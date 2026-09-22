import Quickshell
import QtQuick
import qs.desktop.modules.common

// A desktop surface is intentionally independent from application windows.
// ScreenLifecycle temporarily hides it while KWin has no real output.
Scope {
    id: root

    // Desktop files and context menus exist independently on every usable
    // output. DeskCenterWindow itself keeps widgets restricted to the elected
    // primary screen.
    Variants {
        model: ScreenLifecycle.usableScreens

        delegate: Component {
            DeskCenterWindow {
                required property var modelData

                screen: modelData
                visible: ScreenLifecycle.outputAvailable
            }
        }
    }
}
