import Quickshell
import Quickshell.Io
import QtQuick
import qs.desktop.modules.common

// Independent module root. Its lazy window follows the shared real-output
// lifecycle without importing back into qs.desktop.modules.dock.
Scope {
    id: root

    // Load only the persisted presentation overrides at shell startup. This
    // instantiates a small service and one short-lived read process; it does
    // not create the launcher's window, GridView, or icon textures.
    function initializePresentationOverrides() {
        return AppLauncherConfigService.appOverrides
    }

    Component.onCompleted: {
        root.initializePresentationOverrides()
        console.log("[AppLauncher] module instantiated"
            + " targetScreen=" + !!targetScreen)
    }

    property bool open: AppLauncherService.open
    // The launcher owns a sizeable GridView, icon texture set, and glass
    // rendering chain. Keeping its window merely invisible still retains all
    // of those resources. Instantiate it when opened and release it shortly
    // after close, once the compositor has processed the visibility change.
    property bool windowLoaded: root.open
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    onOpenChanged: {
        console.log("[AppLauncher] root open=" + open)
        if (open) {
            windowUnloadTimer.stop()
            windowLoaded = true
        } else {
            windowUnloadTimer.restart()
        }
    }
    onTargetScreenChanged: console.log("[AppLauncher] target screen changed="
        + !!targetScreen)

    IpcHandler {
        target: "applauncher"
        function show(): void { AppLauncherService.show() }
        function hide(): void { AppLauncherService.hide() }
        function toggle(): void { AppLauncherService.toggle() }
    }

    Timer {
        id: windowUnloadTimer
        interval: 180
        repeat: false
        onTriggered: {
            if (!root.open)
                root.windowLoaded = false
        }
    }

    Loader {
        id: launcherWindowLoader
        // Keep an already-open launcher instantiated while outputs disappear.
        // Only its mapped state is suppressed; destroying the Loader here
        // would reintroduce the suspend-time QQuickItem cleanup path.
        active: root.windowLoaded && root.targetScreen !== null
        sourceComponent: Component {
            AppLauncherWindow {
                screen: root.targetScreen
                open: root.open && ScreenLifecycle.outputAvailable
            }
        }
    }
}
