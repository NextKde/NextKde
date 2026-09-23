// Process-side identity hints for a window's desktop entry.
//
// A Wayland window's app id is whatever its toolkit decides to report, and that
// is often not the desktop file name: an Electron build reports its product name
// (`com.yesha.net`) while its installed entry is named after the AppImage
// (`yeshayun-4.0.11-linux-amd64.desktop`). No amount of id normalisation bridges
// those two, and KWin's `desktopFileName` / `resourceClass` / `resourceName` are
// all aliases of that same reported id, so they add nothing.
//
// The window's PID is the one fact that cannot lie. The shell probes /proc once
// per PID and retries a failed lookup with what the process actually is.
//
// This module owns the probe command, its parsing and the match, so all three
// can be exercised without a session: the QML adapter runs the probe, the tests
// feed it synthetic output.

// Process names that identify a runtime or a wrapper rather than an application.
// Matching one of these against a desktop id would hand a window an unrelated
// app's icon, so they are dropped before they can be used as evidence.
const GENERIC_PROCESS_NAMES = new Set([
    "electron", "appimage", "apprun", "runtime", "sandbox",
    "sh", "bash", "dash", "zsh", "fish", "env", "nice", "setsid", "timeout",
    "node", "bun", "deno", "python", "python2", "python3", "java", "mono",
    "dotnet", "wine", "wine64", "wine-preloader", "wineserver",
    "flatpak", "flatpak-session-helper", "bwrap", "xdg-desktop-portal",
    "crashpad_handler", "chrome_crashpad_handler",
    // Session infrastructure. These own no application window, and several of
    // their names are short enough to collide with an unrelated desktop id.
    "init", "systemd", "dbus-daemon", "dbus-broker", "plasmashell",
    "kwin_wayland", "ksmserver", "kglobalacceld", "kded5", "kded6",
    "kdeinit5", "kdeinit6", "klauncher", "xwayland", "xorg", "polkitd",
]);

function baseName(value) {
    const path = String(value ?? "").trim();
    if (!path)
        return "";
    const cut = path.lastIndexOf("/");
    return cut >= 0 ? path.slice(cut + 1) : path;
}

// Prefer an entry that can actually supply an icon; identity is still worth
// keeping when none can, because the display name comes from the same entry.
function withIconOrFirst(items) {
    for (let i = 0; i < items.length; i++) {
        if (items[i].icon)
            return items[i].entry;
    }
    return items[0].entry;
}

// The probe command. It prints exactly three lines — one hint source each — and
// must stay in sync with parseProbeOutput.
//
// Two details are load-bearing. `/proc/<pid>/environ` and `/proc/<pid>/cmdline`
// are NUL-separated, so `tr` has to run before any line-oriented tool can be
// used on them, and `printf '%s\n' "$(…)"` is what guarantees a line exists even
// when the underlying read fails (a missing line would shift every later hint
// into the wrong slot). `sed -n '1p'` rather than `head -n 1` keeps the reader
// from being killed by SIGPIPE mid-pipeline. The PID is coerced to an integer
// before it reaches the shell.
export function probeCommand(pid) {
    const target = String(Math.max(0, Math.trunc(Number(pid) || 0)));
    return ["sh", "-c",
        "p=\"$1\"\n"
            + "printf '%s\\n' \"$(tr '\\0' '\\n' < \"/proc/$p/environ\" 2>/dev/null | sed -n 's|^APPIMAGE=||p')\"\n"
            + "printf '%s\\n' \"$(readlink \"/proc/$p/exe\" 2>/dev/null)\"\n"
            + "printf '%s\\n' \"$(tr '\\0' '\\n' < \"/proc/$p/cmdline\" 2>/dev/null | sed -n '1p')\"",
        "kos-window-identity", target];
}

// Turn probe output into hints, most reliable first.
//
// APPIMAGE is the exact path the runtime was launched from, and external
// installers name the desktop file after that same file name. The executable and
// argv[0] cover builds that are not AppImages, where the binary usually shares
// its name with the entry. `/proc/<pid>/comm` is deliberately not read: toolkits
// rewrite it (`electron` for every Electron app), so it names the runtime.
export function parseProbeOutput(text) {
    const lines = String(text ?? "").split("\n");
    const hints = [];

    function push(value) {
        const name = baseName(value).replace(/\.appimage$/i, "");
        // Below four characters a hint is more likely to collide with an
        // unrelated desktop id than to identify this one.
        if (name.length < 4 || name.length > 96)
            return;
        if (GENERIC_PROCESS_NAMES.has(name.toLowerCase()))
            return;
        if (hints.indexOf(name) < 0)
            hints.push(name);
    }

    push(lines[0]);
    push(lines[1]);
    push(lines[2]);
    return hints;
}

// Retry a failed desktop-entry lookup with process hints.
//
// `normalize` is the shell's shared id normaliser, `hasIcon` reports whether an
// entry can supply an icon (optional). Only unambiguous evidence is accepted: a
// desktop id that normalises to the hint exactly always wins, while a hint merely
// contained in a longer id (an AppImage keeps its version in the file name) is
// taken only when it singles out one entry. Two candidates mean the hint is too
// generic to decide, and guessing would be worse than the generic icon.
// QML hands `list<T>` properties to JavaScript as a V4Sequence, not as an
// Array: `Array.isArray()` is false there even though length and indexing work.
// Guarding on Array.isArray therefore disables this module silently inside the
// shell while every Node test still passes, so accept any array-like sequence.
function isSequence(value) {
    return !!value && typeof value === "object"
        && typeof value.length === "number" && value.length >= 0;
}

export function matchEntryByHints(entries, hints, normalize, hasIcon) {
    if (!isSequence(entries) || !entries.length
            || !isSequence(hints) || !hints.length
            || typeof normalize !== "function")
        return null;

    const indexed = [];
    for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        const key = normalize(entry?.id ?? "");
        if (!key)
            continue;
        indexed.push({
            entry: entry,
            key: key,
            icon: typeof hasIcon === "function" ? !!hasIcon(entry) : true,
        });
    }

    for (let h = 0; h < hints.length; h++) {
        const needle = normalize(hints[h]);
        if (needle.length < 4)
            continue;
        const exact = [];
        const contained = [];
        for (let i = 0; i < indexed.length; i++) {
            if (indexed[i].key === needle)
                exact.push(indexed[i]);
            else if (indexed[i].key.indexOf(needle) >= 0)
                contained.push(indexed[i]);
        }
        if (exact.length)
            return withIconOrFirst(exact);
        if (contained.length === 1)
            return contained[0].entry;
    }
    return null;
}
