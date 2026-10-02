import "../../shared/qml/controls" as SharedControls
import QtQuick
import QtQuick.Controls

// Compact value in a settings row. The choices live in a small rounded sheet
// instead of a platform-styled ComboBox, keeping every settings page aligned.
Item {
    id: control
    property var colors
    property var model: []
    property string textRole: ""
    property int currentIndex: 0
    property bool openingUp: false
    property string placeholder: ""
    signal activated(int index)
    implicitWidth: 150
    implicitHeight: 40

    function labelAt(index) {
        if (index < 0 || index >= model.length) return ""
        const value = model[index]
        return textRole ? String(value[textRole] || "") : String(value)
    }

    function openMenu() {
        const overlay = Overlay.overlay
        if (!overlay) return
        const origin = control.mapToItem(overlay, 0, 0)
        control.openingUp = origin.y + control.height + menu.implicitHeight + 5
            > overlay.height - 12
        menu.x = Math.max(12, Math.min(overlay.width - menu.width - 12,
            origin.x + control.width - menu.width)) - origin.x
        menu.y = control.openingUp ? -menu.implicitHeight - 5 : control.height + 5
        menu.open()
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 9
        spacing: 9
        Text {
            text: control.placeholder || control.labelAt(control.currentIndex)
            color: control.colors.secondaryText
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        SharedControls.VectorIcon {
            name: "chevron"
            color: control.colors.secondaryText
            size: 17
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -2
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: control.openMenu()
    }

    Popup {
        id: menu
        width: Math.max(188, control.width + 34)
        implicitHeight: Math.min(360, choices.implicitHeight + 12)
        padding: 6
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 180; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 100 }
        }
        background: Rectangle {
            radius: 19
            // 不透明底。之前是"模糊捕获 backdrop + 半透明着色"两层玻璃,底下
            // 透什么全看运气;现在底色定死,玻璃感全部交给描边。
            color: control.colors.dark ? "#262b31" : "#f6f8fb"
            border.width: 1
            // Edge glow - soft rim light(LiquidNavBar 的边光做法)
            border.color: Qt.rgba(1, 1, 1, control.colors.dark ? 0.30 : 0.72)
            // Inner rim light:再往里 1px 一道更细的亮线(LiquidGlassButton 层1)
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 18
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, control.colors.dark ? 0.16 : 0.45)
            }
            // Chromatic aberration:红/青描边各偏 0.5px(LiquidGlassButton 层2)
            Rectangle {
                width: parent.width
                height: parent.height
                x: -0.5
                radius: 19
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 0.25, 0.25, control.colors.dark ? 0.14 : 0.20)
            }
            Rectangle {
                width: parent.width
                height: parent.height
                x: 0.5
                radius: 19
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0.25, 0.85, 1, control.colors.dark ? 0.14 : 0.20)
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 17
                gradient: Gradient {
                    GradientStop { position: 0; color: control.colors.dark ? "#20ffffff" : "#aaffffff" }
                    GradientStop { position: 0.4; color: "#00ffffff" }
                    GradientStop { position: 1; color: control.colors.dark ? "#10000000" : "#08000000" }
                }
            }
        }
        contentItem: Flickable {
            clip: true
            contentHeight: choices.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Column {
            id: choices
            Repeater {
                model: control.model
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: menu.width - 12
                    height: 39
                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: parent.index === control.currentIndex
                            ? Qt.rgba(control.colors.accent.r, control.colors.accent.g,
                                      control.colors.accent.b, control.colors.dark ? 0.22 : 0.13)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: control.labelAt(parent.index)
                        color: parent.index === control.currentIndex
                            ? control.colors.accent : control.colors.primaryText
                        font.pixelSize: 13
                    }
                    SharedControls.VectorIcon {
                        anchors.right: parent.right
                        anchors.rightMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.index === control.currentIndex
                        name: "check"
                        color: control.colors.accent
                        size: 13
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            control.activated(parent.index)
                            menu.close()
                        }
                    }
                }
            }
            }
        }
    }
}
