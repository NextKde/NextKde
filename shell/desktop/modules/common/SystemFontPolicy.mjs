// Parsing rules for the desktop's own interface font.
//
// 使用系统字体 (AppearanceConfigService.useSystemFont) makes every shell surface
// render with the font KDE is configured with instead of the families the shell
// was designed around. The value lives in kdeglobals:
//
//     [General]
//     font=Maple Mono NF CN,10
//
// Two shapes have to be accepted. KDE 6 writes `family,pointSize`; older
// configurations and hand-edited files also carry Qt's full QFont serialisation
// (`family,10,-1,5,50,0,0,0,0,0`), whose trailing fields are weight and style
// hints that this feature deliberately ignores -- family is the whole request.
//
// Kept out of the QML service so the rules can be unit-tested without Qt, the
// same split VisibilityPolicy.mjs and DesktopGridMetrics.mjs use.

const GENERAL_GROUP = "[General]";

// Returns the raw `font=` value of kdeglobals' General group, or "" when the
// group or the key is absent. Group names are matched case-insensitively
// because KConfig preserves whatever spelling the writer used, and the key is
// split at the first separator rather than matched as a prefix: `fontSize=`,
// `menuFont=` and `fixed=` are different settings that a prefix match would
// happily return.
export function fontSpecFromConfig(text) {
    const lines = String(text ?? "").split("\n");
    let inGeneral = false;
    for (const rawLine of lines) {
        const line = rawLine.trim();
        if (line.startsWith("[") && line.endsWith("]")) {
            inGeneral = line.toLowerCase() === GENERAL_GROUP.toLowerCase();
            continue;
        }
        if (!inGeneral)
            continue;
        const separator = line.indexOf("=");
        if (separator < 0)
            continue;
        if (line.slice(0, separator).trim().toLowerCase() !== "font")
            continue;
        return line.slice(separator + 1).trim();
    }
    return "";
}

// Splits a KDE/QFont specification into the family it names and the point size
// it carries (0 when the file names a family only).
export function parseFontSpec(spec) {
    const value = String(spec ?? "").trim();
    if (value.length === 0)
        return { family: "", pointSize: 0 };
    const fields = value.split(",");
    // A specification that starts with a digit is Qt's own serialisation
    // without a family, which carries no usable name.
    const family = fields.length > 0 ? fields[0].trim() : "";
    const pointSize = fields.length > 1 ? Number(fields[1].trim()) : NaN;
    return {
        family: family,
        pointSize: Number.isFinite(pointSize) && pointSize > 0 ? pointSize : 0,
    };
}

// The family the shell should draw with. An unreadable or missing
// configuration falls back to the font Qt already applied through the platform
// theme, which is what every application on the desktop is using anyway.
export function resolveFamily(spec, applicationFamily) {
    const { family } = parseFontSpec(spec);
    if (family !== "")
        return family;
    return String(applicationFamily ?? "").trim();
}
