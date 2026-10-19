import assert from "node:assert/strict";
import { fontSpecFromConfig, parseFontSpec, resolveFamily } from
    "../../shell/desktop/modules/common/SystemFontPolicy.mjs";

// kdeglobals' [General] font= is the only thing 使用系统字体 borrows from KDE, and
// it is written by KDE, by hand, and by older Qt versions. These are the shapes
// that appear in the wild; the shell's chain reads them all through these three
// functions, so a parser change here is a change to what the desktop draws with.

const kde6 = `[General]
BrowserApplication=google-chrome.desktop
font=Maple Mono NF CN,10
fixed=Maple Mono NF CN,10
menuFont=Maple Mono NF CN,10
smallestReadableFont=Maple Mono NF CN,9

[Icons]
Theme=breeze-dark
`;

// KDE/Qt serialise a full QFont when the setting was written by a tool that
// keeps weight and style; only the family is meaningful to this feature.
const serialised = `[General]
font=Noto Sans,10,-1,5,50,0,0,0,0,0
`;

// A family with commas in its own name is not representable in this format and
// does not occur in kdeglobals; the first field is the family by definition.
const onlyFamily = `[General]
font=Inter
`;

assert.equal(parseFontSpec("Maple Mono NF CN,10").family, "Maple Mono NF CN");
assert.equal(parseFontSpec("Maple Mono NF CN,10").pointSize, 10);
assert.equal(parseFontSpec("  Noto Sans  ,9 ").family, "Noto Sans");
assert.equal(parseFontSpec("Noto Sans,9").pointSize, 9);
assert.equal(parseFontSpec("Inter").family, "Inter");
assert.equal(parseFontSpec("Inter").pointSize, 0, "a family alone carries no size");
assert.equal(parseFontSpec("").family, "", "an empty spec names no family");
assert.equal(parseFontSpec(undefined).family, "");
// A garbage size is not a reason to drop an otherwise usable family.
assert.equal(parseFontSpec("Inter,wide").family, "Inter");
assert.equal(parseFontSpec("Inter,wide").pointSize, 0);

// The [General] group only: [Icons] Theme= and [KDE] font= lookalikes must not
// be mistaken for the interface font.
assert.equal(fontSpecFromConfig(kde6), "Maple Mono NF CN,10");
assert.equal(fontSpecFromConfig(serialised), "Noto Sans,10,-1,5,50,0,0,0,0,0");
assert.equal(fontSpecFromConfig(onlyFamily), "Inter");
assert.equal(fontSpecFromConfig(""), "", "no file is no font, not a crash");
assert.equal(fontSpecFromConfig(undefined), "");
assert.equal(fontSpecFromConfig("[Icons]\nfont=Wrong\n"), "",
    "[Icons] font= is a theme key, not the interface font");
assert.equal(fontSpecFromConfig("[KDE]\nfont=Wrong\n"), "",
    "only [General] owns the interface font");
assert.equal(fontSpecFromConfig("[general]\nfont=Inter,10\n"), "Inter,10",
    "KConfig group spelling is case-insensitive");
assert.equal(fontSpecFromConfig("[General]\nFont=Inter,10\n"), "Inter,10",
    "KConfig key spelling is case-insensitive");
assert.equal(fontSpecFromConfig("[General]\nmenuFont=Other,10\n"), "",
    "the menu font is a different setting");
assert.equal(fontSpecFromConfig("[General]\nfont =Inter,10\n"), "Inter,10",
    "whitespace around the separator is tolerated");
assert.equal(fontSpecFromConfig("[General]\nfont=Inter,10\n[Icons]\nTheme=x\n"), "Inter,10",
    "a later group does not erase the value");

// resolveFamily: the configured family wins; an unreadable file falls back to
// the font Qt already applied, which is what the desktop is drawing with.
assert.equal(resolveFamily("Maple Mono NF CN,10", "Sans Serif"), "Maple Mono NF CN");
assert.equal(resolveFamily("", "Sans Serif"), "Sans Serif");
assert.equal(resolveFamily("", ""), "");
assert.equal(resolveFamily(undefined, "DejaVu Sans"), "DejaVu Sans");
assert.equal(resolveFamily("Inter", undefined), "Inter");
assert.equal(resolveFamily("Inter,10", "Sans Serif"), "Inter",
    "the point size is not part of the family");

console.log("system font policy: kdeglobals font= parsing and family resolution passed");
