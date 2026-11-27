export const sizeOrder = ["1x1", "1x2", "2x2", "2x1"];

// Legacy gallery size names shared by the gallery and its desktop host.
export function namedGallerySpan(size) {
    const pair = toArray(size);
    if (pair && pair.length === 2
        && Number.isInteger(Number(pair[0])) && Number.isInteger(Number(pair[1])))
        return [Number(pair[0]), Number(pair[1])];
    const match = /^(\d+)x(\d+)$/.exec(String(size));
    if (match) return [Number(match[1]), Number(match[2])];
    return size === "large" ? [2, 2] : size === "medium" ? [2, 1] : [1, 1];
}

const variants = {
    clock: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    weather: { small: [2, 1], medium: [3, 1], large: [3, 2] },
    calendar: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    todo: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    system: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    activity: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    music: { small: [1, 1], medium: [2, 1], large: [2, 2] },
    // The grouped view is a tall two-column card anchored at the top-right.
    groups: { small: [2, 2], medium: [2, 3], large: [3, 3] }
};

// The grouped view is the one widget whose default placement is the top-right
// of the desktop grid instead of the left flow. It may grow one row/column
// beyond the ordinary widget ceiling, but it cannot shrink below two cells on
// either axis: its header plus the four type tabs need about 222 px, and a
// one-column content area cannot fit a member cell. The stored sizes are the
// four layouts that remain readable.
export function allowedSizeOrder(widgetId) {
    switch (String(widgetId)) {
    case "groups":
        return ["2x2", "2x3", "3x2", "3x3"];
    case "weather":
        // Weather's declared medium/large spans are three columns wide, so
        // every span the resize handle can reach must also be storable.
        return ["1x1", "1x2", "2x1", "2x2", "3x1", "3x2"];
    default:
        return sizeOrder;
    }
}

// Minimum span per axis. Ordinary widgets may shrink to a single cell; the
// grouped view keeps the two-row/two-column floor that its tabs and member
// grid need.
export function minSpanFor(widgetId) {
    return String(widgetId) === "groups" ? [2, 2] : [1, 1];
}

export function isValidSize(widgetId, size) {
    const value = String(size);
    if (["small", "medium", "large"].includes(value)) return true;
    if (allowedSizeOrder(widgetId).includes(value)) return true;
    if (Object.prototype.hasOwnProperty.call(variants, String(widgetId))) return false;
    // Package-backed widget instances are not one of the eight legacy named
    // ids above (see DeskCenterWindow.qml's addGalleryWidget/resizeWidget),
    // so they never appear in allowedSizeOrder/variants and would otherwise
    // be rejected outright -- silently dropping any span a package declares
    // beyond the legacy 2x2 ceiling, such as the example clock's 3x2. Accept
    // any syntactically valid NxM span within metadata.json's own 1-4 bound
    // (see WidgetPackageIndex.cpp's validSize) instead.
    const match = /^(\d+)x(\d+)$/.exec(value);
    return !!match && Number(match[1]) >= 1 && Number(match[1]) <= 4
        && Number(match[2]) >= 1 && Number(match[2]) <= 4;
}

// A JS array that has passed through a Repeater/ListView `model:` binding
// comes back out as a Qt sequence wrapper on its nested array fields --
// indexable and JSON.stringify-able, but Array.isArray() on it is false (it
// is not the same realm's Array). Array.prototype.slice.call duck-types on
// `.length` instead, so it accepts that wrapper as well as a plain array.
function toArray(value) {
    return (value != null && typeof value !== "string" && typeof value.length === "number")
        ? Array.prototype.slice.call(value) : null;
}

