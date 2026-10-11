export const sizeOrder = ["small", "medium", "large"];

const variants = {
    clock: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    weather: { small: [2, 1], medium: [3, 1], large: [3, 2] },
    calendar: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    todo: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    system: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    activity: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    music: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    notifications: { small: [2, 1], medium: [2, 2], large: [3, 2] }
};

export function normalizedSize(size) {
    return sizeOrder.includes(String(size)) ? String(size) : "medium";
}

export function spanFor(widgetId, size) {
    const pair = variants[String(widgetId)]?.[normalizedSize(size)] ?? [1, 1];
    return [pair[0], pair[1]];
}

export function packWidgets(definitions, columnCount, rowCount, preserveOrder = false) {
    const sorted = preserveOrder ? definitions.slice() : definitions.slice().sort((left, right) =>
        right.priority - left.priority);
    const occupied = [];
    const result = [];
    for (let row = 0; row < rowCount; row++)
        occupied[row] = Array(columnCount).fill(false);

    for (const widget of sorted) {
        let placed = false;
        const firstRow = widget.row ?? 0;
        const lastRow = widget.row ?? (rowCount - widget.rows);
        const firstColumn = widget.column ?? 0;
        const lastColumn = widget.column ?? (columnCount - widget.columns);
        for (let row = firstRow; row <= lastRow && !placed; row++) {
            for (let column = firstColumn; column <= lastColumn && !placed; column++) {
                let fits = true;
                for (let y = row; y < row + widget.rows && fits; y++) {
                    if (y < 0 || y >= rowCount) {
                        fits = false;
                        break;
                    }
                    for (let x = column; x < column + widget.columns; x++) {
                        if (x < 0 || x >= columnCount || occupied[y][x]) {
                            fits = false;
                            break;
                        }
                    }
                }
                if (!fits)
                    continue;
                for (let y = row; y < row + widget.rows; y++)
                    for (let x = column; x < column + widget.columns; x++)
                        occupied[y][x] = true;
                result.push({ id: widget.id, column, row,
                    columns: widget.columns, rows: widget.rows });
                placed = true;
            }
        }
    }
    return result;
}

// Each edge has its own grid; the file field occupies the space between them.
// Explicit user order takes precedence over the default widget priorities.
export function packWidgetSides(definitions, leftColumns, rightColumns, rowCount) {
    const result = [];
    for (const side of ["left", "right"]) {
        const widgets = definitions.filter(widget => (widget.side || "left") === side);
        const width = side === "right" ? rightColumns : leftColumns;
        if (width <= 0) continue;
        result.push(...packWidgets(widgets, width, rowCount, true).map(placement =>
            Object.assign({}, placement, {side: side})));
    }
    return result;
}

// Pixel rectangles allow a card to grow continuously between preset sizes.
// A saved vertical offset is a preferred position; other cards flow around it.
export function packPixelSides(definitions, leftWidth, rightWidth, availableHeight, gap) {
    const result = [];
    for (const side of ["left", "right"]) {
        const width = side === "right" ? rightWidth : leftWidth;
        const occupied = [];
        const widgets = definitions.filter(w => (w.side || "left") === side);
        // Place manually positioned cards before flowing the automatic cards.
        const ordered = widgets.filter(w => Number.isFinite(w.topOffset))
            .concat(widgets.filter(w => !Number.isFinite(w.topOffset)));
        for (const widget of ordered) {
            const cardWidth = Math.min(width, Math.max(120, widget.width));
            const cardHeight = Math.min(availableHeight, Math.max(120, widget.height));
            const preferredY = Number.isFinite(widget.topOffset)
                ? Math.max(0, Math.min(availableHeight - cardHeight, widget.topOffset)) : 0;
            const ys = [preferredY, 0].concat(occupied.map(r => r.y + r.height + gap));
            const xs = [0].concat(occupied.map(r => r.x + r.width + gap));
            const candidates = [];
            for (const y of ys) for (const x of xs) candidates.push({x, y});
            candidates.sort((a, b) =>
                Math.abs(a.y - preferredY) - Math.abs(b.y - preferredY) || a.y - b.y || a.x - b.x);
            for (const pos of candidates) {
                if (pos.x + cardWidth > width + 0.01 || pos.y + cardHeight > availableHeight + 0.01) continue;
                if (occupied.some(r => pos.x < r.x + r.width + gap - 0.01
                    && pos.x + cardWidth + gap > r.x + 0.01
                    && pos.y < r.y + r.height + gap - 0.01
                    && pos.y + cardHeight + gap > r.y + 0.01)) continue;
                const placement = {id: widget.id, side, x: pos.x, y: pos.y,
                    width: cardWidth, height: cardHeight};
                result.push(placement);
                occupied.push(placement);
                break;
            }
        }
    }
    return result;
}
