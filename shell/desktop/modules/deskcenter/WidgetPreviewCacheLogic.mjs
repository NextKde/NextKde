export const CACHE_FORMAT_VERSION = 9;
export const DEFAULT_MAX_ENTRIES = 200;
export const DEFAULT_MAX_CONCURRENT = 2;

export function safeFileName(name) {
    return typeof name === "string" && /^[A-Za-z0-9._-]+\.png$/.test(name);
}

export function buildSlotKey(widgetId, sizeValue) {
    return String(widgetId || "") + "@" + String(sizeValue || "");
}

export function buildThemeKey(appearance, paintInQml, layer1Color, dpr) {
    const app = appearance && typeof appearance === "object" ? appearance : {};
    const pal = app.palette && typeof app.palette === "object" ? app.palette : {};
    return [
        String(app.style || ""),
        app.isDark ? "dark" : "light",
        app.transparent ? "glass" : "opaque",
        String(app.locale || "en"),
        paintInQml ? "tonal" : "native",
        String(layer1Color || ""),
        String(pal.primary || ""),
        String(pal.surface || ""),
        String(pal.onSurface || ""),
        String(Math.round((Number(dpr) || 1) * 100)),
    ].join("|");
}

function fnv1a32(str, seed) {
    let h = seed >>> 0;
    for (let i = 0; i < str.length; i++) {
        h ^= str.charCodeAt(i);
        h = Math.imul(h, 0x01000193) >>> 0;
    }
    return ("00000000" + h.toString(16)).slice(-8);
}

function sanitizeSlug(text, maxLen) {
    const clean = String(text || "widget").replace(/[^A-Za-z0-9._-]/g, "_");
    return (clean.length > maxLen ? clean.slice(0, maxLen) : clean) || "widget";
}

export function buildCacheFileName(widgetId, revision, sizeValue, themeKey) {
    const payload = [
        String(CACHE_FORMAT_VERSION),
        String(widgetId || ""),
        String(revision || ""),
        String(sizeValue || ""),
        String(themeKey || ""),
    ].join("|");
    const h1 = fnv1a32(payload, 0x811c9dc5);
    const h2 = fnv1a32(payload, 0x9e3779b9);
    const idSlug = sanitizeSlug(widgetId, 48);
    const sizeSlug = sanitizeSlug(sizeValue, 16);
    return idSlug + "-" + sizeSlug + "-" + h1 + h2 + ".png";
}

function cloneMap(map) {
    const out = Object.create(null);
    if (!map || typeof map !== "object") return out;
    for (const k of Object.keys(map)) {
        const entry = map[k];
        if (entry && typeof entry === "object")
            out[k] = Object.assign({}, entry);
    }
    return out;
}

function collectReferencedFiles(map) {
    const used = new Set();
    for (const k of Object.keys(map)) {
        const f = map[k] && map[k].fileName;
        if (safeFileName(f)) used.add(f);
    }
    return used;
}

