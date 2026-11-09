// KWin UUIDs, never WindowService's synthetic window-N action handles.
export function windowKey(value) {
    return String(value || "").replace(/^\{|\}$/g, "").toLowerCase();
}

function appKey(value) {
    return String(value || "").trim().toLowerCase()
        .replace(/\.desktop$/, "").replace(/\s+/g, "-");
}

export function selectTarget(entries, windowId, appIds) {
    const wanted = windowKey(windowId);
    const exact = entries.find(entry => wanted
        && windowKey(entry.target.windowId) === wanted);
    if (exact)
        return exact;

    const apps = appIds.map(appKey).filter(Boolean);
    // A grouped launcher represents all its windows. A different window's
    // separate icon must never become this window's fallback endpoint.
    return entries.find(entry => !entry.target.windowId
        && apps.includes(appKey(entry.target.appId))) || null;
}

export function surfaceRect(target, originX, originY, surfaceWidth, surfaceHeight) {
    const values = [target.x, target.y, target.width, target.height, originX, originY];
    if (!values.every(Number.isFinite) || target.width < 1 || target.height < 1)
        return null;
    // Plasma's protocol takes integer surface-local logical coordinates.
    // Do not add output offsets twice or multiply by the output pixel scale.
    let left = Math.floor(target.x - originX);
    let top = Math.floor(target.y - originY);
    const right = Math.ceil(target.x - originX + target.width);
    const bottom = Math.ceil(target.y - originY + target.height);
    let width = right - left;
    let height = bottom - top;
    // KOS slides its auto-hidden glass beyond a permanently mapped surface.
    // Retain the icon's along-edge slot, clipping its outward extent to the
    // surface edge. In particular a left Dock must not wrap unsigned x or
    // lose its target and fall back to the cursor while hidden.
    if (Number.isFinite(surfaceWidth) && surfaceWidth >= 1) {
        left = Math.max(0, Math.min(left, Math.floor(surfaceWidth) - 1));
        width = Math.max(1, Math.min(right, Math.floor(surfaceWidth)) - left);
    }
    if (Number.isFinite(surfaceHeight) && surfaceHeight >= 1) {
        top = Math.max(0, Math.min(top, Math.floor(surfaceHeight) - 1));
        height = Math.max(1, Math.min(bottom, Math.floor(surfaceHeight)) - top);
    }
    if (left < 0 || top < 0)
        return null;
    return { x: left, y: top, width, height };
}
