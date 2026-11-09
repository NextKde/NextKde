import QtQuick
import QtQuick.Window
import Kos.Demo as Demo

// The popup lives in Overlay, outside settingsScene. Sample the actual content
// behind it; its ordinary menu rows never create additional glass layers.
Item {
    id: root
    readonly property var host: root.Window.window
    readonly property Item scene: host ? host.settingsScene : null
    readonly property bool liquidEnabled: host && host.liquidEnabled
    property real radius: 12
    property point sceneOrigin: Qt.point(0, 0)
    readonly property bool sampling: liquidEnabled && surface.sampling
    function updateOrigin() {
        if (scene && liquidEnabled) sceneOrigin = scene.mapToItem(root, 0, 0)
    }
    Component.onCompleted: Qt.callLater(updateOrigin)
    Connections {
        target: root.Window.window
        enabled: root.liquidEnabled && root.visible
        function onAfterAnimating() { root.updateOrigin() }
    }
    Item {
        id: sourcePosition
        x: root.sceneOrigin.x
        y: root.sceneOrigin.y
        width: root.scene ? root.scene.width : 0
        height: root.scene ? root.scene.height : 0
        visible: false
        ShaderEffectSource {
            anchors.fill: parent
            sourceItem: root.liquidEnabled ? root.scene : null
            live: root.visible
            recursive: false
        }
    }
    Demo.LiquidBackdrop {
        id: panelBackdrop
        registerAsDefault: false
        sourceItem: sourcePosition
        active: root.visible && root.liquidEnabled
        blur: 0.35
    }
    Demo.LiquidSurface {
        id: surface
        anchors.fill: parent
        visible: root.sampling
        radius: root.radius
        backdrop: root.liquidEnabled ? panelBackdrop : null
        tintStrength: 0.7
    }
    Rectangle {
        anchors.fill: parent
        visible: !root.sampling
        radius: root.radius
        color: Demo.AppTheme.dark ? "#2C2C2E" : "#F7F7F9"
    }
}
