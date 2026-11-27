export const STANDARD_CATEGORIES = [
    { id: "clock", label: "Clock" },
    { id: "weather", label: "Weather" },
    { id: "calendar", label: "Calendar & To-Do" },
    { id: "media", label: "Media & Music" },
    { id: "system", label: "System & Monitor" },
    { id: "activity", label: "Activity & Health" },
    { id: "productivity", label: "Productivity & Notes" },
    { id: "news", label: "News & Info" },
    { id: "finance", label: "Finance" },
    { id: "photos", label: "Photos & Visual" },
    { id: "developer", label: "Developer" },
    { id: "utilities", label: "Utilities" },
    { id: "other", label: "Other" },
];

export const CATEGORY_ALIASES = {
    clock: "clock",
    time: "clock",
    timer: "clock",
    "world-clock": "clock",
    weather: "weather",
    forecast: "weather",
    environment: "weather",
    calendar: "calendar",
    todo: "calendar",
    "to-do": "calendar",
    tasks: "calendar",
    reminders: "calendar",
    pim: "calendar",
    schedule: "calendar",
    media: "media",
    music: "media",
    audio: "media",
    player: "media",
    podcast: "media",
    entertainment: "media",
    system: "system",
    monitor: "system",
    hardware: "system",
    metrics: "system",
    performance: "system",
    battery: "system",
    network: "system",
    activity: "activity",
    usage: "activity",
    screentime: "activity",
    health: "activity",
    fitness: "activity",
    productivity: "productivity",
    notes: "productivity",
    memo: "productivity",
    work: "productivity",
    office: "productivity",
    news: "news",
    rss: "news",
    reading: "news",
    info: "news",
    feed: "news",
    finance: "finance",
    stocks: "finance",
    crypto: "finance",
    currency: "finance",
    photos: "photos",
    photo: "photos",
    gallery: "photos",
    art: "photos",
    decoration: "photos",
    developer: "developer",
    dev: "developer",
    coding: "developer",
    github: "developer",
    tools: "developer",
    utilities: "utilities",
    utility: "utilities",
    tool: "utilities",
    launcher: "utilities",
    shortcuts: "utilities",
};

const LABEL_BY_ID = Object.create(null);
for (const cat of STANDARD_CATEGORIES)
    LABEL_BY_ID[cat.id] = cat.label;

export function normalizeCategory(raw) {
    const key = String(raw ?? "").trim().toLowerCase();
    if (key.length > 0 && Object.prototype.hasOwnProperty.call(CATEGORY_ALIASES, key))
        return CATEGORY_ALIASES[key];
    return "other";
}

export function categoryLabelKey(categoryId) {
    const id = String(categoryId ?? "").trim().toLowerCase();
    return Object.prototype.hasOwnProperty.call(LABEL_BY_ID, id) ? LABEL_BY_ID[id] : "Other";
}

export function buildSidebarCategories(entries, translateFn) {
    const present = Object.create(null);
    const list = entries && typeof entries !== "string" && typeof entries.length === "number" ? entries : [];
    for (let i = 0; i < list.length; i++) {
        const entry = list[i];
        if (!entry) continue;
        present[normalizeCategory(entry.category)] = true;
    }
    const tr = typeof translateFn === "function" ? translateFn : (s => s);
    const result = [];
    for (const cat of STANDARD_CATEGORIES) {
        if (present[cat.id])
            result.push({ id: cat.id, name: tr(cat.label), icon: "" });
    }
    return result;
}

export function groupEntriesByPackage(entries, choicesById, localizedFn, translateFn) {
    const list = entries && typeof entries !== "string" && typeof entries.length === "number" ? entries : [];
    const loc = typeof localizedFn === "function" ? localizedFn : ((e, f) => String(e?.[f] ?? ""));
    const tr = typeof translateFn === "function" ? translateFn : (s => s);
    const groups = [];
    const byPkg = Object.create(null);

    for (let i = 0; i < list.length; i++) {
        const entry = list[i];
        if (!entry) continue;
        const pkgId = String(entry.packageId || entry.id || "");
        if (!byPkg[pkgId]) {
            byPkg[pkgId] = [];
            groups.push({ packageId: pkgId, entries: byPkg[pkgId] });
        }
        byPkg[pkgId].push(entry);
    }

    const out = [];
    for (const group of groups) {
        const groupEntries = group.entries;
        const first = groupEntries[0];
        const multi = groupEntries.length > 1;
        let title;
        if (!multi) {
            title = loc(first, "name") || String(first.name || first.id || "");
        } else {
            title = loc(first, "packageName")
                || String(first.packageName || "")
                || tr(categoryLabelKey(normalizeCategory(first.category)));
        }

        const items = [];
        for (const entry of groupEntries) {
            const choices = choicesById ? (choicesById[entry.id] ?? []) : [];
            const subName = loc(entry, "name") || String(entry.name || entry.id || "");
            for (let j = 0; j < choices.length; j++) {
                const choice = choices[j];
                if (!choice) continue;
                items.push({
                    entry,
                    value: String(choice.value ?? ""),
                    span: choice.span,
                    showSubName: multi,
                    label: multi ? (subName + " · " + String(choice.label ?? "")) : String(choice.label ?? ""),
                });
            }
        }
        items.sort((a, b) => {
            const aCols = Number(a.span?.[0] ?? 0);
            const aRows = Number(a.span?.[1] ?? 0);
            const bCols = Number(b.span?.[0] ?? 0);
            const bRows = Number(b.span?.[1] ?? 0);
            const aArea = aCols * aRows;
            const bArea = bCols * bRows;
            if (aArea !== bArea) return aArea - bArea;
            if (aRows !== bRows) return aRows - bRows;
            if (aCols !== bCols) return aCols - bCols;
            return 0;
        });
        if (items.length > 0)
            out.push({ packageId: group.packageId, title, items });
    }
    return out;
}
