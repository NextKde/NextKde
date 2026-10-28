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
    implicitHeight: 28
    activeFocusOnTab: true
    Keys.onSpacePressed: openMenu()
    Keys.onReturnPressed: openMenu()
    Accessible.role: Accessible.ComboBox
    Accessible.name: placeholder || labelAt(currentIndex)

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
        popupType: Popup.Item
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
        background: SettingsPopupSurface {}
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
                    height: 28
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
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
