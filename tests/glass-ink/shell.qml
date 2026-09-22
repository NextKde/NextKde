import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Smoke host for the glass ink rule (设置 ▸ 显示 ▸ 系统外观 ▸ 液态玻璃跟随外观模式).
// Loaded offscreen by run.mjs.
//
// There is one option, not two: 液态玻璃跟随外观模式 decides whether the glass
// itself takes the resolved appearance. While it is off the glass stays dark in
// both appearances, so the ink that reads on it is the fixed white the shell has
// always drawn. Turning it on lets a light appearance light the glass, and the
// same ink turns dark with it. The rule is therefore "the ink follows the glass",
// never "the ink follows the desktop theme": with the option off on a light
// desktop the glass is still dark and white type is still correct, which is
// exactly what a system-theme test would get wrong.
//
// That rule is a chain of bindings -- AppearanceConfigService →
// AppearanceTokens → IconAppearanceService.glassContentColor →
// LiquidGlassSurface / GlassText / the Dock's ink roles -- and every link can
// break silently: a surface that keeps its own literal still looks right while
// the glass is dark, and only a light glass reveals white-on-white. This fixture
// walks the states the option can be in and reads the resolved colours, so the
// chain is exercised the way the shell evaluates it, not the way the source
// reads.
//
// The saved appearance is read at startup (through the platform daemon), so
// every value that decides the outcome is set explicitly after `ready` -- the
// option included, because a developer's own state file must not decide what
// this test measures. The fixture never calls an update* function, so no state
// file is written.
Item {
    id: root

    width: 240
    height: 80

    LiquidGlassPanel { id: panel; width: 200; height: 60; radius: 12 }
    GlassText { id: label; text: "ink" }

    property var failures: []
    property int stage: 0

    // Failures name the colour that broke the rule: a bare "expected dark"
    // cannot tell an unseeded palette from a branch that read the desktop
    // theme instead of the glass.
    function rgba(color) {
        if (color === undefined)
            return "no colour"
        return [color.r, color.g, color.b]
            .map(value => value.toFixed(2)).join("/")
    }
    function check(name, condition, actual) {
        if (condition)
            return
        failures.push(actual === undefined
            ? name : name + " [got " + actual + "]")
    }
    function isWhite(color) {
        return color !== undefined && color.r > 0.9 && color.g > 0.9
            && color.b > 0.9
    }
    function isDark(color) {
        return color !== undefined && color.r < 0.25 && color.g < 0.25
            && color.b < 0.25
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
                // A light desktop with the option off is the trap: the shell
                // resolves light, but the glass does not follow, so it stays
                // dark and the ink stays white. Nothing here may inherit a saved
                // shell style or appearance mode.
                AppearanceConfigService.shellStyle = "macos"
                AppearanceConfigService.themeMode = "light"
                AppearanceConfigService.glassFollowsAppearanceMode = false
                return
            }
            if (root.stage === 2) {
                root.check("the desktop resolves light",
                    AppearanceTokens.resolvedAppearanceIsDark === false)
                root.check("an opted-out glass is dark on a light desktop",
                    AppearanceTokens.isDarkTheme === true)
                root.check("dark glass foreground is white",
                    root.isWhite(panel.foregroundColor),
                    root.rgba(panel.foregroundColor))
                root.check("dark glass secondary is white",
                    panel.secondaryForegroundColor.r > 0.9,
                    root.rgba(panel.secondaryForegroundColor))
                root.check("dark glass text is white",
                    root.isWhite(label.color), root.rgba(label.color))
                root.check("white type keeps the readability outline",
                    label.style === Text.Outline, label.style)
                root.check("the dock's ink role is white on the dark glass",
                    root.isWhite(ThemeService.foregroundColor),
                    root.rgba(ThemeService.foregroundColor))
                // Light glass: the same light desktop, now following it.
                AppearanceConfigService.glassFollowsAppearanceMode = true
                return
            }
            if (root.stage === 3) {
                root.check("the glass now follows the light desktop",
                    AppearanceTokens.isDarkTheme === false)
                root.check("light glass foreground is dark",
                    root.isDark(panel.foregroundColor),
                    root.rgba(panel.foregroundColor))
                root.check("light glass secondary is dark",
                    panel.secondaryForegroundColor.r < 0.3,
                    root.rgba(panel.secondaryForegroundColor))
                root.check("light glass text is dark",
                    root.isDark(label.color), root.rgba(label.color))
                root.check("black type drops the readability outline",
                    label.style === Text.Normal, label.style)
                root.check("the dock's ink role turns dark with the glass",
                    root.isDark(ThemeService.foregroundColor),
                    root.rgba(ThemeService.foregroundColor))
                AppearanceConfigService.themeMode = "dark"
                return
            }
            if (root.stage === 4) {
                root.check("a dark desktop keeps the glass dark",
                    AppearanceTokens.isDarkTheme === true)
                root.check("dark glass foreground is white again",
                    root.isWhite(panel.foregroundColor),
                    root.rgba(panel.foregroundColor))
                root.check("dark glass text is white again",
                    root.isWhite(label.color), root.rgba(label.color))
                // Round trip: the option, not the desktop, is what moved the
                // ink, so putting it back has to put the white ink back.
                AppearanceConfigService.themeMode = "light"
                AppearanceConfigService.glassFollowsAppearanceMode = false
                return
            }
            if (root.stage === 5) {
                root.check("turning the option off restores the white ink",
                    root.isWhite(panel.foregroundColor),
                    root.rgba(panel.foregroundColor))
                root.check("opted-out light glass text is white again",
                    root.isWhite(label.color), root.rgba(label.color))
                // Material never reads the option: its tonal form follows the
                // appearance on its own, so a light scheme already carried dark
                // ink before this rule existed and must not change here.
                AppearanceConfigService.shellStyle = "material"
                return
            }
            if (root.stage >= 6) {
                root.check("material still follows a light appearance",
                    AppearanceTokens.isDarkTheme === false)
                root.check("material light glass foreground is dark",
                    root.isDark(panel.foregroundColor),
                    root.rgba(panel.foregroundColor))
                root.check("material light glass text is dark",
                    root.isDark(label.color), root.rgba(label.color))
                if (root.failures.length > 0)
                    console.error("GLASS_INK_FAIL: " + root.failures.join("; "))
                else
                    console.error("GLASS_INK_PASS")
                Qt.quit()
            }
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.error("GLASS_INK_FAIL: timeout after stage " + root.stage)
            Qt.quit()
        }
    }
}
