// All coordinates are logical pixels, including negative monitor origins.
export function validAnchor(anchor) {
    return !!anchor?.available
        && [anchor.x, anchor.y, anchor.width, anchor.height].every(Number.isFinite)
        && anchor.width >= 0 && anchor.height >= 0;
}

export function screenForAnchor(screens, anchor, fallback) {
    if (!validAnchor(anchor))
        return fallback;
    const x = anchor.x + anchor.width / 2;
    const y = anchor.y + anchor.height / 2;
    return screens.find(screen => x >= screen.x && x < screen.x + screen.width
        && y >= screen.y && y < screen.y + screen.height) || fallback;
}

export function bounds(screen, anchor) {
    const full = { x: 0, y: 0, width: screen.width, height: screen.height };
    if (!validAnchor(anchor)
        || ![anchor.areaX, anchor.areaY, anchor.areaWidth, anchor.areaHeight].every(Number.isFinite))
        return full;
    const x = Math.max(0, anchor.areaX - screen.x);
    const y = Math.max(0, anchor.areaY - screen.y);
    const right = Math.min(screen.width, anchor.areaX + anchor.areaWidth - screen.x);
    const bottom = Math.min(screen.height, anchor.areaY + anchor.areaHeight - screen.y);
    return right > x && bottom > y ? { x, y, width: right - x, height: bottom - y } : full;
}

export function place(screen, anchor, width, height) {
    const area = bounds(screen, anchor);
    const margin = Math.min(12, area.width / 2, area.height / 2);
    const left = area.x + margin;
    const top = area.y + margin;
    const right = Math.max(left, area.x + area.width - margin - width);
    const bottom = Math.max(top, area.y + area.height - margin - height);
    const clamp = (value, min, max) => Math.max(min, Math.min(value, max));
    if (!validAnchor(anchor))
        return { x: clamp((screen.width - width) / 2, left, right),
                 y: clamp(Math.round(screen.height * 0.16), top, bottom) };
    const x = anchor.x - screen.x;
    const y = anchor.y - screen.y;
    const gap = 8;
    // Open below the caret/pointer. Flip upward if there is insufficient room;
    // right-edge alignment keeps the anchor close without leaving the output.
    const below = y + anchor.height + gap;
    return {
        x: clamp(x + width <= area.x + area.width - margin ? x : x + anchor.width - width, left, right),
        y: clamp(below <= bottom ? below : y - gap - height, top, bottom)
    };
}
