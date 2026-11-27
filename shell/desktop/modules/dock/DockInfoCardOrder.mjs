// Dock information cards are installed widget packages (containers: ["dock"]).
// A card is identified by its `dockCardId` (falling back to the entry `id`), so
// one card can ship a macOS and a Material entry and keep its place in the
// ordered list when the shell style changes.

// Cards that used to be hard-coded in the Dock. Saved orders written by older
// versions keep working: the legacy names are migrated to the official packages.
export const LEGACY_INFO_CARD_IDS = {
    music: "org.nextkde.dock.music",
    weather: "org.nextkde.dock.weather",
    clock: "org.nextkde.dock.clock",
    metrics: "org.nextkde.dock.system",
    temperature: "org.nextkde.dock.system",
};

export const DEFAULT_INFO_CARD_ORDER = [
    "org.nextkde.dock.music",
    "org.nextkde.dock.weather",
    "org.nextkde.dock.clock",
    "org.nextkde.dock.system",
];

export function isValidPackageId(id) {
    const s = String(id ?? "");
    if (s.length === 0 || s.length > 192 || s.startsWith(".") || s.endsWith("."))
        return false;
    const labels = s.split(".");
    if (labels.length < 3)
        return false;
    for (const label of labels) {
        if (label.length === 0 || label.length > 63)
            return false;
        if (!/^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label))
            return false;
    }
    return true;
}

export function migrateInfoCardId(rawId) {
    const s = String(rawId ?? "");
    return Object.prototype.hasOwnProperty.call(LEGACY_INFO_CARD_IDS, s)
        ? LEGACY_INFO_CARD_IDS[s] : s;
}

export function isValidInfoCardId(id) {
    return isValidPackageId(migrateInfoCardId(id));
}

export function cardIdOf(entry) {
    if (!entry || typeof entry !== "object") return "";
    const explicit = String(entry.dockCardId ?? "");
    return explicit.length > 0 ? explicit : String(entry.id ?? "");
}

export function normalizeInfoCardOrder(rawOrder) {
    const input = (rawOrder != null && typeof rawOrder !== "string" && typeof rawOrder.length === "number")
        ? Array.prototype.slice.call(rawOrder) : [];
    const result = [];
    for (const rawId of input) {
        const id = migrateInfoCardId(rawId);
        if (!isValidPackageId(id) || result.indexOf(id) >= 0)
            continue;
        result.push(id);
    }
    return result;
}

export function supportsContainer(entry, containerName) {
    if (!entry || typeof entry !== "object") return false;
    const raw = entry.containers;
    if (raw == null || typeof raw === "string" || typeof raw.length !== "number" || raw.length === 0)
        return containerName === "desktop";
    for (let i = 0; i < raw.length; i++) {
        if (String(raw[i]) === containerName)
            return true;
    }
    return false;
}
