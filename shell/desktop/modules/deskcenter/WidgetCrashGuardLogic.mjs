export function parseMap(json) {
    try {
        const parsed = JSON.parse(String(json ?? "{}"));
        if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
            return parsed;
    } catch (_) {}
    return {};
}

export function promotePendingToTripped(pending, tripped, nowMs = Date.now(), currentSessionId = "") {
    const nextTripped = Object.assign({}, tripped || {});
    const newlyTrippedIds = [];
    const src = pending || {};
    const activeSession = String(currentSessionId ?? "");
    for (const id of Object.keys(src)) {
        const entry = src[id];
        if (!id) continue;
        const entrySession = String(entry?.sessionId ?? "");
        if (activeSession.length > 0 && entrySession.length > 0 && entrySession === activeSession)
            continue;
        nextTripped[id] = {
            revision: String(entry?.revision ?? ""),
            reason: "Crashed during previous load",
            trippedAt: Number(nowMs) || 0
        };
        newlyTrippedIds.push(id);
    }
    return {
        pending: {},
        tripped: nextTripped,
        newlyTrippedIds
    };
}

export function isTripped(tripped, packageId, currentRevision = "") {
    if (!packageId || !tripped || !Object.prototype.hasOwnProperty.call(tripped, packageId))
        return false;
    const entry = tripped[packageId];
    const recordedRev = String(entry?.revision ?? "");
    const nextRev = String(currentRevision ?? "");
    if (recordedRev.length > 0 && nextRev.length > 0 && recordedRev !== nextRev)
        return false;
    return true;
}

export function pruneRecovered(tripped, packageId, currentRevision = "") {
    if (!packageId || !tripped || !Object.prototype.hasOwnProperty.call(tripped, packageId))
        return { tripped: tripped || {}, changed: false };
    if (isTripped(tripped, packageId, currentRevision))
        return { tripped, changed: false };
    const next = Object.assign({}, tripped);
    delete next[packageId];
    return { tripped: next, changed: true };
}

export function markLoadStart(pending, packageId, revision = "", nowMs = Date.now(), sessionId = "") {
    if (!packageId) return pending || {};
    const next = Object.assign({}, pending || {});
    const record = {
        revision: String(revision ?? ""),
        startedAt: Number(nowMs) || 0
    };
    const session = String(sessionId ?? "");
    if (session.length > 0)
        record.sessionId = session;
    next[packageId] = record;
    return next;
}

export function markLoadSettled(pending, packageId) {
    if (!packageId || !pending || !Object.prototype.hasOwnProperty.call(pending, packageId))
        return { pending: pending || {}, changed: false };
    const next = Object.assign({}, pending);
    delete next[packageId];
    return { pending: next, changed: true };
}

export function reEnable(tripped, packageId) {
    if (!packageId || !tripped || !Object.prototype.hasOwnProperty.call(tripped, packageId))
        return { tripped: tripped || {}, changed: false };
    const next = Object.assign({}, tripped);
    delete next[packageId];
    return { tripped: next, changed: true };
}

export function listTripped(tripped) {
    const out = [];
    const src = tripped || {};
    for (const id of Object.keys(src).sort()) {
        const entry = src[id];
        if (!entry || typeof entry !== "object") continue;
        out.push({
            id,
            revision: String(entry.revision ?? ""),
            reason: String(entry.reason ?? "Crashed during previous load"),
            trippedAt: Number(entry.trippedAt ?? 0)
        });
    }
    return out;
}
