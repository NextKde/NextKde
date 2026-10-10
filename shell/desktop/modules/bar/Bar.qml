import Quickshell
import Quickshell.Io
import qs.desktop.modules.bar
import qs.desktop.modules.common

// Hide the layer-shell window while ScreenLifecycle settles the output list
// around sleep/resume, then bind it to the newly elected output.
Scope {
    id: root

    property bool enabled: true

    // Bridge system tray attention signals into desktop notifications.
    TrayNotificationBridge {}

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    // The global shortcut layer runs `qs ipc call control-center toggle`
    // (registered as a KDE Command Shortcut); the panel lives in BarWindow,
    // so this scope only forwards the intent through the shared service.
    IpcHandler {
        target: "control-center"
        function toggle(): void { ControlCenterService.toggleRequested() }
    }

    BarWindow {
        screen: root.targetScreen
        visible: root.enabled && ScreenLifecycle.outputAvailable
            && root.targetScreen !== null
        barEnabled: root.enabled
    }
}
