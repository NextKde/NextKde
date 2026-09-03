import Quickshell
import Quickshell.Io
import QtQuick
import qs.desktop.modules.common

// Independent module root. Its lazy window follows the shared real-output
// lifecycle without importing back into qs.desktop.modules.dock.
Scope {
    id: root

    // Load persisted presentation overrides at shell startup. The launcher
    // window is created once a usable output exists, then remains allocated
    // while hidden to avoid Qt Quick teardown crashes during output changes.
    function initializePresentationOverrides() {
        return AppLauncherConfigService.appOverrides
    }

    Component.onCompleted: {
        root.initializePresentationOverrides()
        if (targetScreen)
            windowCreated = true
        console.log("[AppLauncher] module instantiated"
            + " targetScreen=" + !!targetScreen)
    }

    property bool open: AppLauncherService.open
    // Keep the window instance alive for the scope's lifetime. Destroying a
    // Loader containing a GridView/Repeater just after its PanelWindow becomes
    // invisible can leave a delegate temporarily detached while Qt still
    // processes a geometry update, which crashes Qt Quick 6.11 in
    // QQuickItemPrivate::addToDirtyList(). The invisible PanelWindow no longer
    // maps or accepts input, so retaining it is the safe close path.
    property bool windowCreated: false
    readonly property var targetScreen: ScreenLifecycle.activeScreen
    onOpenChanged: console.log("[AppLauncher] root open=" + open)
    onTargetScreenChanged: {
        console.log("[AppLauncher] target screen changed=" + !!targetScreen)
        // Once constructed, do not tear down the GridView while an output is
        // temporarily unavailable (for example, during suspend/resume).
        if (targetScreen)
            windowCreated = true
    }

    IpcHandler {
        target: "applauncher"
        function show(): void { AppLauncherService.show() }
        function hide(): void { AppLauncherService.hide() }
        function toggle(): void { AppLauncherService.toggle() }
    }

    Loader {
        id: launcherWindowLoader
        // Keep an already-open launcher instantiated while outputs disappear.
        // Only its mapped state is suppressed; destroying the Loader here
        // would reintroduce the suspend-time QQuickItem cleanup path.
        active: root.windowCreated
        sourceComponent: Component {
            AppLauncherWindow {
                screen: root.targetScreen
                open: root.open && ScreenLifecycle.outputAvailable
            }
        }
    }
}
