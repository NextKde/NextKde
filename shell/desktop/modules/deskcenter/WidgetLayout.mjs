export const sizeOrder = ["1x1", "1x2", "2x2", "2x1"];

const variants = {
    clock: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    weather: { small: [2, 1], medium: [3, 1], large: [3, 2] },
    calendar: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    todo: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    system: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    activity: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    music: { small: [1, 1], medium: [2, 1], large: [2, 2] }
};

export function normalizedSize(size) {
    const value = String(size);
    // Keep old weather spans (including its three-column forecast) until the
    // user explicitly resizes it. Existing desktops must not change size.
    return sizeOrder.includes(value) || ["small", "medium", "large"].includes(value)
        ? value : "medium";
}

export function spanFor(widgetId, size) {
    const value = normalizedSize(size);
    if (sizeOrder.includes(value))
        return value.split("x").map(Number);
    const pair = variants[String(widgetId)]?.[value] ?? [1, 1];
    return [pair[0], pair[1]];
}

export function packWidgets(definitions, columnCount, rowCount) {
    const occupied = [];
    const result = [];
    for (let row = 0; row < rowCount; row++)
        occupied[row] = Array(columnCount).fill(false);

    function place(widget, column, row) {
        if (column < 0 || row < 0 || column + widget.columns > columnCount
                || row + widget.rows > rowCount) return false;
        for (let y = row; y < row + widget.rows; y++)
            for (let x = column; x < column + widget.columns; x++)
                if (occupied[y][x]) return false;
        for (let y = row; y < row + widget.rows; y++)
            for (let x = column; x < column + widget.columns; x++)
                occupied[y][x] = true;
        result.push({ id: widget.id, column, row, columns: widget.columns, rows: widget.rows });
        return true;
    }
    // Reserve saved positions before filling gaps with unpositioned widgets.
    // Out-of-bounds/conflicting positions fall back to packing on this screen,
    // without rewriting the preference saved for the original screen geometry.
    for (const widget of definitions) {
        if (Number.isInteger(widget.column) && Number.isInteger(widget.row))
            place(widget, widget.column, widget.row);
    }
    for (const widget of definitions) {
        if (result.some(placement => placement.id === widget.id)) continue;
        let placed = false;
        for (let row = 0; row <= rowCount - widget.rows && !placed; row++)
            for (let column = 0; column <= columnCount - widget.columns && !placed; column++)
                placed = place(widget, column, row);
    }
    return definitions.map(widget => result.find(placement => placement.id === widget.id))
        .filter(placement => placement !== undefined);
}

export function fitWidgets(definitions, preferredColumns, maxColumns, rowCount) {
    if (rowCount <= 0 || maxColumns <= 0) return { columns: 0, placements: [] };
    const rows = rowCount;
    const maximum = maxColumns;
    const extent = definitions.reduce((right, widget) =>
        Number.isInteger(widget.column) ? Math.max(right, widget.column + widget.columns) : right, 0);
    const first = Math.min(maximum, Math.max(1, preferredColumns, extent));
    // Grow into free desktop space before changing any requested card sizes.
    for (let columns = first; columns <= maximum; columns++) {
        const placements = packWidgets(definitions, columns, rows);
        if (placements.length === definitions.length)
            return { columns, placements };
    }
    // Very short/small outputs can have fewer rows than a saved card's height.
    // Compact only this screen's projection, never the persisted preferences.
    let compact = definitions.map(widget => Object.assign({}, widget, {
        columns: Math.min(widget.columns, maximum), rows: Math.min(widget.rows, rows) }));
    let placements = packWidgets(compact, maximum, rows);
    if (placements.length < definitions.length) {
        compact = definitions.map(widget => Object.assign({}, widget, { columns: 1, rows: 1 }));
        placements = packWidgets(compact, maximum, rows);
    }
    return { columns: maximum, placements };
}

export function snappedSpan(width, height, cellSize, gap) {
    const step = Math.max(1, cellSize + gap);
    const snap = length => Math.max(1, Math.min(2, Math.round((length + gap) / step)));
    return [snap(width), snap(height)];
}

export function snappedPosition(x, y, columns, rows, cellSize, gap, maxColumns, maxRows) {
    const step = Math.max(1, cellSize + gap);
    return {
        column: Math.max(0, Math.min(Math.max(0, maxColumns - columns), Math.round(x / step))),
        row: Math.max(0, Math.min(Math.max(0, maxRows - rows), Math.round(y / step)))
    };
}

export function canPlace(placements, widgetId, column, row, columns, rows, maxColumns, maxRows) {
    if (!Number.isInteger(column) || !Number.isInteger(row) || column < 0 || row < 0
            || column + columns > maxColumns || row + rows > maxRows) return false;
    return !placements.some(other => other.id !== widgetId
        && column < other.column + other.columns && column + columns > other.column
        && row < other.row + other.rows && row + rows > other.row);
}

// Keep enough file columns for the current desktop, up to the capacity of the
// original four-column widget layout. Even an empty desktop keeps a drop lane.
export function widgetColumnLimit(width, cellSize, gap, fileColumnWidth, fileCount, fileRows) {
    const step = Math.max(1, cellSize + gap);
    const fileStep = Math.max(1, fileColumnWidth);
    const baselineFiles = Math.max(1, Math.floor((width - 4 * step) / fileStep));
    const needed = Math.max(1, Math.ceil(fileCount / Math.max(1, fileRows)));
    const reserved = Math.min(baselineFiles, needed) * fileStep;
    return Math.max(0, Math.floor((width - reserved) / step));
}

export function savedPositionsAfterMove(saved, placements, widgetId, column, row) {
    const next = Object.assign({}, saved);
    for (const placement of placements) {
        // Preserve the original location of projected/out-of-bounds cards.
        if (!Object.prototype.hasOwnProperty.call(next, placement.id))
            next[placement.id] = { column: placement.column, row: placement.row };
    }
    next[widgetId] = { column, row };
    return next;
}
