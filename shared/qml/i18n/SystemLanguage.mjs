// Match shared/i18n/SystemLanguage.h: only the primary UI language decides.
// A secondary Chinese fallback must not override an English primary language.
function primaryLanguage(languages) {
    return String((languages || [])[0] || "").toLowerCase().replace(/_/g, "-");
}

export function isChinese(languages) {
    const primary = primaryLanguage(languages);
    return primary === "zh" || primary.startsWith("zh-");
}

// Every Portuguese variant uses the Brazilian catalog, the only one shipped.
export function isPortuguese(languages) {
    const primary = primaryLanguage(languages);
    return primary === "pt" || primary.startsWith("pt-");
}

export function systemLanguage(languages) {
    if (isChinese(languages)) return "zh-CN";
    if (isPortuguese(languages)) return "pt-BR";
    return "en";
}
