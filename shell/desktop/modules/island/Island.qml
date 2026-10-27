import Quickshell
import QtQuick
import qs.desktop.modules.common

// Island — module root for the top-edge dynamic island.
//
// Ported from the NookX Dynamic Island. The original is an AppDelegate that
// creates one NSPanel per screen; this root follows the same lifecycle as
// the launcher: the window is created once a usable output exists and is
// then kept allocated, because tearing a window down while an output is
// briefly unavailable (suspend/resume) is the crash path the launcher
// comment already documents.
//
// The window instance itself lives in IslandWindow.qml.
Scope {
    id: root

    // Load persisted settings at shell startup, before the window appears.
    // The window is created once a usable output exists and is then kept
    // allocated, because tearing a window down while an output is briefly
    // unavailable (suspend/resume) is the crash path the launcher comment
    // already documents.
    readonly property var targetScreen: IslandService.triggerScreen
        && !IslandService.triggerScreen.isPlaceholder
        ? IslandService.triggerScreen : ScreenLifecycle.activeScreen

    property bool windowCreated: false

    onTargetScreenChanged: {
        if (targetScreen)
            windowCreated = true
    }

    Component.onCompleted: {
        console.log("[Island] module instantiated")
        if (targetScreen)
            windowCreated = true
        // "always" opens the island without any pointer gesture, so the mode
        // has to be applied here as well as being guarded in collapse().
        applyExpandMode()
    }

    // Switching to "always" from Settings must open the island immediately;
    // leaving it must not collapse one the user had already opened by hand.
    Connections {
        target: IslandConfigService
        function onExpandModeChanged() { applyExpandMode() }
    }

    function applyExpandMode() {
        if (!IslandConfigService.enabled)
            return
        if (IslandConfigService.expandMode === "always") {
            IslandService.expand(null)
            return
        }
        // Leaving "always" must not leave the island stuck open. In hover
        // mode it follows the pointer, and `expand()` returns early while
        // the island is already expanded — so without this the island would
        // stay open, ignore the pointer and only react to a click.
        if (IslandService.expanded && !IslandService.hovered)
            IslandService.collapse()
    }

    Loader {
        id: islandWindowLoader
        active: root.windowCreated
        sourceComponent: Component {
            IslandWindow {
                screen: root.targetScreen
                outputAvailable: ScreenLifecycle.outputAvailable
            }
        }
    }
}
