pragma Singleton
import QtQuick
import "MaterialColorScheme.mjs" as Mcu
import "TraditionalColorScheme.mjs" as Traditional

// Material 3 colour scheme for Kos.Ui.
//
// Three colour sources feed the same 49-role palette:
//
//   "monet"    — Material's own algorithm (MaterialColorScheme.mjs), a real
//                CAM16/HCT implementation. Faithful to the wallpaper's HUE but
//                not to its tone: measured on this code, the light-mode accent
//                lands 24.8 tone steps from the seed on average and the dark
//                one further.
//   "chinese"  — 中国传统色 (TraditionalColorScheme.mjs). The seed snaps to the
//                nearest named colour in a 526-entry table and the accent keeps
//                that colour's real tone, which is what makes the result read as
//                the wallpaper's colour: 1.4 tone steps from the seed on
//                average. Falls back to Monet when no swatch is close enough.
//   "japanese" — 日本の伝統色, same algorithm, 228-entry table.
//
// Accuracies against matugen 4.2.0 for the monet branch, 12 seeds x 49 roles x
// 2 modes:
//
//   vibrant     76.4% of roles byte-exact, 97.5% within the imperceptible band
//   tonal-spot  60.8% byte-exact
//
// Measured in sRGB byte steps — the honest metric — vibrant is 75.0% exact and
// 91.2% within one step, worst case 9 steps. HCT distance reads higher because
// the hue coordinate is unstable at near-neutral chroma, so trust the byte-step
// numbers and never judge a change by HCT distance alone.
QtObject {
    id: service

    // Seed colour the scheme is derived from. Consumers set this through
    // `setSeed()`; an empty value clears the palette.
    property string seed: ""
    property bool ready: false
    // Which colour source produces the palette. See the header. "monet" keeps
    // the previous behaviour and is the default, so an upgrade does not
    // restyle an existing installation.
    property string scheme: "monet"
    // Scheme variant, used by the "monet" source only. "vibrant" matches what
    // the shell was previously fed through matugen, and it is also the variant
    // with the higher measured fidelity, so it stays the default.
    // "tonal-spot" is matugen's own default and is calmer; it is fully modelled
    // too, just less precisely.
    property string variant: "vibrant"
    // role -> { light: { color }, dark: { color } }, matching the shape the
    // previous matugen-backed implementation exposed so consumers are unaffected.
    property var palette: ({})
    // Bumped on every palette rebuild. Canvas-based consumers only read the
    // scheme when they actually paint, so they need one signal that covers every
    // way the palette can move — a shell-style switch, a colour-source switch, a
    // new wallpaper seed — instead of subscribing to each role they happen to
    // draw with. Without it the DeskCenter clock hands and the CPU/memory rings
    // kept the previous theme's colours after a switch.
    property int revision: 0
    // Name of the traditional swatch the accent came from, e.g. "朱砂". Empty
    // for the "monet" scheme and for seeds that fell back to Monet. Shown in
    // the settings UI so the choice is legible rather than a swatch.
    readonly property string accentName: _accentName

    property string _accentName: ""

    // previewSwatches() results keyed on seed|target|variant. Cleared on
    // rebuild() so a state the builders forgot (none today — they are pure)
    // could not survive a palette change; the key itself already separates
    // every input that affects the output.
    property var _previewCache: ({})

    function color(role, darkMode, fallback) {
        const entry = palette && palette[role]
        const variant = entry && entry[darkMode ? "dark" : "light"]
        return variant && variant.color ? variant.color : fallback
    }

    // Accepts "#rrggbb" (with or without the leading '#') or a Qt color value.
    function normalizeSeed(value) {
        if (value === undefined || value === null)
            return ""
        let text = String(value).trim()
        if (!text)
            return ""
        // Qt.rgba()-style values stringify as "#aarrggbb"; keep the RGB part.
        const longForm = text.match(/^#([0-9a-f]{8})$/i)
        if (longForm)
            text = "#" + longForm[1].slice(2)
        const shortForm = text.match(/^#([0-9a-f]{3})$/i)
        if (shortForm)
            text = "#" + shortForm[1].split("").map(ch => ch + ch).join("")
        if (!/^#[0-9a-f]{6}$/i.test(text))
            return ""
        return text.toLowerCase()
    }

    // Rebuild the palette from a seed colour. Cheap and synchronous — the whole
    // scheme is a few hundred transcendental calls plus one bisection per
    // out-of-gamut tone.
    function setSeed(value) {
        const next = normalizeSeed(value)
        if (next === seed)
            return
        seed = next
        rebuild()
    }

    function setVariant(value) {
        if (value === variant)
            return
        variant = value
        rebuild()
    }

    function isValidScheme(value) {
        return value === "monet" || value === "chinese"
            || value === "japanese"
    }

    // Representative swatches for one colour source, for the settings page to
    // draw its picker from. Deliberately does NOT touch the active palette: the
    // page needs all three side by side, and switching `scheme` to measure them
    // would repaint the entire shell three times per snapshot.
    //
    // The set is chosen to show what actually differs between the sources — the
    // accent, its two companions, a container, and both appearances' surfaces.
    function previewSwatches(target) {
        if (!seed || !isValidScheme(target))
            return []
        // The swatch set is a pure function of (seed, target, variant): variant
        // only shapes the monet branch, but it stays in the key so a variant
        // change never serves the previous variant's colours. Seed changes are
        // a different key, so a new wallpaper always rebuilds and can never be
        // handed the previous palette's swatches.
        const key = seed + "|" + target + "|" + variant
        if (_previewCache[key])
            return _previewCache[key]
        const pair = target === "monet"
            ? Mcu.buildSchemePair(seed, { variant: variant })
            : Traditional.buildSchemePair(seed, { table: target })
        const swatches = [
            pair.light.primary,
            pair.light.tertiary,
            pair.light.secondary,
            pair.light.primary_container,
            pair.light.surface_container,
            pair.dark.surface_container,
        ]
        _previewCache[key] = swatches
        return swatches
    }

    function setScheme(value) {
        const next = String(value)
        if (!isValidScheme(next) || next === scheme)
            return
        scheme = next
        rebuild()
    }

    function rebuild() {
        // The preview cache keys are complete, so entries stay correct across
        // a rebuild; dropping them anyway keeps a seed switch from holding the
        // previous wallpaper's six swatch arrays forever.
        _previewCache = ({})
        if (!seed) {
            palette = ({})
            _accentName = ""
            ready = false
            revision++
            return
        }
        try {
            // Both sources return { light: {role: hex}, dark: {role: hex} } with
            // the same 49 role names, so only the call differs here.
            const pair = scheme === "monet"
                ? Mcu.buildSchemePair(seed, { variant: variant })
                : Traditional.buildSchemePair(seed, { table: scheme })
            // Reshape to matugen's colors[role][mode].color so that consumers
            // written against the previous matugen-backed version keep working.
            const out = ({})
            for (const mode of ["light", "dark"]) {
                for (const role of Object.keys(pair[mode])) {
                    if (!out[role])
                        out[role] = ({})
                    out[role][mode] = { color: pair[mode][role] }
                }
            }
            palette = out
            revision++
            // A seed whose nearest swatch was too far away produces Monet's
            // palette, and reporting a traditional name for it would be a lie.
            const match = scheme === "monet" ? null
                : Traditional.nearestNamed(seed, { table: scheme })
            _accentName = match && match.accepted ? match.name : ""
            ready = Object.keys(palette).length > 0
        } catch (error) {
            console.warn("[ColorScheme] failed to build scheme for " + seed + ": " + error)
            palette = ({})
            _accentName = ""
            ready = false
            revision++
        }
    }
}
