// Density changes spacing, never the icon artwork or the two-line label.
export const densities = ["comfortable", "compact", "dense"];

// Use spare vertical space for one more row instead of leaving a visible
// bottom gap. The extra row must keep at least a 3 px gutter; otherwise the
// requested density gap and its bottom remainder are retained.
export function rowLayout(validHeight, cellHeight, gap) {
    const preferred = Math.max(1,
        Math.floor((validHeight + gap) / (cellHeight + gap)));
    const candidate = preferred + 1;
    if (candidate > 1) {
        const candidateGap = (validHeight - candidate * cellHeight)
            / (candidate - 1);
        if (candidateGap >= 3) {
            return {
                count: candidate,
                pitch: cellHeight + candidateGap,
                gap: candidateGap
            };
        }
    }
    return { count: preferred, pitch: cellHeight + gap, gap: gap };
}

// Slot indices are column-major: one column is filled top-to-bottom before
// the next. Right alignment fills from the right edge, left alignment from
// the left edge of the desktop file area.
export function columnForSlot(slot, rowCount, columnCount, alignment) {
    const index = Math.floor(slot / rowCount);
    return alignment === "left" ? index : columnCount - 1 - index;
}

export function slotForCell(column, row, rowCount, columnCount, alignment) {
    const index = alignment === "left" ? column : columnCount - 1 - column;
    return index * rowCount + row;
}

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
