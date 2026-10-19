import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.bar

// 使用系统字体, read where the shell resolves it. Loaded offscreen by run.mjs.
//
// The option is a chain -- AppearanceConfigService.useSystemFont →
// SystemFontService (kdeglobals) → AppearanceTokens.typography.* → the string
// each Text item binds -- and every link fails *silently*: a Text that keeps its
// designed family still renders a plausible interface, just not the user's font.
// This fixture reads the resolved `font.family` off representative Text items in
// both states, so the chain is exercised the way the shell evaluates it.
//
// It does not wait for AppearanceConfigService.ready: that gates on state.read
// through the platform daemon, which this harness deliberately does not run. The
// option is a plain property, so assigning it is exactly what a snapshot load
// does.
Item {
    id: root

    width: 420
    height: 220

    property var failures: []
    property int stage: 0

    function check(name, condition, actual) {
        if (condition)
            return
        failures.push(name + (actual === undefined ? "" : " [got " + actual + "]"))
    }

    // One representative of each role the shell binds.
    Text { id: textRole; font.family: AppearanceTokens.typography.textFamily; text: "x" }
    Text { id: displayRole; font.family: AppearanceTokens.typography.displayFamily; text: "1" }
    Text { id: chainRole; font.family: AppearanceTokens.typography.displayChain; text: "y" }
    Text { id: emojiRole; font.family: AppearanceTokens.typography.emojiFamily; text: "z" }
    // A shipping consumer, so the fixture also notices a surface that stops
    // reading the token even though the token itself still resolves.
    UsageRing { id: ring; value: 0.5; label: "CPU" }

    Timer {
        interval: 150
        repeat: true
        running: true
        onTriggered: {
            // The FileView is asynchronous: wait for the real kdeglobals read so
            // the "on" state is checked against the family the file names.
            if (!SystemFontService.loaded)
                return
            root.stage++
            if (root.stage === 1) {
                root.check("kdeglobals names a family",
                    SystemFontService.family === "Maple Mono NF CN",
                    SystemFontService.family)
                // Branches only: no update* call, so no state file is written
                // through the daemon this harness does not run.
                AppearanceConfigService.useSystemFont = false
                return
            }
            if (root.stage === 2) {
                root.check("off keeps the designed text family",
                    textRole.font.family === "Noto Sans CJK SC", textRole.font.family)
                // The designed display face is only named when it is installed;
                // otherwise the role is empty, which delegates to the platform
                // font. That is the behaviour every one of these sites had with
                // the literal before the token existed.
                root.check("off keeps the designed display family",
                    displayRole.font.family === (AppearanceTokens.typography
                        .hasRecommendedDisplayFamily ? "SF Pro Display" : ""),
                    displayRole.font.family)
                root.check("off keeps the designed chain",
                    chainRole.font.family === "SF Pro Display, Noto Sans CJK SC, sans-serif",
                    chainRole.font.family)
                root.check("emoji never follow the interface font",
                    emojiRole.font.family === "Noto Color Emoji", emojiRole.font.family)
                root.check("the token agrees with the option",
                    AppearanceTokens.typography.followsSystemFont === false,
                    AppearanceTokens.typography.followsSystemFont)
                AppearanceConfigService.useSystemFont = true
                return
            }
            if (root.stage === 3) {
                const expected = "Maple Mono NF CN"
                root.check("the token follows the option",
                    AppearanceTokens.typography.followsSystemFont === true,
                    AppearanceTokens.typography.followsSystemFont)
                root.check("text follows the system font",
                    textRole.font.family === expected, textRole.font.family)
                root.check("display type follows the system font",
                    displayRole.font.family === expected, displayRole.font.family)
                root.check("a surface that asked for a chain resolves to one family",
                    chainRole.font.family === expected, chainRole.font.family)
                root.check("emoji still do not follow it",
                    emojiRole.font.family === "Noto Color Emoji", emojiRole.font.family)
                root.check("a shipping consumer still loads", ring.label === "CPU",
                    ring.label)
                // Round trip: the option, not a restart, is what moved every
                // family, so turning it back off has to restore the designed
                // ones.
                AppearanceConfigService.useSystemFont = false
                return
            }
            if (root.stage >= 4) {
                root.check("turning it off restores the designed text family",
                    textRole.font.family === "Noto Sans CJK SC", textRole.font.family)
                root.check("turning it off restores the designed display family",
                    displayRole.font.family === (AppearanceTokens.typography
                        .hasRecommendedDisplayFamily ? "SF Pro Display" : ""),
                    displayRole.font.family)
                if (root.failures.length > 0)
                    console.error("FONT_FAIL: " + root.failures.join("; "))
                else
                    console.error("FONT_PASS")
                Qt.quit()
            }
        }
    }

    Timer {
        interval: 9000
        running: true
        onTriggered: {
            console.error("FONT_FAIL: timeout after stage " + root.stage
                + (root.failures.length > 0 ? " (" + root.failures.join("; ") + ")" : ""))
            Qt.quit()
        }
    }
}
