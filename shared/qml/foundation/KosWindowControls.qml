import QtQuick
import QtQuick.Controls
import QtQuick.Window

Row {
    id: root
    required property var targetWindow
    property int circleSize: 14
    property int buttonWidth: 22
    property int buttonHeight: 32
    property bool maximizeMode: false
    property bool compositorIntegration: true
    // One entry per actual action; order is layout order, not action identity.
    property var actions: ["maximize", "minimize", "close"]
    property int layoutRevision: 0
    onPositioningComplete: layoutRevision++
    readonly property var buttonLayout: {
        const revision = layoutRevision
        const result = []
        for (let i = 0; i < buttons.count; ++i) {
            const item = buttons.itemAt(i)
            if (item && item.visible)
                result.push({action: item.modelData,
                    x: item.x + (item.width-circleSize)/2,
                    y: item.y + (item.height-circleSize)/2,
                    width: circleSize, height: circleSize})
        }
        return result
    }
    readonly property bool externalDrawing: compositorActive
    readonly property bool compositorActive: compositorLoader.item ? compositorLoader.item.active : false
    readonly property bool compositorSupported: compositorLoader.item ? compositorLoader.item.supported : false
    readonly property bool hoverGlyphs: compositorLoader.item && compositorLoader.item.supported
        ? compositorLoader.item.hoverGlyphs : true
    objectName: "windowControls"
    spacing: 6
    // Keep delegates in the Row layout while takeover hides only their opacity.
    Loader {
        id: compositorLoader
        active: root.compositorIntegration
        width: 0; height: 0
        source: "KosCompositorControls.qml"
        onLoaded: item.target = root
    }
    Binding { target: compositorLoader.item; property: "buttons"; value: root.buttonLayout; when: compositorLoader.status === Loader.Ready }
    Binding { target: compositorLoader.item; property: "enabled"; value: root.compositorIntegration && (root.maximizeMode || root.actions.indexOf("maximize") < 0); when: compositorLoader.status === Loader.Ready }
    HoverHandler { id: groupHover }
    Repeater {
        id: buttons
        model: root.actions
        delegate: AbstractButton {
            id: button
            required property string modelData
            objectName: "window" + (modelData === "maximize" ? "fullscreen" : modelData) + "Button"
            width: root.buttonWidth; height: root.buttonHeight
            opacity: root.compositorActive ? 0 : 1
            enabled: !root.compositorActive
            Accessible.ignored: root.compositorActive
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Keys.onReturnPressed: button.clicked()
            Keys.onEnterPressed: button.clicked()
            Accessible.name: modelData === "maximize"
                ? (root.maximizeMode
                    ? (root.targetWindow.visibility === Window.Maximized ? qsTr("Restore") : qsTr("Maximize"))
                    : (root.targetWindow.visibility === Window.FullScreen ? qsTr("Exit full screen") : qsTr("Full screen")))
                : modelData === "minimize" ? qsTr("Minimize") : qsTr("Close")
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            ToolTip.delay: 700
            onClicked: {
                if (modelData === "maximize") {
                    if (root.maximizeMode) {
                        if (root.targetWindow.visibility === Window.Maximized) root.targetWindow.showNormal()
                        else root.targetWindow.showMaximized()
                    } else root.targetWindow.toggleFullScreen()
                }
                else if (modelData === "minimize") root.targetWindow.showMinimized()
                else if (modelData === "close") root.targetWindow.close()
            }
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: root.circleSize; height: root.circleSize; radius: width / 2
                    color: button.modelData === "maximize" ? "#2fc866" : button.modelData === "minimize" ? "#ffbf18" : "#ff5f57"
                    border.width: button.activeFocus ? 2 : 1
                    border.color: button.activeFocus ? AppTheme.text : Qt.darker(color, 1.28)
                    scale: button.down ? .88 : button.hovered ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: AppTheme.motionFast } }
                    Item {
                        anchors.centerIn: parent; width: 9; height: 9
                        opacity: !root.hoverGlyphs || groupHover.hovered || button.activeFocus ? .72 : 0
                        Behavior on opacity { NumberAnimation { duration: AppTheme.motionFast } }
                        Rectangle {
                            anchors.centerIn: parent; width: 6; height: 6; radius: .6
                            color: "transparent"; border.width: 1.2; border.color: "black"
                            visible: button.modelData === "maximize"
                        }
                        Rectangle {
                            anchors.centerIn: parent; width: 7; height: 1.35; radius: height / 2
                            color: "black"; rotation: button.modelData === "close" ? 45 : 0
                            visible: button.modelData !== "maximize"
                        }
                        Rectangle {
                            anchors.centerIn: parent; width: 7; height: 1.35; radius: height / 2
                            color: "black"; rotation: -45; visible: button.modelData === "close"
                        }
                    }
                }
            }
        }
    }
}
