import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.bar

// Verify the default and live General font bindings without an opt-in.
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
            if (root.stage === 1 || root.stage === 2) {
                const expected = root.stage === 1 ? "Maple Mono NF CN" : "Inter"
                root.check("text follows General font by default", textRole.font.family === expected, textRole.font.family)
                root.check("display follows General font", displayRole.font.family === expected, displayRole.font.family)
                root.check("chain follows General font", chainRole.font.family === expected, chainRole.font.family)
                root.check("emoji stays independent", emojiRole.font.family === "Noto Color Emoji", emojiRole.font.family)
                function checkText(item) {
                    if (item.text !== undefined && item.font !== undefined)
                        root.check("UsageRing follows General font", item.font.family === expected, item.font.family)
                    for (const child of item.children || []) checkText(child)
                }
                checkText(ring)
                SystemFontService.applyConfig(root.stage === 1 ? "[General]\nfont=Inter,10\n" : "[General]\n")
                return
            }
            if (root.stage >= 3) {
                root.check("removing font clears the stale family", SystemFontService.fontSpec === "")
                root.check("missing font uses Qt fallback", textRole.font.family === Qt.application.font.family, textRole.font.family)
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
