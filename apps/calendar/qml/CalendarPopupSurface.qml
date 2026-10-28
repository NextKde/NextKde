import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Kos.Ui
import Kos.Demo as Demo

// One glass panel; ordinary menu/option rows stay outside this background.
CalendarGlassSurface {
    id: root
    readonly property var hostWindow: root.Window.window
    property Item scene: hostWindow ? hostWindow.calendarScene : null
    readonly property bool captureEnabled: visible && scene !== null
        && liquidEnabled && GraphicsInfo.api !== GraphicsInfo.Software
    property point sceneOrigin: Qt.point(0, 0)
    radius: 12
    coverage: 0.7
    fallbackColor: AppTheme.dark ? "#2C2C2E" : "#F7F7F9"
    backdrop: panelCapture

    function updateOrigin() {
        if (scene && captureEnabled) sceneOrigin = scene.mapToItem(root, 0, 0)
    }
    Component.onCompleted: Qt.callLater(updateOrigin)
    onCaptureEnabledChanged: Qt.callLater(updateOrigin)
    Connections {
        target: root.Window.window
        enabled: root.captureEnabled
        function onAfterAnimating() { root.updateOrigin() }
    }
    Item {
        id: blurredScene
        x: root.sceneOrigin.x
        y: root.sceneOrigin.y
        width: root.scene ? root.scene.width : 0
        height: root.scene ? root.scene.height : 0
        visible: false
        Loader {
            anchors.fill: parent
            active: root.captureEnabled
            sourceComponent: MultiEffect {
                source: root.scene
                blurEnabled: true
                blur: 0.35
                blurMax: 32
                autoPaddingEnabled: false
            }
        }
    }
    Demo.LiquidBackdrop {
        id: panelCapture
        registerAsDefault: false
        sourceItem: blurredScene
        active: root.captureEnabled
    }
}
