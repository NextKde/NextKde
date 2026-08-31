import Quickshell
import qs.desktop.modules.common

// A desktop surface is intentionally independent from application windows.
// ScreenLifecycle temporarily hides it while KWin has no real output.
Scope {
    id: root

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    DeskCenterWindow {
        screen: root.targetScreen
        visible: ScreenLifecycle.outputAvailable && root.targetScreen !== null
    }
}
