import QtQuick
import "Kos/Ui"
import qs.desktop.modules.common

// Smoke host for the traditional-colour scheme, loaded offscreen by run.mjs.
//
// The node suite in test_traditional_color.mjs proves the algorithm. What it
// cannot cover is whether the QML engine can load this module graph at all:
// ColorScheme.qml imports TraditionalColorScheme.mjs by relative path, and that
// module in turn imports ChineseColors.mjs, JapaneseColors.mjs, Cam16Hct.mjs and
// MaterialColorScheme.mjs. Under Node those resolve as ESM; under QML the QML
// module system resolves them, and a file missing from that graph is a runtime
// failure that neither the Node suite nor qmllint would catch. That is what this
// fixture is for — not the colour maths, the wiring.
Item {
    id: root

    width: 10
    height: 10

    property var failures: []

    // Probe: how the shell actually consumes ColorScheme — through a property
    // BINDING, not by calling color() again. Every other assertion in this file
    // and in the node suite calls color() explicitly, which returns the fresh
    // value regardless of whether binding propagation works. This is the one
    // thing that decides whether a scheme switch reaches the UI.
    property color probePrimary: ColorScheme.color("primary", false)
    property color probeSurface: ColorScheme.color("surface", false)


    function check(label, condition) {
        if (!condition)
            root.failures.push(label)
    }

    Component.onCompleted: {
        const schemes = ["monet", "chinese", "japanese"]
        const seed = "#e60012"

        check("ColorScheme singleton is reachable through Kos.Ui",
            typeof ColorScheme !== "undefined")
        check("setScheme exists", typeof ColorScheme.setScheme === "function")
        check("accentName is exposed",
            typeof ColorScheme.accentName === "string")

        ColorScheme.setSeed(seed)
        check("seed accepted and normalised", ColorScheme.seed === seed)

        const accents = ({})
        for (const scheme of schemes) {
            ColorScheme.setScheme(scheme)
            check(scheme + " is selected", ColorScheme.scheme === scheme)
            check(scheme + " reports ready", ColorScheme.ready === true)
            // 49 roles + source_color, the shape every shell consumer reads.
            check(scheme + " produces 50 entries",
                Object.keys(ColorScheme.palette).length === 50)
            for (const role of ["primary", "on_primary", "primary_container",
                "secondary", "tertiary", "error", "surface", "on_surface",
                "outline", "background"]) {
                const light = String(ColorScheme.color(role, false))
                const dark = String(ColorScheme.color(role, true))
                check(scheme + " " + role + ":light resolves",
                    /^#[0-9a-f]{6,8}$/i.test(light))
                check(scheme + " " + role + ":dark resolves",
                    /^#[0-9a-f]{6,8}$/i.test(dark))
            }
            accents[scheme] = String(ColorScheme.color("primary", false))
        }

        // If a traditional table returned Monet's accent the setting would be a
        // no-op that still costs the user a choice.
        check("chinese accent differs from monet",
            accents.chinese !== accents.monet)
        check("japanese accent differs from monet",
            accents.japanese !== accents.monet)

        ColorScheme.setScheme("chinese")
        check("a matched seed reports its swatch name",
            ColorScheme.accentName.length > 0)

        ColorScheme.setScheme("monet")
        check("monet reports no swatch name",
            ColorScheme.accentName === "")

        // ── binding propagation ──────────────────────────────────────────
        // A bound property must re-evaluate when the palette is rebuilt; if it
        // does not, the scheme switch never reaches a consumer.
        ColorScheme.setSeed("#4a4a6a")
        ColorScheme.setScheme("monet")
        const boundMonet = String(root.probePrimary)
        const boundSurfaceMonet = String(root.probeSurface)
        ColorScheme.setScheme("chinese")
        const boundChinese = String(root.probePrimary)
        const boundSurfaceChinese = String(root.probeSurface)
        check("bound primary follows setScheme (monet " + boundMonet
            + " vs chinese " + boundChinese + ")", boundMonet !== boundChinese)
        check("bound surface follows setScheme (monet " + boundSurfaceMonet
            + " vs chinese " + boundSurfaceChinese + ")",
            boundSurfaceMonet !== boundSurfaceChinese)
        console.log("BINDING_PROBE monet=" + boundMonet + "/" + boundSurfaceMonet
            + " chinese=" + boundChinese + "/" + boundSurfaceChinese)

        // ColorScheme.revision is what Canvas consumers repaint on; if it stops
        // moving, a theme switch or colour-source switch leaves stale drawings
        // — which is exactly what happened to the clock hands and the CPU ring.
        ColorScheme.setScheme("monet")
        const revisionBefore = ColorScheme.revision
        ColorScheme.setScheme("chinese")
        check("revision bumps when the palette is rebuilt",
            ColorScheme.revision > revisionBefore)

        // ── layer ladder ─────────────────────────────────────────────────
        // AppearanceTokens tints each Material surface with the accent, and the
        // ratios live on the singleton itself. An earlier revision declared
        // them inside the nested `colors` object while referencing
        // `tokens._layerTint0` — an unresolvable path, so the ratio came back
        // undefined and every layer became Qt.rgba(NaN, NaN, NaN, 1). Invalid
        // colours paint black: cards turned illegible, and because a broken
        // value is the same broken value under every scheme, switching colour
        // sources looked like a no-op. Both symptoms are asserted against here,
        // and neither is visible to the node suite or to qmllint.
        check("layer tint ratios resolve",
            AppearanceTokens._layerTint0 > 0 && AppearanceTokens._layerTint1 > 0
            && AppearanceTokens._layerTint2 > 0 && AppearanceTokens._layerTint3 > 0
            && AppearanceTokens._layerTint4 > 0)

        ColorScheme.setScheme("monet")
        const layersMonet = [AppearanceTokens.colors.layer0,
            AppearanceTokens.colors.layer1, AppearanceTokens.colors.layer2,
            AppearanceTokens.colors.layer3,
            AppearanceTokens.colors.layer4].map(c => String(c))
        ColorScheme.setScheme("chinese")
        const layersChinese = [AppearanceTokens.colors.layer0,
            AppearanceTokens.colors.layer1, AppearanceTokens.colors.layer2,
            AppearanceTokens.colors.layer3,
            AppearanceTokens.colors.layer4].map(c => String(c))
        for (let i = 0; i < 5; i++) {
            check("layer" + i + " is a valid colour under monet ("
                + layersMonet[i] + ")",
                /^#[0-9a-f]{6,8}$/i.test(layersMonet[i]))
            check("layer" + i + " is a valid colour under chinese ("
                + layersChinese[i] + ")",
                /^#[0-9a-f]{6,8}$/i.test(layersChinese[i]))
            check("layer" + i + " follows the colour source",
                layersMonet[i] !== layersChinese[i])
        }

        // Back to the default so the assertions above cannot have left the
        // singleton in a state the next load would inherit.
        ColorScheme.setScheme("monet")
        ColorScheme.setSeed("#64c4d4")
    }

    // Let the palette rebuilds above settle into the scene graph before the
    // verdict, so a binding error raised by them is reported as a failure.
    Timer {
        interval: 300
        running: true
        onTriggered: {
            if (root.failures.length > 0)
                console.error("TRADITIONAL_COLOR_FAIL: "
                    + root.failures.join("; "))
            else
                console.log("TRADITIONAL_COLOR_PASS")
            Qt.quit()
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.error("TRADITIONAL_COLOR_FAIL: timeout")
            Qt.quit()
        }
    }
}
