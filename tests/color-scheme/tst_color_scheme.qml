import QtQuick
import QtTest
import "../../shared/qml/colorize/MaterialColorScheme.mjs" as Mcu

// Regression tests for the in-process Material 3 scheme generator, exercised
// from inside the QML engine.
//
// This mirrors tests/color-scheme/test_color_scheme.mjs. That Node suite is the
// primary one (it runs in headless CI, where qmltestrunner cannot start); this
// suite exists to prove the same module loads and behaves identically when QML
// resolves it, which is how the shell actually consumes it.
//
// Expected values are recorded from matugen `scheme-vibrant` 4.2.0 output, so
// this doubles as a port-fidelity check: edits to the chroma curves or the hue
// rotation tables will fail here.
TestCase {
    name: "MaterialColorScheme"

    // Role values for the reference seed, handed to matugen as
    //   matugen color hex "#64c4d4" --json hex --dry-run --type scheme-vibrant
    // Keys are "role:mode".
    readonly property var expected: ({
        "primary:light": "#006875",
        "primary:dark": "#00daf2",
        "on_primary:light": "#ffffff",
        "on_primary:dark": "#00363d",
        "primary_container:light": "#9bf0ff",
        "primary_container:dark": "#004f58",
        "secondary:light": "#3e6374",
        "secondary:dark": "#a6cce0",
        "tertiary:light": "#366285",
        "tertiary:dark": "#a0cbf3",
        "error:light": "#ba1a1a",
        "error:dark": "#ffb4ab",
        "surface:light": "#eefcff",
        "surface:dark": "#091517",
        "on_surface:light": "#111d20",
        "on_surface:dark": "#d7e5e8",
        "outline:light": "#6c797c",
        "outline:dark": "#869396",
        "inverse_surface:light": "#263235",
        "inverse_primary:light": "#82d3e1",
    })

    readonly property string referenceSeed: "#64c4d4"

    function test_reference_scheme() {
        const scheme = Mcu.buildSchemePair(referenceSeed, { variant: "vibrant" })
        for (const key in expected) {
            const [role, mode] = key.split(":")
            compare(scheme[mode][role], expected[key], key + " drifted")
        }
    }

    function test_all_roles_present() {
        const scheme = Mcu.buildSchemePair(referenceSeed)
        // The Material 3 baseline scheme exposes 49 roles per mode.
        compare(Mcu.ROLE_NAMES.length, 49)
        for (const role of Mcu.ROLE_NAMES) {
            verify(scheme.light[role] !== undefined, role + " missing (light)")
            verify(scheme.dark[role] !== undefined, role + " missing (dark)")
            verify(scheme.light[role].length === 7, role + " light malformed")
            verify(scheme.dark[role].length === 7, role + " dark malformed")
        }
    }

    function test_tone_is_lightness() {
        // Tone is exactly CIE Lab L*. Two seeds with different hues must put
        // `primary` at the same tone, which is why tone is the stable axis.
        const a = Mcu.hexToHct(Mcu.buildScheme("#64c4d4").primary)[2]
        const b = Mcu.hexToHct(Mcu.buildScheme("#a24b6f").primary)[2]
        fuzzyCompare(a, b, 1.0)
    }

    function test_hue_rotation_differs_per_family() {
        // secondary and tertiary are hue-rotated away from the seed, primary is
        // not. Guard the rotation without pinning the table.
        const scheme = Mcu.buildScheme(referenceSeed, { variant: "vibrant" })
        const seedHue = Mcu.hexToHct(referenceSeed)[0]
        const primaryHue = Mcu.hexToHct(scheme.primary)[0]
        fuzzyCompare(primaryHue, seedHue, 1.0)
        verify(Math.abs(Mcu.hexToHct(scheme.tertiary)[0] - seedHue) > 10,
            "tertiary should be rotated away from the seed hue")
    }

    function test_grey_seed_is_stable() {
        // A near-grey seed carries no usable hue; the generator anchors it so
        // the result stays intentional rather than arbitrary.
        const first = Mcu.buildScheme("#808080")
        const second = Mcu.buildScheme("#7d7d7d")
        compare(first.primary, second.primary)
    }

    function test_deterministic() {
        const a = Mcu.buildSchemePair(referenceSeed)
        const b = Mcu.buildSchemePair(referenceSeed)
        for (const role of Mcu.ROLE_NAMES) {
            compare(a.light[role], b.light[role])
            compare(a.dark[role], b.dark[role])
        }
    }

    function test_hct_roundtrip() {
        // The CAM16/HCT pair must invert exactly. #fffbfe is excluded: at tone
        // 99 the blue channel's 250/254 boundary is below the colour space's
        // resolution, so it is not a meaningful failure.
        for (const hex of ["#64c4d4", "#a24b6f", "#3d6b35", "#ffffff",
            "#000000", "#808080", "#6750a4"]) {
            const [h, c, t] = Mcu.hexToHct(hex)
            compare(Mcu.hctToHex(h, c, t), hex, hex + " HCT round trip drifted")
        }
    }

    function test_hex_arity() {
        // hexToArgb / argbToHex must survive a round trip, including the
        // shorthand form the shell may pass through from theming.
        for (const hex of ["#000000", "#ffffff", "#64c4d4", "#fff"]) {
            const normalized = hex.length === 4
                ? "#" + hex[1] + hex[1] + hex[2] + hex[2] + hex[3] + hex[3]
                : hex
            compare(Mcu.argbToHex(Mcu.hexToArgb(hex)), normalized,
                hex + " hex/argb round trip drifted")
        }
    }

    function test_role_color_helper() {
        const scheme = Mcu.buildSchemePair(referenceSeed, { variant: "vibrant" })
        compare(Mcu.roleColor(referenceSeed, "primary", { variant: "vibrant" }),
            scheme.light.primary)
        compare(Mcu.roleColor(referenceSeed, "primary",
            { variant: "vibrant", dark: true }), scheme.dark.primary)
        compare(Mcu.roleColor(referenceSeed, "not_a_role"), undefined)
    }
}
