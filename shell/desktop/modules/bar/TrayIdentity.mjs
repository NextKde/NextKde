// Explicit application labels are not random IDs: WorkBuddy, OneDrive and
// other mixed-case names must win over a shared Electron ID fallback.
export function isGeneratedLabel(value) {
    const text = String(value || "").trim();
    return !text || /^chrome[_-]status[_-]icon(?:[_-]\d+)?$/i.test(text)
        || /[_-]status[_-]icon[_-]?\d*$/i.test(text)
        || /^tray[-\s]?icon(?:\s+tray\s+app)?\s+/i.test(text);
}

export function isInternalId(value) {
    const text = String(value || "").trim();
    return isGeneratedLabel(text)
        || /^[a-f0-9]{8,}$/i.test(text)
        || (/^[a-z0-9]{8,16}$/i.test(text) && /[a-z]/i.test(text) && /\d/.test(text));
}

const genericNames = new Set([
    "app", "apprun", "resources", "electron", "node", "chrome", "chromium",
    "python", "python3", "java", "sh", "bash", "env", "flatpak", "snap", "tray", "icon"
]);

export function nameFromId(value) {
    const id = String(value || "").trim();
    if (!id || /^chrome[_-]status[_-]icon/i.test(id)) return "";
    let name = id.replace(/^tray[-\s]?icon(\s+tray\s+app)?\s+/i, "");
    name = name.replace(/[_-]status[_-]icon[_-]?\d*$/i, "").replace(/[_-]+$/, "").trim();
    if (name === id || name.length < 2 || !/^[a-z0-9._-]+$/i.test(name)
        || genericNames.has(name.toLowerCase())) return "";
    if (!/[-_]/.test(name) && name === name.toLowerCase())
        name = name.charAt(0).toUpperCase() + name.slice(1);
    return name;
}

export function friendlyName(item, resolvedNames = {}, aliases = {}, siblings = []) {
    if (!item) return "";
    for (const value of [item.tooltipTitle, item.title]) {
        const label = String(value || "").trim();
        if (!isGeneratedLabel(label)) return label;
    }
    const id = String(item.id || "").trim();
    // An app-specific ID is stronger evidence than a daemon fallback keyed by
    // an ID that Electron can reuse for several simultaneously running apps.
    const fromId = nameFromId(id);
    if (fromId) return aliases[fromId.toLowerCase()] || fromId;
    if (id && !isInternalId(id)) return aliases[id.toLowerCase()] || id;
    const anonymous = Array.from(siblings || []).filter(other => String(other?.id || "").trim() === id
        && isGeneratedLabel(other?.tooltipTitle) && isGeneratedLabel(other?.title)
        && !nameFromId(other?.id));
    // A shared-ID result cannot distinguish two currently anonymous items.
    // Keep the original artwork until a title or an unambiguous refresh arrives.
    const resolved = anonymous.length > 1 ? "" : resolvedNames[id];
    return resolved || item.tooltipTitle || item.title || id;
}
