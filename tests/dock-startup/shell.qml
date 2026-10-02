import QtQuick
import Quickshell
import qs.desktop.modules.dock
import qs.desktop.modules.common

Item {
    id: test
    readonly property string savedMode: Quickshell.env("KOS_TEST_MODE")
    readonly property string savedPosition: Quickshell.env("KOS_TEST_POSITION")
    property int loadedCreations: 0
    property bool failed: false

    function check(condition, message) {
        if (!condition) {
            test.failed = true
            console.log("FAIL " + message)
            Qt.quit()
        }
    }

    Dock {}

    // Wait longer than the auto-hide controller's boot timeout. Until config
    // resolves, even an available output must not receive a provisional Dock.
    Timer {
        interval: 600; running: true
        onTriggered: {
            check(ConfigService.shows === 0, "Dock exposed before saved config resolved")
            if (test.failed) return
            ConfigService.position = test.savedPosition
            ConfigService.visibilityMode = test.savedMode
            ConfigService.ready = true
        }
    }
    Timer {
        interval: 750; running: true
        onTriggered: {
            check(ConfigService.shows === 1, "Exactly one initial Dock exposure")
            check(ConfigService.dockVisible, "Ready Dock must become visible")
            check(ConfigService.exposedMode === test.savedMode, "First exposure uses saved mode")
            check(ConfigService.exposedPosition === test.savedPosition, "First exposure uses saved edge")
            test.loadedCreations = ConfigService.creations
            // A missing screen alone must hide the existing Dock.
            ScreenLifecycle.activeScreen = null
        }
    }
    Timer {
        interval: 850; running: true
        onTriggered: {
            check(!ConfigService.dockVisible, "Missing target screen keeps Dock hidden")
            ScreenLifecycle.outputAvailable = false
            ScreenLifecycle.activeScreen = ({ name: "test", width: 1920, height: 1080 })
        }
    }
    Timer {
        interval: 950; running: true
        onTriggered: {
            check(!ConfigService.dockVisible, "Unavailable output keeps Dock hidden")
            ScreenLifecycle.outputAvailable = true
        }
    }
    Timer {
        interval: 1050; running: true
        onTriggered: {
            check(ConfigService.dockVisible && ConfigService.shows === 2,
                "Dock returns when the output is ready")
            check(ConfigService.creations === test.loadedCreations,
                "Output churn must preserve the existing Dock")
            ConfigService.visibilityMode = test.savedMode === "always" ? "smart" : "always"
        }
    }
    Timer {
        interval: 1150; running: true
        onTriggered: {
            check(ConfigService.creations === test.loadedCreations && ConfigService.shows === 2,
                "Runtime mode switches must not recreate or remap the Dock")
            if (!test.failed) console.log("DOCK_STARTUP_PASS")
            Qt.quit()
        }
    }
}
