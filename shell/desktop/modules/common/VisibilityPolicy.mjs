// Pure visibility policy for the shell's individually toggleable surfaces.
//
// The QML side owns persistence and rendering; everything that decides *which*
// ids are valid and how a wanted value maps to the stored set lives here, so
// the rules can be unit-tested without a compositor. Both the Shell's
// AppearanceConfigService and the Settings page's row builder consume this,
// which is what keeps the two from disagreeing about what "hidden" means.

// The DeskCenter cards, in their authoring order. The layout pass and the
// settings page both read this list, so neither can drift from the surfaces
// the shell actually builds.
export const deskCenterWidgetIds = [
    "clock", "weather", "calendar", "todo", "system", "activity", "music",
];

// The shell-owned StatusArea cells, in their declared trailing order.
export const statusCellIds = [
    "network", "battery", "settings", "controlcenter",
];

// The cells the shell always renders, whatever the hidden set says. The
// Control Center is the anchor every other panel positions against, so hiding
// it would leave those panels with nothing to hang from.
export const requiredStatusCellIds = ["controlcenter"];

function isKnown(id, known) {
    return known.indexOf(String(id)) >= 0;
}

export function isKnownDeskCenterWidget(id) {
    return isKnown(id, deskCenterWidgetIds);
}

export function isKnownStatusCell(id) {
    return isKnown(id, statusCellIds);
}

// Drops unknown ids and duplicates, so a stale or hand-edited config cannot
// hide a surface that no longer exists nor grow the list without bound. A
// required id is dropped too: an unreadable config must never be able to
// remove the anchor the other panels depend on.
export function normalizeHiddenIds(value, known) {
    if (!Array.isArray(value))
        return [];
    const seen = {};
    const result = [];
    for (const candidate of value) {
        const id = String(candidate);
        if (seen[id] || !isKnown(id, known) || requiredStatusCellIds.indexOf(id) >= 0)
            continue;
        seen[id] = true;
        result.push(id);
    }
    return result;
}

export function isHidden(hiddenIds, id) {
    return (hiddenIds ?? []).indexOf(String(id)) >= 0;
}

// `visible` is the wanted state, so a caller can hand over the value its
// switch displays with no negation to keep in sync. Returns the next list, or
// `null` when nothing changes or the id is refused, which lets the caller skip
// a redundant write and its file sync.
export function withVisibility(hiddenIds, id, visible, known) {
    if (!isKnown(id, known))
        return null;
    const key = String(id);
    if (requiredStatusCellIds.indexOf(key) >= 0)
        return null;
    const current = Array.isArray(hiddenIds) ? hiddenIds : [];
    const hidden = current.indexOf(key) >= 0;
    if (hidden === !visible)
        return null;
    const next = current.filter(candidate => candidate !== key);
    if (!visible)
        next.push(key);
    return next;
}

// Builds one row per known surface for the settings page: the id the Shell
// validates against, a display label, and the wanted visibility. The label
// table is passed in so this module stays free of UI copy.
export function buildRows(known, hiddenIds, labels) {
    const hidden = hiddenIds ?? [];
    return known.map(id => ({
        id,
        label: labels?.[id] ?? id,
        visible: hidden.indexOf(id) < 0,
    }));
}