export function parseIndex(rawJson) {
    const out = Object.create(null);
    if (typeof rawJson !== "string" || rawJson.trim().length === 0)
        return out;
    let parsed;
    try {
        parsed = JSON.parse(rawJson);
    } catch (_e) {
        return out;
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
        return out;
    for (const key of Object.keys(parsed)) {
        const entry = parsed[key];
        if (!entry || typeof entry !== "object") continue;
        if (typeof entry.widgetId !== "string" || entry.widgetId.length === 0) continue;
        if (typeof entry.sizeValue !== "string" || entry.sizeValue.length === 0) continue;
        if (!safeFileName(entry.fileName)) continue;
        out[key] = {
            widgetId: entry.widgetId,
            packageId: typeof entry.packageId === "string" && entry.packageId.length > 0
                ? entry.packageId
                : entry.widgetId,
            sizeValue: entry.sizeValue,
            isDefaultSize: !!entry.isDefaultSize,
            fileName: entry.fileName,
            revision: String(entry.revision || ""),
            themeKey: String(entry.themeKey || ""),
            lastUsedMs: Number(entry.lastUsedMs) || 0,
        };
    }
    return out;
}

export function resolveSlot(indexMap, slotKey, desiredFileName) {
    const entry = indexMap && typeof indexMap === "object" ? indexMap[slotKey] : null;
    if (!entry || !safeFileName(entry.fileName))
        return { status: "miss", exactFileName: "", fallbackFileName: "" };
    if (entry.fileName === desiredFileName)
        return { status: "hit", exactFileName: entry.fileName, fallbackFileName: "" };
    return { status: "stale", exactFileName: "", fallbackFileName: entry.fileName };
}

export function commitEntry(indexMap, meta, maxEntries = DEFAULT_MAX_ENTRIES) {
    const next = cloneMap(indexMap);
    const widgetId = String(meta && meta.widgetId ? meta.widgetId : "");
    const sizeValue = String(meta && meta.sizeValue ? meta.sizeValue : "");
    const fileName = String(meta && meta.fileName ? meta.fileName : "");
    if (!widgetId || !sizeValue || !safeFileName(fileName))
        return { entries: next, removedFiles: [] };

    const slotKey = buildSlotKey(widgetId, sizeValue);
    const candidatesToRemove = [];
    if (next[slotKey] && next[slotKey].fileName && next[slotKey].fileName !== fileName)
        candidatesToRemove.push(next[slotKey].fileName);

    next[slotKey] = {
        widgetId: widgetId,
        packageId: String(meta.packageId || widgetId),
        sizeValue: sizeValue,
        isDefaultSize: !!(meta && meta.isDefaultSize),
        fileName: fileName,
        revision: String(meta && meta.revision ? meta.revision : ""),
        themeKey: String(meta && meta.themeKey ? meta.themeKey : ""),
        lastUsedMs: Number(meta && meta.lastUsedMs) || Date.now(),
    };

    const limit = Math.max(1, Number(maxEntries) || DEFAULT_MAX_ENTRIES);
    const keys = Object.keys(next);
    if (keys.length > limit) {
        keys.sort((a, b) => {
            const ea = next[a];
            const eb = next[b];
            if (!!ea.isDefaultSize !== !!eb.isDefaultSize)
                return ea.isDefaultSize ? 1 : -1; // evict non-default first
            return (Number(ea.lastUsedMs) || 0) - (Number(eb.lastUsedMs) || 0);
        });
        const excess = keys.length - limit;
        for (let i = 0; i < excess; i++) {
            const k = keys[i];
            if (k === slotKey) continue;
            if (next[k] && next[k].fileName)
                candidatesToRemove.push(next[k].fileName);
            delete next[k];
        }
        // In case limit is 1 and slotKey wasn't first, loop handles excess above;
        // if slotKey happened to sit inside the first `excess` slots, trim one extra non-slotKey item.
        if (Object.keys(next).length > limit) {
            for (const k of keys) {
                if (k !== slotKey && next[k]) {
                    if (next[k].fileName) candidatesToRemove.push(next[k].fileName);
                    delete next[k];
                    if (Object.keys(next).length <= limit) break;
                }
            }
        }
    }

    const stillUsed = collectReferencedFiles(next);
    const removedFiles = [];
    for (const f of candidatesToRemove) {
        if (safeFileName(f) && !stillUsed.has(f) && removedFiles.indexOf(f) < 0)
            removedFiles.push(f);
    }
    return { entries: next, removedFiles: removedFiles };
}

export function touchEntry(indexMap, slotKey, nowMs) {
    if (!indexMap || !indexMap[slotKey])
        return { entries: cloneMap(indexMap), changed: false };
    const next = cloneMap(indexMap);
    const ts = Number(nowMs) || Date.now();
    if (next[slotKey].lastUsedMs === ts)
        return { entries: next, changed: false };
    next[slotKey].lastUsedMs = ts;
    return { entries: next, changed: true };
}

export function invalidateSlotFile(indexMap, slotKey, fileName) {
    const next = cloneMap(indexMap);
    if (!next[slotKey] || next[slotKey].fileName !== fileName)
        return { entries: next, changed: false };
    delete next[slotKey];
    return { entries: next, changed: true };
}

function toStringSet(listLike) {
    const set = new Set();
    if (listLike && typeof listLike !== "string" && typeof listLike.length === "number") {
        for (let i = 0; i < listLike.length; i++) {
            const s = String(listLike[i] || "");
            if (s.length > 0) set.add(s);
        }
    }
    return set;
}

export function pruneForCatalog(indexMap, validWidgetIds, blockedPackageIds) {
    const validSet = toStringSet(validWidgetIds);
    const blockedSet = toStringSet(blockedPackageIds);
    const next = cloneMap(indexMap);
    const candidateFiles = [];
    let changed = false;

    for (const k of Object.keys(next)) {
        const entry = next[k];
        const pkgId = entry.packageId || entry.widgetId;
        if (!validSet.has(entry.widgetId) || blockedSet.has(pkgId)) {
            if (entry.fileName) candidateFiles.push(entry.fileName);
            delete next[k];
            changed = true;
        }
    }

    const stillUsed = collectReferencedFiles(next);
    const removedFiles = [];
    for (const f of candidateFiles) {
        if (safeFileName(f) && !stillUsed.has(f) && removedFiles.indexOf(f) < 0)
            removedFiles.push(f);
    }
    return { entries: next, removedFiles: removedFiles, changed: changed };
}

export function createQueueState() {
    return { active: [], pending: [] };
}

function promoteQueue(active, pending, maxConcurrent) {
    const limit = Math.max(1, Number(maxConcurrent) || DEFAULT_MAX_CONCURRENT);
    const nextActive = active.slice();
    const nextPending = pending.slice();
    while (nextActive.length < limit && nextPending.length > 0) {
        let pickIdx = nextPending.findIndex(item => item.isDefaultSize === true);
        if (pickIdx < 0) pickIdx = 0;
        nextActive.push(nextPending[pickIdx]);
        nextPending.splice(pickIdx, 1);
    }
    return { active: nextActive, pending: nextPending };
}

export function enqueueRender(state, req, maxConcurrent = DEFAULT_MAX_CONCURRENT) {
    const cur = state || createQueueState();
    const slotKey = String(req && req.slotKey ? req.slotKey : "");
    const fileName = String(req && req.fileName ? req.fileName : "");
    if (!slotKey || !safeFileName(fileName))
        return cur;

    const item = {
        slotKey: slotKey,
        fileName: fileName,
        isDefaultSize: !!(req && req.isDefaultSize),
    };

    const active = cur.active.slice();
    const activeIdx = active.findIndex(a => a.slotKey === slotKey);
    if (activeIdx >= 0) {
        active[activeIdx] = item;
        return { active: active, pending: cur.pending.slice() };
    }

    const pending = cur.pending.filter(p => p.slotKey !== slotKey);
    pending.push(item);
    return promoteQueue(active, pending, maxConcurrent);
}

export function releaseRender(state, slotKey, maxConcurrent = DEFAULT_MAX_CONCURRENT) {
    const cur = state || createQueueState();
    const key = String(slotKey || "");
    const active = cur.active.filter(a => a.slotKey !== key);
    const pending = cur.pending.filter(p => p.slotKey !== key);
    return promoteQueue(active, pending, maxConcurrent);
}

export function isRenderActive(state, slotKey, fileName) {
    if (!state || !Array.isArray(state.active)) return false;
    const key = String(slotKey || "");
    const file = String(fileName || "");
    return state.active.some(a => a.slotKey === key && (!file || a.fileName === file));
}
