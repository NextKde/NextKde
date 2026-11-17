// Window ownership is separate from application presentation. A helper keeps
// its raw app ID, title and handle; Stage consumes the resolved family instead.
// Explicit compositor parents are authoritative. Process ancestry is only a
// fallback when the helper and its nearest window-owning ancestor share a
// private application directory and the helper has no independent desktop ID.

const PROBE_MARKER = "KOS_WINDOW_ANCESTRY_V1";
const PROBE_END = "KOS_WINDOW_ANCESTRY_END";
const MAX_DEPTH = 16;

export function probeCommand(pid, identityCommand) {
    const command = identityCommand.slice();
    // Append to the existing three-line identity probe: no extra process per
    // window. Fields are fixed-width records, never evaluated as shell code.
    // The final stamp rejects a process that exited/recycled during the read.
    command[2] += '\n' + [
        'set -f',
        'target="$p"',
        'printf "%s\\n" "' + PROBE_MARKER + '"',
        'depth=0',
        'while [ "$p" -gt 1 ] && [ "$depth" -lt 16 ]; do',
        '  IFS= read -r state < "/proc/$p/stat" 2>/dev/null || break',
        '  state=${state##*) }',
        '  set -- $state',
        '  parent=$2; stamp=${20}',
        '  exe=$(readlink "/proc/$p/exe" 2>/dev/null) || break',
        '  printf "%s\\n" "$p" "$parent" "$stamp" "$exe"',
        '  [ "$parent" -ne "$p" ] || break',
        '  p=$parent; depth=$((depth + 1))',
        'done',
        'printf "%s\\n" "' + PROBE_END + '"',
        'if IFS= read -r state < "/proc/$target/stat" 2>/dev/null; then',
        '  state=${state##*) }; set -- $state',
        '  printf "%s\\n" "${20}"',
        '  readlink "/proc/$target/exe" 2>/dev/null',
        'fi',
    ].join('\n');
    return command;
}

export function parseProcessProbe(text, pid) {
    const lines = String(text || "").split('\n');
    const start = lines.indexOf(PROBE_MARKER);
    const end = lines.indexOf(PROBE_END, start + 1);
    if (start < 3 || end < start || (end - start - 1) % 4 !== 0)
        return [];
    const nodes = [];
    const seen = new Set();
    for (let i = start + 1; i < end; i += 4) {
        const node = { pid: Number(lines[i]), ppid: Number(lines[i + 1]),
            startTime: lines[i + 2], exe: lines[i + 3] };
        if (!Number.isSafeInteger(node.pid) || node.pid <= 1
                || !Number.isSafeInteger(node.ppid) || node.ppid < 0
                || !/^\d+$/.test(node.startTime) || !node.exe.startsWith('/')
                || node.exe.endsWith(' (deleted)') || seen.has(node.pid)
                || (nodes.length && nodes[nodes.length - 1].ppid !== node.pid))
            return [];
        seen.add(node.pid);
        nodes.push(node);
    }
    const self = nodes[0];
    if (!self || self.pid !== Number(pid) || nodes.length > MAX_DEPTH
            || lines[end + 1] !== self.startTime || lines[end + 2] !== self.exe)
        return [];
    return nodes;
}

export function naturalKey(record) {
    return record.identity?.desktopId || record.identity?.rawAppId
        || (record.pid > 0 ? "pid:" + record.pid : "window:" + record.windowId);
}

