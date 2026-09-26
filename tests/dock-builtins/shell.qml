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
                if (Quickshell.env("KOS_TEST_RELOAD") === "1") {
                    check(!ConfigService.showLauncher && !ConfigService.showTrash,
                        "hidden icons must stay hidden across a shell restart")
                    check(ConfigService.updateBuiltinVisibility("launcher", true),
                        "a hidden launcher must be restorable")
                    check(!ConfigService.showTrash, "restoring launcher changed trash")
                    check(ConfigService.updateBuiltinVisibility("trash", true),
                        "a hidden trash icon must be restorable")
                    console.log("DOCK_BUILTINS_RELOAD_PASS")
                    Qt.quit()
                    return
                }
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
                ConfigService.updateBuiltinVisibility("trash", false)
                check(ConfigService.showLauncher, "hiding trash changed launcher")
                ConfigService.updateBuiltinVisibility("launcher", false)
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
            if (saved.showLauncher === false && saved.showTrash === false) {
                console.log("DOCK_BUILTINS_SAVE_PASS")
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
