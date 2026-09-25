// Density changes spacing, never the icon artwork or the two-line label.
export const densities = ["comfortable", "compact", "dense"];

export function metrics(baseWidth, baseHeight, iconSize, density, lineHeight) {
    const mode = densities.includes(density) ? density : "comfortable";
    const gap = mode === "comfortable" ? 16 : mode === "compact" ? 8 : 6;
    const iconTop = mode === "comfortable" ? 8 : mode === "compact" ? 4 : 3;
    const labelGap = mode === "comfortable" ? 3 : mode === "compact" ? 2 : 1;
    const cellWidth = mode === "comfortable" ? baseWidth
        : mode === "compact" ? Math.max(108, iconSize + 48)
        : Math.max(96, iconSize + 36);
    const contentHeight = iconTop + iconSize + labelGap + Math.ceil(lineHeight) * 2 + 6;
    const cellHeight = mode === "comfortable" ? Math.max(baseHeight, contentHeight) : contentHeight;
    return { cellWidth, cellHeight, gap, iconTop, labelGap };
}

// Keep valid manual placements, then place displaced/newly visible entries in
// free slots. A smaller field must never leave icons underneath the widgets.
export function reflowSlots(ids, previous, capacity) {
    const next = {};
    const occupied = new Set();
    const pending = [];
    for (const id of ids) {
        const slot = previous[id];
        if (Number.isInteger(slot) && slot >= 0 && slot < capacity && !occupied.has(slot)) {
            next[id] = slot;
            occupied.add(slot);
        } else {
            pending.push(id);
        }
    }
    let slot = 0;
    for (const id of pending) {
        while (occupied.has(slot)) slot++;
        if (slot >= capacity) break;
        next[id] = slot;
        occupied.add(slot++);
    }
    return next;
}
