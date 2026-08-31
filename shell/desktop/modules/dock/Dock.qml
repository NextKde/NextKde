import Quickshell
import QtQuick
import qs.desktop.modules.common

// Keep one Dock window alive across output churn. ScreenLifecycle hides it
// while no real output exists and restores it without binding to Qt's
// synthetic placeholder screen.
Scope {
    id: root

    property Component leadingAccessory: null
    property Component trailingAccessory: null
    property bool clockInInfoCarousel: false

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    // Keep position-specific components so each newly selected edge commits
    // its final layer-shell anchors on the window's first frame. The Loader
    // remains instantiated while outputs disappear, so suspend/resume does not
    // tear down the active Dock window.
    Component {
        id: bottomDock
        DockWindow {
            position: "bottom"
            screen: root.targetScreen
            visible: ScreenLifecycle.outputAvailable
                && root.targetScreen !== null
            leadingAccessory: root.leadingAccessory
            trailingAccessory: root.trailingAccessory
            clockInInfoCarousel: root.clockInInfoCarousel
        }
    }

    Component {
        id: leftDock
        DockWindow {
            position: "left"
            screen: root.targetScreen
            visible: ScreenLifecycle.outputAvailable
                && root.targetScreen !== null
            leadingAccessory: root.leadingAccessory
            trailingAccessory: root.trailingAccessory
            clockInInfoCarousel: root.clockInInfoCarousel
        }
    }

    Component {
        id: rightDock
        DockWindow {
            position: "right"
            screen: root.targetScreen
            visible: ScreenLifecycle.outputAvailable
                && root.targetScreen !== null
            leadingAccessory: root.leadingAccessory
            trailingAccessory: root.trailingAccessory
            clockInInfoCarousel: root.clockInInfoCarousel
        }
    }

    Loader {
        sourceComponent: ConfigService.position === "left"
            ? leftDock
            : (ConfigService.position === "right" ? rightDock : bottomDock)
    }
}