// A package's own declared sizes (metadata.json's `sizes`, e.g. [[2,2],[3,2]])
// define its real resize ceiling/floor, which can exceed the legacy 2x2 cap
// baked into maxSpanFor's default. Returns null when there is nothing
// declared, so the caller can fall back to the legacy named-widget bounds.
export function declaredSizeCeiling(sizes) {
    const list = toArray(sizes);
    if (!list || list.length === 0) return null;
    return list.reduce((acc, span) => [Math.max(acc[0], span[0]), Math.max(acc[1], span[1])], [1, 1]);
}

export function declaredSizeFloor(sizes) {
    const list = toArray(sizes);
    if (!list || list.length === 0) return null;
    return list.reduce((acc, span) => [Math.min(acc[0], span[0]), Math.min(acc[1], span[1])], list[0]);
}

// A package declares a *discrete* set of sizes (metadata.json's `sizes`),
// not a continuous [floor, ceiling] rectangle -- a package declaring
// [[1,1],[3,3]] (skipping [2,2]) must still snap only to those two, not to
// every combination the per-axis min/max happens to allow. Picks whichever
// declared pair is closest (straight-line distance in cell units) to the
// column/row guess the drag/magnet math produced.
export function nearestDeclaredSize(columns, rows, sizes) {
    const list = toArray(sizes);
    if (!list || list.length === 0) return [columns, rows];
    let best = list[0];
    let bestDistance = Infinity;
    for (const span of list) {
        const dc = span[0] - columns;
        const dr = span[1] - rows;
        const distance = dc * dc + dr * dr;
        if (distance < bestDistance) { bestDistance = distance; best = span; }
    }
    return [best[0], best[1]];
}

// Reconcile a persisted instance span against the package's current `sizes`
// list (e.g. after a package update removed a previously used size). Returns
// `{ span: [cols, rows], changed: bool }`.
export function resolveDeclaredSpan(columns, rows, sizes, defaultSize) {
    const rawList = toArray(sizes);
    if (!rawList || rawList.length === 0)
        return { span: [columns, rows], changed: false };
    const validList = [];
    for (const item of rawList) {
        const pair = toArray(item);
        if (!pair || pair.length !== 2) continue;
        const c = Number(pair[0]);
        const r = Number(pair[1]);
        if (Number.isInteger(c) && Number.isInteger(r) && c >= 1 && c <= 4 && r >= 1 && r <= 4)
            validList.push([c, r]);
    }
    if (validList.length === 0)
        return { span: [columns, rows], changed: false };
    if (Number.isInteger(columns) && Number.isInteger(rows)
            && validList.some(pair => pair[0] === columns && pair[1] === rows)) {
        return { span: [columns, rows], changed: false };
    }
    if (Number.isInteger(columns) && Number.isInteger(rows) && columns >= 1 && rows >= 1) {
        return { span: nearestDeclaredSize(columns, rows, validList), changed: true };
    }
    const defPair = toArray(defaultSize);
    if (defPair && defPair.length === 2) {
        const dc = Number(defPair[0]);
        const dr = Number(defPair[1]);
        if (validList.some(pair => pair[0] === dc && pair[1] === dr))
            return { span: [dc, dr], changed: true };
    }
    return { span: [validList[0][0], validList[0][1]], changed: true };
}

export function maxSpanFor(widgetId) {
    switch (String(widgetId)) {
    case "groups":
        return [3, 3];
    // Weather's medium and large layouts are three columns wide. The resize
    // handle must use the same ceiling, otherwise merely grabbing a 3-column
    // card snaps it down to two and the user cannot drag it back.
    case "weather":
        return [3, 2];
    default:
        return [2, 2];
    }
}

export function normalizedSize(size) {
    const value = String(size);
    // Keep old weather spans (including its three-column forecast) until the
    // user explicitly resizes it. Existing desktops must not change size.
    return /^\d+x\d+$/.test(value) || ["small", "medium", "large"].includes(value)
        ? value : "medium";
}

