// InputMethodPlacement.mjs — Pure geometry, spot coordinate resolution,
// and Kimpanel property parsing routines for NextKde liquid glass input method.

export function parseCandidateText(raw) {
    if (!raw) return { text: "", comment: "" };
    const str = String(raw).trim();
    // In Rime / Fcitx5, comment is appended with space or tab: "候选词 编码"
    const match = str.match(/^([^\s]+)\s+(.+)$/);
    if (match) {
        return { text: match[1], comment: match[2].trim() };
    }
    return { text: str, comment: "" };
}

export function parseKimpanelProperty(raw) {
    if (!raw) return null;
    const parts = String(raw).split(":");
    const id = parts[0] || "";
    const shortText = parts[1] || "";
    const icon = parts[2] || "";
    const label = parts[3] || "";
    const type = parts[4] || "";
    const key = id.startsWith("/Fcitx/") ? id.slice(7) : id;
    return {
        id,
        key,
        shortText,
        icon,
        label,
        isMenu: type === "menu"
    };
}

export function resolveGlobalSpotRect(spot, activeWindow, kwinCaret, fallbackScreen) {
    // Missing coordinates are not an absolute (0, 0) spot. In particular,
    // undefined !== 0 used to bypass the real pointer/window fallback.
    const hasSpot = spot && Number.isFinite(spot.x) && Number.isFinite(spot.y)
        && (spot.x !== 0 || spot.y !== 0);
    // 1. If KWin compositor returned a valid global text-input caret (e.g. VS Code, Antigravity, Obsidian)
    if (kwinCaret && kwinCaret.available && kwinCaret.source === "caret") {
        return {
            x: Number(kwinCaret.x) || 0,
            y: Number(kwinCaret.y) || 0,
            width: Number(kwinCaret.width) || 0,
            height: Number(kwinCaret.height) || 20,
            source: "kwin-caret"
        };
    }

    // 2. If spot mode is relative with non-zero coordinates (Wayland dbus clients: Konsole, Firefox, KRunner)
    if (hasSpot && (spot.mode === "relative" || spot.scale > 0)) {
        const scale = spot.scale > 0 ? spot.scale : 1.0;
        const winContent = (activeWindow && activeWindow.contentGeometry)
            || (activeWindow && activeWindow.geometry)
            || { x: 0, y: 0, width: 800, height: 600 };
        return {
            x: Math.round(winContent.x + (spot.x || 0) / scale),
            y: Math.round(winContent.y + (spot.y || 0) / scale),
            width: Math.round((spot.width || 0) / scale),
            height: Math.round((spot.height || 20) / scale),
            source: "window-relative"
        };
    }

    // 3. If spot mode is absolute and non-zero (XWayland clients)
    if (hasSpot) {
        return {
            x: Number(spot.x) || 0,
            y: Number(spot.y) || 0,
            width: Number(spot.width) || 0,
            height: Number(spot.height) || 20,
            source: "absolute"
        };
    }

    // 4. If KWin returned a pointer anchor fallback (clicks in webviews/terminals)
    if (kwinCaret && kwinCaret.available && kwinCaret.x !== undefined && kwinCaret.y !== undefined) {
        return {
            x: Number(kwinCaret.x) || 0,
            y: Number(kwinCaret.y) || 0,
            width: Number(kwinCaret.width) || 0,
            height: Number(kwinCaret.height) || 20,
            source: "kwin-pointer"
        };
    }

    // 5. Fallback: active window top-left or screen safe center
    if (activeWindow && (activeWindow.contentGeometry || activeWindow.geometry)) {
        const geom = activeWindow.contentGeometry || activeWindow.geometry;
        return {
            x: geom.x + 32,
            y: geom.y + 64,
            width: 0,
            height: 20,
            source: "fallback-window"
        };
    }

    const scr = fallbackScreen || { x: 0, y: 0, width: 1920, height: 1080 };
    return {
        x: Math.round(scr.x + scr.width / 2 - 120),
        y: Math.round(scr.y + scr.height / 2),
        width: 0,
        height: 20,
        source: "fallback-screen"
    };
}

export function placeCandidatePopup(safeBounds, anchorRect, popupWidth, popupHeight, gap = 8) {
    const safe = safeBounds || { x: 0, y: 0, width: 1920, height: 1080 };
    const anchor = anchorRect || { x: 0, y: 0, width: 0, height: 20 };
    const w = Math.max(1, Math.round(popupWidth || 200));
    const h = Math.max(1, Math.round(popupHeight || 60));

    // Default: place directly beneath the anchor caret left-aligned
    let x = anchor.x;
    let y = anchor.y + anchor.height + gap;

    const safeBottom = safe.y + safe.height;
    const safeRight = safe.x + safe.width;

    // Flip upwards if expanding downwards exceeds bottom safe boundary (e.g. Dock / bottom edge)
    if (y + h > safeBottom && (anchor.y - gap - h) >= safe.y) {
        y = anchor.y - gap - h;
    }

    // Clamp horizontally within screen safe bounds
    if (x + w > safeRight) {
        x = Math.max(safe.x, safeRight - w);
    }
    if (x < safe.x) {
        x = safe.x;
    }

    // Clamp vertically if popup is taller than safe bounds
    if (y + h > safeBottom) {
        y = Math.max(safe.y, safeBottom - h);
    }
    if (y < safe.y) {
        y = safe.y;
    }

    return {
        x: Math.round(x),
        y: Math.round(y),
        width: w,
        height: h
    };
}
