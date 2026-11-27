function normalizeLocale(tag) {
    return String(tag ?? "").trim().replace(/_/g, "-").toLowerCase();
}

export function localizedField(entry, fieldName, locale) {
    if (!entry || typeof entry !== "object") return "";
    const i18n = entry.i18n;
    const norm = normalizeLocale(locale);
    if (i18n && typeof i18n === "object" && !Array.isArray(i18n) && norm.length > 0) {
        const base = norm.split("-")[0];
        let baseMatch = null;
        for (const key of Object.keys(i18n)) {
            const normKey = normalizeLocale(key);
            const block = i18n[key];
            if (!block || typeof block !== "object" || Array.isArray(block))
                continue;
            const val = block[fieldName];
            if (typeof val !== "string" || val.length === 0)
                continue;
            if (normKey === norm)
                return val;
            if (baseMatch === null && normKey === base)
                baseMatch = val;
        }
        if (baseMatch !== null)
            return baseMatch;
    }
    const fallback = entry[fieldName];
    return typeof fallback === "string" ? fallback : "";
}