export function spanFor(widgetId, size) {
    const value = normalizedSize(size);
    const explicit = /^(\d+)x(\d+)$/.exec(value);
    if (explicit)
        return [Number(explicit[1]), Number(explicit[2])];
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

// Place a widget that is not part of the left flow. The grouped view keeps its
// saved position when it is still valid; otherwise it lands at the first free
// top-right rectangle (row 0, rightmost columns first). Left-flow widgets are
// obstacles, so an anchored card can never overlap them.
export function placeAnchoredWidget(widget, placements, columnCount, rowCount) {
    if (!widget)
        return null;
    const columns = Math.max(1, Number(widget.columns) || 1);
    const rows = Math.max(1, Number(widget.rows) || 1);
    const obstacles = toArray(placements) ?? [];
    const fits = (column, row) => Number.isInteger(column) && Number.isInteger(row)
        && column >= 0 && row >= 0
        && column + columns <= columnCount && row + rows <= rowCount
        && !obstacles.some(other =>
            column < other.column + other.columns
            && column + columns > other.column
            && row < other.row + other.rows
            && row + rows > other.row);
    if (fits(widget.column, widget.row))
        return { id: widget.id, column: widget.column, row: widget.row,
            columns: columns, rows: rows };
    for (let row = 0; row <= rowCount - rows; ++row) {
        for (let column = columnCount - columns; column >= 0; --column) {
            if (fits(column, row))
                return { id: widget.id, column: column, row: row,
                    columns: columns, rows: rows };
        }
    }
    return null;
}

// Cards are placed from the left visual inset, but the 10-column grid itself
// is still sized with the original 8 px layout margins (see
// layoutBaseSideMargin in DeskCenterWindow.qml). Shifting that grid inward
// therefore pushes its rightmost column past `width - rightInset`; the top-
// right anchored grouped view would sit flush under the screen edge instead of
// keeping the same margin as every other card. Cap a card's left edge so its
// right edge never crosses the visible margin; every other card is already
// inside it, so this only moves the anchored one.
export function insetRightEdge(x, width, screenWidth, rightInset) {
    return Math.min(x, Math.max(0, screenWidth - rightInset - width));
}

export function snappedSpan(width, height, cellSize, gap,
        maximumColumns = 2, maximumRows = 2,
        minimumColumns = 1, minimumRows = 1) {
    const step = Math.max(1, cellSize + gap);
    // A caller may pass a minimum above the maximum on a screen that cannot
    // fit it; the maximum wins so the card never claims an impossible span.
    const snap = (length, maximum, minimum) => Math.max(minimum,
        Math.min(Math.max(minimum, maximum), Math.round((length + gap) / step)));
    return [snap(width, maximumColumns, minimumColumns),
        snap(height, maximumRows, minimumRows)];
}

// A resize drag moves continuously, but a widget only lands on whole cells.
// Snapping the card at the halfway point would jump under the pointer, so bend
// the drag instead: near a cell size the magnet holds the corner back, and the
// further the pointer pulls away the more freely it follows (exactly on the
// halfway line it is free). The mapping is continuous, so the corner tracks a
// steady hand while the magnet does the resisting, and the release spring does
// the snapping to the cell the corner is closest to.
export function magnetizedSize(size, cellSize, gap, maximumSpan = 2, minimumSpan = 1) {
    const step = Math.max(1, cellSize + gap);
    const lowerSpan = Math.min(minimumSpan, maximumSpan);
    const minimum = lowerSpan * cellSize + (lowerSpan - 1) * gap;
    const maximum = maximumSpan * cellSize + (maximumSpan - 1) * gap;
    const clamped = Math.max(minimum, Math.min(maximum, size));
    const span = Math.max(lowerSpan,
        Math.min(maximumSpan, Math.round((clamped + gap) / step)));
    const snapped = span * cellSize + (span - 1) * gap;
    // 0 at the cell size (fully held), 1 on the halfway line (fully free).
    const free = Math.min(1, Math.abs(clamped - snapped) / (step / 2));
    return snapped + (clamped - snapped) * free;
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
