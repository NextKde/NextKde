import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

PanelWindow {
    id: window
    readonly property var geometry: SwitcherService.screenGeometry
    readonly property var targetScreen: Quickshell.screens.find(output => output.x === geometry.x && output.y === geometry.y)
        || ScreenLifecycle.activeScreen
    screen: targetScreen
    visible: content.mapped && targetScreen !== null
    color: "transparent"
    implicitWidth: Math.min(content.desiredWidth, (screen?.width || 1280) * 0.88)
    implicitHeight: content.implicitHeight + 16
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "kos-switcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}
    BackgroundEffect.blurRegion: content.blurRegion

    SwitcherContent {
        id: content
        anchors.centerIn: parent
        width: parent.width
        height: implicitHeight
        windows: SwitcherService.windows
        selectedHandle: SwitcherService.selectedHandle
        requestedOpen: SwitcherService.open
    }
}
