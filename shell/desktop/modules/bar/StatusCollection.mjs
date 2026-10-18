// Shared by the live strip and its state service. Keep absent applications in
// the saved order: temporarily folding an icon is not deleting its preference.
export const toggleKey = "collection:toggle";

export function visibleKeys(ordered, collected, expanded, enabled = true) {
    if (!enabled) return ordered.slice();
    const hidden = new Set(collected.filter(key => key !== "cell:controlcenter"));
    return (expanded ? ordered.filter(key => hidden.has(key)) : [])
        .concat([toggleKey], ordered.filter(key => !hidden.has(key)));
}

function groupOrder(keys) {
    return keys.filter(k => k.startsWith("tray:"))
        .concat(keys.filter(k => !k.startsWith("tray:") && k !== "cell:controlcenter"),
            keys.filter(k => k === "cell:controlcenter"));
}

export function previewOrder(keys, key, destination) {
    const result = keys.slice();
    const source = result.indexOf(key);
    if (source < 0 || destination < 0 || key === "cell:controlcenter") return result;
    result.splice(source, 1);
    result.splice(Math.min(destination, result.length), 0, key);
    const boundary = result.indexOf(toggleKey);
    if (boundary < 0) return groupOrder(result);
    return groupOrder(result.slice(0, boundary)).concat([toggleKey], groupOrder(result.slice(boundary + 1)));
}

export function destinationSection(preview, key) {
    const boundary = preview.indexOf(toggleKey);
    if (boundary < 0) return { collected: false, keys: preview.slice() };
    const collected = preview.indexOf(key) < boundary;
    return { collected, keys: collected ? preview.slice(0, boundary) : preview.slice(boundary + 1) };
}

export function mergeOrder(saved, arranged) {
    const live = new Set(arranged);
    let next = 0;
    const merged = saved.map(key => live.has(key) ? arranged[next++] : key);
    return merged.concat(arranged.slice(next));
}
