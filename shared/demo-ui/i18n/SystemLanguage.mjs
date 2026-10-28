// Match shared/i18n/SystemLanguage.h: only the primary UI language decides.
// A secondary Chinese fallback must not override an English primary language.
export function isChinese(languages) {
    const primary = String((languages || [])[0] || "").toLowerCase().replace(/_/g, "-");
    return primary === "zh" || primary.startsWith("zh-");
}

export function systemLanguage(languages) {
    return isChinese(languages) ? "zh-CN" : "en";
}
