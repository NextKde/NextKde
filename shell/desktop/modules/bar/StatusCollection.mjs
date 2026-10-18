// Keep the disclosure outside the reorderable sections. Opening its popup
// never adds collected icons to the Bar/Dock's width or changes its row count.
export const toggleKey = "collection:toggle";
export const dragMimeType = "application/x-nextkde-status-icon";

export function sections(ordered, collected) {
    const hidden = new Set(collected.filter(key => key !== "cell:controlcenter"));
    return {
        strip: ordered.filter(key => !hidden.has(key)),
        collection: ordered.filter(key => hidden.has(key))
    };
}

export function visibleKeys(ordered, collected) {
    return [toggleKey].concat(sections(ordered, collected).strip);
}

function groupOrder(keys) {
    return keys.filter(k => k.startsWith("tray:"))
        .concat(keys.filter(k => !k.startsWith("tray:") && k !== "cell:controlcenter"),
            keys.filter(k => k === "cell:controlcenter"));
}

export function previewOrder(keys, key, destination) {
    if (!key || key === toggleKey || key === "cell:controlcenter" || destination < 0)
        return keys.slice();
    const result = keys.filter(candidate => candidate !== key && candidate !== toggleKey);
    result.splice(Math.min(destination, result.length), 0, key);
    const ordered = groupOrder(result);
    return keys.includes(toggleKey) ? [toggleKey].concat(ordered) : ordered;
}

export function dropPlan(ordered, collected, key, section, destination) {
    if (!ordered.includes(key) || key === "cell:controlcenter"
        || !["strip", "collection"].includes(section) || destination < 0)
        return null;
    const keys = sections(ordered, collected)[section];
    return { collected: section === "collection", keys: previewOrder(keys, key, destination) };
}

export function mergeOrder(saved, arranged) {
    const live = new Set(arranged);
    let next = 0;
    const merged = saved.map(key => live.has(key) ? arranged[next++] : key);
    return merged.concat(arranged.slice(next));
}

export function gridOrigin(index, columns, size, spacing) {
    return { x: (index % columns) * (size + spacing),
        y: Math.floor(index / columns) * (size + spacing) };
}

export function popupGeometry(count, availableHeight) {
    const width = 300, padding = 12, cellSize = 40, spacing = 6;
    const columns = Math.floor((width - padding * 2 + spacing) / (cellSize + spacing));
    const rows = Math.max(1, Math.ceil(count / columns));
    const contentHeight = rows * cellSize + (rows - 1) * spacing;
    const footerHeight = 32;
    const height = Math.min(contentHeight + padding * 2 + footerHeight,
        Math.max(96, availableHeight));
    return { width, padding, cellSize, spacing, columns, contentHeight, height,
        viewportHeight: height - padding * 2 - footerHeight };
}
