import QtQuick
import Quickshell
import qs.desktop.modules.dock
import qs.desktop.modules.platform

Item {
    property bool started: false

    function check(condition, message) {
        if (!condition)
            throw new Error(message)
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (started || !ConfigService.ready)
                return
            started = true
            try {
                if (Quickshell.env("KOS_TEST_RELOAD") === "2") {
                    check(ConfigService.revealTriggerMode === "fullEdge",
                        "restoring full-edge mode must survive another restart")
                    check(ConfigService.showLauncher && ConfigService.showTrash,
                        "restored built-ins must survive another restart")
                    check(ConfigService.showNotificationBadges, "restored badges survive another restart")
                    console.log("DOCK_BUILTINS_DEFAULT_RELOAD_PASS")
                    Qt.quit()
                    return
                }
                if (Quickshell.env("KOS_TEST_RELOAD") === "1") {
                    check(!ConfigService.showNotificationBadges, "hidden badges survive restart")
                    check(ConfigService.updateNotificationBadgeVisibility(true), "badges can be restored")
                    check(ConfigService.revealTriggerMode === "dockSpan",
                        "opt-in Dock span must survive a shell restart")
                    check(!ConfigService.showLauncher && !ConfigService.showTrash,
                        "hidden icons must stay hidden across a shell restart")
                    check(ConfigService.updateBuiltinVisibility("launcher", true),
                        "a hidden launcher must be restorable")
                    check(!ConfigService.showTrash, "restoring launcher changed trash")
                    check(ConfigService.updateBuiltinVisibility("trash", true),
                        "a hidden trash icon must be restorable")
                    check(!ConfigService.updateRevealTriggerMode("invalid")
                        && ConfigService.revealTriggerMode === "dockSpan",
                        "invalid updates must not replace a saved choice")
                    check(ConfigService.updateRevealTriggerMode("fullEdge"),
                        "full-edge mode must be restorable")
                    savedCheck.start()
                    return
                }
                check(ConfigService.revealTriggerMode === "fullEdge",
                    "legacy and fresh configuration must preserve full-edge behavior")
                for (const invalid of ["", "unknown", null, 1, false])
                    check(!ConfigService.updateRevealTriggerMode(invalid),
                        "invalid reveal trigger updates must be rejected")
                check(ConfigService.updateRevealTriggerMode("dockSpan"),
                    "Dock-span trigger must be selectable")
                check(!ConfigService.updateRevealTriggerMode("dockSpan"),
                    "unchanged trigger mode must not schedule another write")
                ConfigService._apply({ revealTriggerMode: "invalid" })
                check(ConfigService.revealTriggerMode === "fullEdge",
                    "invalid saved reveal trigger falls back to full-edge behavior")
                ConfigService._apply({ revealTriggerMode: "dockSpan" })
                check(ConfigService.revealTriggerMode === "dockSpan",
                    "valid saved reveal trigger must load")
                ConfigService._apply({})
                check(ConfigService.revealTriggerMode === "fullEdge",
                    "missing reveal trigger preserves legacy full-edge behavior")
                check(ConfigService.showLauncher && ConfigService.showTrash,
                    "both icons must be visible by default")
                check(!ConfigService.updateBuiltinVisibility("unknown", false),
                    "unknown controls must not change configuration")
                check(!ConfigService.updateBuiltinVisibility("launcher", "false"),
                    "non-boolean visibility must be rejected")
                check(ConfigService.updateBuiltinVisibility("launcher", false),
                    "launcher can be hidden")
                check(ConfigService.showTrash, "hiding launcher changed trash")
                check(!ConfigService.updateBuiltinVisibility("launcher", false),
                    "unchanged visibility must not schedule another write")
                ConfigService._apply({ showLauncher: "false", showTrash: null })
                check(ConfigService.showLauncher && ConfigService.showTrash,
                    "malformed configuration must preserve visible defaults")
                ConfigService._apply({ showLauncher: false, showTrash: false })
                check(!ConfigService.showLauncher && !ConfigService.showTrash,
                    "explicit false must survive loading")
                ConfigService._apply({})
                check(ConfigService.showLauncher && ConfigService.showTrash,
                    "legacy configuration must preserve visible defaults")
                check(ConfigService.showNotificationBadges, "legacy config defaults badges to visible")
                for (const invalid of ["false", null, 0]) {
                    check(!ConfigService.updateNotificationBadgeVisibility(invalid), "reject invalid badge writes")
                    ConfigService._apply({showNotificationBadges: invalid})
                    check(ConfigService.showNotificationBadges, "invalid stored badge value defaults visible")
                }
                ConfigService._apply({showNotificationBadges: false})
                check(!ConfigService.showNotificationBadges, "explicit false must load")
                ConfigService._apply({})
                check(ConfigService.showNotificationBadges, "missing badge preference remains visible")
                check(!ConfigService.updateNotificationBadgeVisibility(true), "unchanged badge setting is ignored")
                check(ConfigService.updateNotificationBadgeVisibility(false), "badges can be hidden")
                ConfigService.updateBuiltinVisibility("trash", false)
                check(ConfigService.showLauncher, "hiding trash changed launcher")
                ConfigService.updateBuiltinVisibility("launcher", false)
                ConfigService.updateRevealTriggerMode("dockSpan")
                savedCheck.start()
            } catch (error) {
                console.log("FAIL " + error)
                Qt.quit()
            }
        }
    }

    Timer {
        id: savedCheck
        interval: 100
        repeat: true
        onTriggered: JsonConfigStore.readPath(ConfigService.configPath, function(data, exists) {
            if (!exists)
                return
            const saved = JSON.parse(data)
            const reload = Quickshell.env("KOS_TEST_RELOAD") === "1"
            if (saved.showLauncher === reload && saved.showTrash === reload
                    && saved.revealTriggerMode === (reload ? "fullEdge" : "dockSpan")) {
                console.log(reload ? "DOCK_BUILTINS_RELOAD_PASS" : "DOCK_BUILTINS_SAVE_PASS")
                Qt.quit()
            }
        })
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: { console.log("FAIL timeout"); Qt.quit() }
    }
}
