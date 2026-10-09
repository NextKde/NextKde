import QtQuick
import QtQuick.Controls
import QtQuick.Window

Row {
    id: root
    required property var targetWindow
    objectName: "windowControls"
    spacing: 10
    HoverHandler { id: groupHover }
    Repeater {
        model: ["fullscreen", "minimize", "close"]
        delegate: AbstractButton {
            id: button
            required property string modelData
            objectName: "window" + modelData + "Button"
            width: 22; height: 32
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: modelData === "fullscreen"
                ? (root.targetWindow.visibility === Window.FullScreen ? qsTr("Exit full screen") : qsTr("Full screen"))
                : modelData === "minimize" ? qsTr("Minimize") : qsTr("Close")
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            ToolTip.delay: 700
            onClicked: {
                if (modelData === "fullscreen") root.targetWindow.toggleFullScreen()
                else if (modelData === "minimize") root.targetWindow.showMinimized()
                else root.targetWindow.close()
            }
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: 18; height: 18; radius: 9
                    color: button.modelData === "fullscreen" ? "#2fc866" : button.modelData === "minimize" ? "#ffbf18" : "#ff5f57"
                    border.width: button.activeFocus ? 2 : 1
                    border.color: button.activeFocus ? AppTheme.text : Qt.darker(color, 1.28)
                    scale: button.down ? .88 : button.hovered ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: AppTheme.motionFast } }
                    Item {
                        anchors.centerIn: parent; width: 9; height: 9
                        opacity: groupHover.hovered || button.activeFocus ? .72 : 0
                        Behavior on opacity { NumberAnimation { duration: AppTheme.motionFast } }
                        Rectangle {
                            anchors.centerIn: parent; width: 6; height: 6; radius: .6
                            color: "transparent"; border.width: 1.2; border.color: "black"
                            visible: button.modelData === "fullscreen"
                        }
                        Rectangle {
                            anchors.centerIn: parent; width: 7; height: 1.35; radius: height / 2
                            color: "black"; rotation: button.modelData === "close" ? 45 : 0
                            visible: button.modelData !== "fullscreen"
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