// Shared system directories, home folders and application catalogs are not
// proof of shared application ownership. A private /opt/app or portable app
// directory is. In particular /usr/bin programs never adopt their children.
function applicationDirectory(exe) {
    if (!exe || !exe.startsWith('/') || exe.includes('/../'))
        return "";
    const executable = exe.slice(exe.lastIndexOf('/') + 1).toLowerCase();
    if (/^(electron|node|python[\d.]*|java|ruby|perl|sh|bash|dash|zsh|fish|wine[\d]*|bwrap|flatpak)$/.test(executable))
        return "";
    let dir = exe.slice(0, exe.lastIndexOf('/'));
    if (dir.endsWith('/bin'))
        dir = dir.slice(0, -4);
    const base = dir.slice(dir.lastIndexOf('/') + 1).toLowerCase();
    if (!dir || /^(bin|sbin|lib|lib32|lib64|libexec|share|opt|usr|local|home|tmp|var|run|app|apps|applications|programs|packages|downloads|desktop|documents|桌面|下载|文档)$/.test(base)
            || /linux-gnu$/.test(base) || /^\/home\/[^/]+$/.test(dir)
            || dir === '/root' || dir.endsWith('/.local')
            || dir.endsWith('/.cache') || dir.endsWith('/.config'))
        return "";
    return dir;
}

export function sharesApplicationDirectory(child, parent) {
    const directory = applicationDirectory(parent?.exe);
    return !!directory && !!child?.exe && child.exe.startsWith(directory + '/');
}

// Decorate NEW records only, before WindowService publishes their revision.
// processByPid[pid] is undefined while probing, [] on failure, or a bounded
// chain starting with the process itself. A failed probe is settled, not a
// permanent exemption from Stage's automatic minimization.
export function resolveFamilies(records, processByPid = {}) {
    const byHandle = new Map();
    const byPid = new Map();
    const owners = new Map();
    const reasons = new Map();
    const pending = new Map();
    for (const r of records) {
        if (r.handleId)
            byHandle.set(r.handleId, r);
        if (r.pid > 0) {
            if (!byPid.has(r.pid)) byPid.set(r.pid, []);
            byPid.get(r.pid).push(r);
        }
        pending.set(r, r.pid > 0 && processByPid[r.pid] === undefined);
    }
    for (const r of records) {
        const explicit = byHandle.get(r.parentHandleId);
        if (explicit && explicit !== r) {
            owners.set(r, explicit);
            reasons.set(r, 'transient');
            continue;
        }
        const chain = processByPid[r.pid] || [];
        for (let i = 1; i < chain.length; i++) {
            const ancestor = chain[i];
            const candidates = byPid.get(ancestor.pid);
            if (!candidates?.length) continue;
            // The nearest window-owning ancestor is a boundary, even if it
            // cannot be accepted. Never jump over an independent application.
            const owner = candidates[0];
            const ownerKey = naturalKey(owner);
            if (candidates.some(w => naturalKey(w) !== ownerKey)) break;
            const ownerChain = processByPid[owner.pid];
            if (ownerChain === undefined) pending.set(r, true);
            const ownerProcess = ownerChain?.[0];
            if (!ownerProcess || ownerProcess.startTime !== ancestor.startTime
                    || ownerProcess.exe !== ancestor.exe) break;
            // Hidden desktop entries also register internal browsers/viewers.
            // They are not independent launchers, but still require both the
            // ancestor stamp and private directory evidence below.
            if (r.identity?.hasDesktopEntry && !r.identity?.desktopEntryNoDisplay
                    && naturalKey(r) !== ownerKey) break;
            if (!sharesApplicationDirectory(chain[0], ownerProcess)) break;
            owners.set(r, owner);
            reasons.set(r, 'process');
            break;
        }
    }
    for (const r of records) {
        let owner = r;
        let unresolved = pending.get(r);
        const seen = new Set([r]);
        while (owners.has(owner)) {
            owner = owners.get(owner);
            if (seen.has(owner)) { owner = r; break; }
            seen.add(owner);
            unresolved = unresolved || pending.get(owner);
        }
        r.familyKey = naturalKey(owner);
        r.ownerWindowId = owner === r ? "" : owner.windowId;
        r.ownerHandleId = owner === r ? "" : owner.handleId;
        r.familyReason = owner === r ? 'application' : reasons.get(r);
        r.familyPending = !!unresolved;
    }
    return records;
}
