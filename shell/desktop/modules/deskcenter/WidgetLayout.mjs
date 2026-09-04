export const sizeOrder = ["small", "medium", "large"];

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
    return sizeOrder.includes(String(size)) ? String(size) : "medium";
}

export function spanFor(widgetId, size) {
    const pair = variants[String(widgetId)]?.[normalizedSize(size)] ?? [1, 1];
    return [pair[0], pair[1]];
}

export function packWidgets(definitions, columnCount, rowCount) {
    const sorted = definitions.slice().sort((left, right) =>
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
