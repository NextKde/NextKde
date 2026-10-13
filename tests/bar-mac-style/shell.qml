import QtQuick
import Quickshell
// qs.Kos.Ui, not Kos.Ui: the wallpaper colour source must be the singleton
// instance AppearanceTokens reads, and that one is reached through the config
// root's alias (the same reason every relative `../../../Kos/Ui` import in the
// tree shares one instance).
import qs.Kos.Ui
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Smoke host for the Bar's mac-style ground (设置 ▸ 顶栏 ▸ 顶栏风格 ▸ mac 风格).
// Loaded offscreen by run.mjs.
//
// The style is a choice plus one intensity knob: the selector turns the
// frosted ground on and off (off is the default Bar, outlines and all), and the
// tint slider -- disabled until the style is on -- sets that ground's opacity.
// The plate opposes the wallpaper while the ink opposes what the strip *looks
// like* -- the wallpaper blended with the plate at the chosen opacity -- so
// every tint stays readable. That blend rule is what this fixture pins: at a
// low tint the strip is still mostly the wallpaper, and an ink that read the
// plate alone would put white type on a bright backdrop.
//
// The chain is a row of bindings -- AppearanceConfigService.barMacTint ->
// AppearanceTokens.bar.* -> ThemeService.barInk -> the Bar's labels and glyphs
// -- and every link renders something plausible while broken, so only the
// resolved colours catch a break. Inputs (wallpaper colour, tint, integration,
// theme) are set explicitly after `ready`, so a developer's own state file
// cannot decide what this measures. It never calls an update* function, so no
// state file is written.
Item {
    id: root

    width: 240
    height: 80

    // The Bar's ink pattern: colour and readability edge both follow the style.
    GlassText {
        id: label
        text: "ink"
        color: ThemeService.barInk
        outlineEnabled: !AppearanceTokens.bar.macStyle
    }

    property var failures: []
    property int stage: 0

    function rgba(color) {
        if (color === undefined)
            return "no colour"
        return [color.r, color.g, color.b]
            .map(value => value.toFixed(2)).join("/")
    }

    function check(name, condition, actual) {
        if (condition)
            return
        failures.push(actual === undefined ? name : name + " [got " + actual + "]")
    }

    function sameColor(a, b) {
        return a !== undefined && b !== undefined
            && Math.abs(a.r - b.r) < 0.01 && Math.abs(a.g - b.g) < 0.01
            && Math.abs(a.b - b.b) < 0.01
    }

    function isWhite(color) {
        return color !== undefined && color.r > 0.9 && color.g > 0.9
            && color.b > 0.9
    }

    function isBlack(color) {
        return color !== undefined && color.r < 0.1 && color.g < 0.1
            && color.b < 0.1
    }

    // The two macOS vibrancy neutrals, whichever one the plate picked.
    function isLightPlate(color) {
        return color !== undefined && color.r > 0.9 && color.g > 0.9
            && color.b > 0.9
    }

    function isDarkPlate(color) {
        return color !== undefined && color.r < 0.2 && color.g < 0.2
            && color.b < 0.2
    }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            if (!AppearanceConfigService.ready)
                return
            root.stage++
            if (root.stage === 1) {
                // Inputs first: a dark wallpaper, the mac style off, the Bar
                // standalone. Nothing here may inherit a saved state file.
                AppearanceConfigService.shellStyle = "macos"
                AppearanceConfigService.themeMode = "dark"
                AppearanceConfigService.barIntegratedWithDock = false
                AppearanceConfigService.barMacStyle = false
                AppearanceConfigService.barMacTint = 0.30
                WallpaperColorSource.proceduralPrimary = "#0f212f"
                return
            }
            if (root.stage === 2) {
                // Off is the default Bar: no plate, the theme ink, and the
                // readability edge stays because nothing paints under the type.
                root.check("the default style keeps the mac ground off",
                    AppearanceTokens.bar.macStyle === false)
                root.check("the default style keeps the theme ink",
                    root.sameColor(ThemeService.barInk,
                        ThemeService.foregroundColor),
                    root.rgba(ThemeService.barInk))
                root.check("the default style keeps the readability outline",
                    label.style === Text.Outline, label.style)
                // The selector turns the style on; the remembered tint comes
                // with it. A dark wallpaper at a low tint: strip still dark.
                AppearanceConfigService.barMacStyle = true
                return
            }
            if (root.stage === 3) {
                root.check("the selector turns the mac ground on",
                    AppearanceTokens.bar.macStyle === true)
                root.check("the tint reaches the tokens",
                    Math.abs(AppearanceTokens.bar.macTint - 0.30) < 0.001,
                    AppearanceTokens.bar.macTint)
                root.check("a dark wallpaper takes the light plate",
                    AppearanceTokens.bar.macPlateIsLight === true)
                root.check("the plate is the macOS light grey",
                    root.isLightPlate(AppearanceTokens.bar.macTintColor),
                    root.rgba(AppearanceTokens.bar.macTintColor))
                root.check("a 30% tint over a dark wallpaper is still dark",
                    AppearanceTokens.bar.macStripIsLight === false,
                    AppearanceTokens.bar.macStripLuminance)
                root.check("the ink on it is white",
                    root.isWhite(ThemeService.barInk),
                    root.rgba(ThemeService.barInk))
                root.check("white type drops the readability outline",
                    label.style === Text.Normal, label.style)
                // Raise the tint past the crossover: the same wallpaper, now
                // under a mostly-opaque light plate.
                AppearanceConfigService.barMacTint = 0.80
                return
            }
            if (root.stage === 4) {
                root.check("an 80% tint over a dark wallpaper turns the strip light",
                    AppearanceTokens.bar.macStripIsLight === true,
                    AppearanceTokens.bar.macStripLuminance)
                root.check("the ink flips to black against it",
                    root.isBlack(ThemeService.barInk),
                    root.rgba(ThemeService.barInk))
                root.check("the theme ink itself is unchanged",
                    root.isWhite(ThemeService.foregroundColor),
                    root.rgba(ThemeService.foregroundColor))
                // A bright wallpaper: the plate opposes it, but at a low tint
                // the strip stays light -- and so must the ink.
                WallpaperColorSource.proceduralPrimary = "#f0f0f0"
                AppearanceConfigService.barMacTint = 0.30
                return
            }
            if (root.stage === 5) {
                root.check("a bright wallpaper takes the dark plate",
                    AppearanceTokens.bar.macPlateIsLight === false)
                root.check("the plate is the macOS dark grey",
                    root.isDarkPlate(AppearanceTokens.bar.macTintColor),
                    root.rgba(AppearanceTokens.bar.macTintColor))
                root.check("a 30% tint over a bright wallpaper is still light",
                    AppearanceTokens.bar.macStripIsLight === true,
                    AppearanceTokens.bar.macStripLuminance)
                root.check("the ink follows the strip, not the plate, and is black",
                    root.isBlack(ThemeService.barInk),
                    root.rgba(ThemeService.barInk))
                AppearanceConfigService.barMacTint = 0.85
                return
            }
            if (root.stage === 6) {
                root.check("an 85% tint over a bright wallpaper turns the strip dark",
                    AppearanceTokens.bar.macStripIsLight === false,
                    AppearanceTokens.bar.macStripLuminance)
                root.check("the ink flips to white against it",
                    root.isWhite(ThemeService.barInk),
                    root.rgba(ThemeService.barInk))
                // An integrated Bar lives inside the Dock's glass: the style
                // must not reach it, whatever the slider says.
                AppearanceConfigService.barIntegratedWithDock = true
                return
            }
            if (root.stage === 7) {
                root.check("an integrated Bar stays on the default style",
                    AppearanceTokens.bar.macStyle === false)
                root.check("an integrated Bar keeps the theme ink",
                    root.sameColor(ThemeService.barInk,
                        ThemeService.foregroundColor),
                    root.rgba(ThemeService.barInk))
                root.check("an integrated Bar keeps its outline",
                    label.style === Text.Outline, label.style)
                // Back to a standalone Bar. The style is a switch and the
                // tint survives it: this is what the disabled slider showing
                // its value means.
                AppearanceConfigService.barIntegratedWithDock = false
                return
            }
            if (root.stage === 8) {
                root.check("a standalone Bar shows the mac ground again",
                    AppearanceTokens.bar.macStyle === true)
                root.check("the tint survived the integration round trip",
                    Math.abs(AppearanceTokens.bar.macTint - 0.85) < 0.001,
                    AppearanceTokens.bar.macTint)
                root.check("so does the ink it implies",
                    root.isWhite(ThemeService.barInk),
                    root.rgba(ThemeService.barInk))
                AppearanceConfigService.barMacStyle = false
                return
            }
            if (root.stage >= 9) {
                root.check("turning the style off restores the default Bar",
                    AppearanceTokens.bar.macStyle === false)
                root.check("turning the style off restores the theme ink",
                    root.sameColor(ThemeService.barInk,
                        ThemeService.foregroundColor),
                    root.rgba(ThemeService.barInk))
                if (root.failures.length > 0)
                    console.error("BAR_MAC_STYLE_FAIL: " + root.failures.join("; "))
                else
                    console.error("BAR_MAC_STYLE_PASS")
                Qt.quit()
            }
        }
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: {
            console.error("BAR_MAC_STYLE_FAIL: timeout after stage " + root.stage)
            Qt.quit()
        }
    }
}
