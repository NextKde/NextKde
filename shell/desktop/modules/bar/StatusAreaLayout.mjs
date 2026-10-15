// Card geometry shared by the editor and its display-independent tests.
export const cardWidth = 90;
export const cardHeight = 66;
export const spacing = 8;
export const margin = 14;

export function columnsForWidth(width, count) {
    return Math.max(1, Math.min(count,
        Math.floor((width - 2 * margin + spacing) / (cardWidth + spacing))));
}

export function dragDestination(index, dx, dy, columns, count) {
    const columnDelta = Math.round(dx / (cardWidth + spacing));
    const rowDelta = Math.round(dy / (cardHeight + spacing));
    return Math.max(0, Math.min(count - 2, index + columnDelta + rowDelta * columns));
}
