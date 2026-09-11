pragma Singleton
import QtQuick
import "MaterialColorScheme.mjs" as Mcu

// Material 3 colour scheme for Kos.Ui.
//
// The scheme is computed in-process from a seed colour by
// `MaterialColorScheme.mjs`, a real CAM16/HCT implementation of Material's
// algorithm (see that file for why Lab was not good enough). Nothing is
// spawned: no matugen, no python, no ImageMagick. The seed itself is supplied
// by the caller, which already owns an image sampler (`ArtworkColorSource`),
// so no second quantisation pass is needed either.
//
// Accuracy against matugen 4.2.0, 12 seeds x 49 roles x 2 modes:
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
    // Scheme variant. "vibrant" matches what the shell was previously fed
    // through matugen, and it is also the variant with the higher measured
    // fidelity, so it stays the default. "tonal-spot" is matugen's own default
    // and is calmer; it is fully modelled too, just less precisely.
    property string variant: "vibrant"
    // role -> { light: { color }, dark: { color } }, matching the shape the
    // previous matugen-backed implementation exposed so consumers are unaffected.
    property var palette: ({})

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

    function rebuild() {
        if (!seed) {
            palette = ({})
            ready = false
            return
        }
        try {
            // The module returns { light: {role: hex}, dark: {role: hex} }.
            // Reshape to matugen's colors[role][mode].color so that consumers
            // written against the previous matugen-backed version keep working.
            const pair = Mcu.buildSchemePair(seed, { variant: variant })
            const out = ({})
            for (const mode of ["light", "dark"]) {
                for (const role of Object.keys(pair[mode])) {
                    if (!out[role])
                        out[role] = ({})
                    out[role][mode] = { color: pair[mode][role] }
                }
            }
            palette = out
            ready = Object.keys(palette).length > 0
        } catch (error) {
            console.warn("[ColorScheme] failed to build scheme for " + seed + ": " + error)
            palette = ({})
            ready = false
        }
    }
}
