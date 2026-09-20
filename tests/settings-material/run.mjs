import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { ROLE_NAMES } from "../../shared/qml/colorize/MaterialColorScheme.mjs";

// The settings window is a separate process, so its Material form is put
// together from two things that live elsewhere: the role names the shell's
// scheme implementation emits, and the accent each shared control is handed.
// Both are strings, and both fail *silently* when they are wrong -- a role name
// the palette does not carry resolves to undefined and falls back to the iPadOS
// literal (the window then claims to be Material while looking like macOS), and
// a control that is not handed an accent keeps its own iPadOS blue default.
//
// That is exactly what shipped: `role("surfaceContainerLow")` against a scheme
// that emits `surface_container_low`. Only the single-word roles resolved, so
// the sidebar, the selection and every text colour stayed iPadOS while the
// window reported `materialForm` correctly. This file is the tripwire for that
// class of mistake, and it has to run without Qt.

const settings = readFileSync(
    new URL("../../apps/settings/main.qml", import.meta.url), "utf8");
let checks = 0;
function check(condition, message) {
    checks += 1;
    assert.ok(condition, message);
}

// ---------------------------------------------------------------------------
// 1. Every role the window asks for is one the scheme emits
// ---------------------------------------------------------------------------

const known = new Set(ROLE_NAMES);
const asked = [...settings.matchAll(/\brole\(\s*"([^"]+)"/g)].map((m) => m[1]);
check(asked.length >= 10,
    "the window resolves its palette through role(), asked for "
    + asked.length + " names");

for (const name of new Set(asked)) {
    check(known.has(name),
        "the window asks the palette for '" + name + "', which "
        + "MaterialColorScheme does not emit. Names are ROLE_SPEC keys: "
        + "snake_case, e.g. surface_container_low, on_surface_variant.");
}

// The specific shape of the bug: a camelCase name is what a reader expects and
// what the scheme never carries.
for (const name of new Set(asked)) {
    check(!/[A-Z]/.test(name),
        "role name '" + name + "' is camelCase; the scheme's keys are "
        + "snake_case");
}

// ---------------------------------------------------------------------------
// 2. Every shared control that takes an accent is handed one
// ---------------------------------------------------------------------------

// The controls carry the host's palette by design (the module cannot import the
// shell), and their own defaults are the iPadOS originals. A slider or switch
// left without an accent is a piece of the other form sitting in the middle of
// this one.
const ACCENT_CONTROLS = ["LiquidSlider", "LiquidGlassSwitch"];
const lines = settings.split("\n");

for (const control of ACCENT_CONTROLS) {
    const opener = "LiquidControls." + control + " {";
    let found = 0;
    for (let i = 0; i < lines.length; ++i) {
        if (lines[i].trim() !== opener)
            continue
        found += 1;
        let depth = 0;
        let accents = 0;
        for (let j = i; j < lines.length; ++j) {
            const text = lines[j];
            if (/^\s*accentColor:/.test(text))
                accents += 1;
            depth += (text.match(/\{/g) || []).length
                - (text.match(/\}/g) || []).length;
            if (depth === 0 && j >= i) {
                check(accents === 1,
                    control + " at line " + (i + 1) + " carries exactly one "
                    + "accentColor, found " + accents + (accents === 0
                        ? " -- it would keep the iPadOS blue default"
                        : " -- QML refuses a property set twice"));
                break;
            }
        }
    }
    check(found > 0, "the window uses " + control);
}

// ---------------------------------------------------------------------------
// 3. The shared controls are told which form to draw
// ---------------------------------------------------------------------------

check(/ControlForm\.materialForm\s*=/.test(settings),
    "the window sets ControlForm.materialForm; without it every shared "
    + "control draws the liquid-glass form inside a Material window");

// And it does so from a scope that has the value: `isMaterialDesign` exists on
// the display page, not on the objects that apply state, so reading it there is
// a ReferenceError that takes the rest of the function with it.
{
    const assignments = [...settings.matchAll(/(\w+)\.materialForm\s*=/g)]
        .map((m) => m[1]);
    for (const target of assignments)
        check(target === "ControlForm",
            "materialForm is assigned through ControlForm, not " + target);
}

console.log("settings Material form: " + checks + " checks passed, "
    + new Set(asked).size + " palette roles resolved");
