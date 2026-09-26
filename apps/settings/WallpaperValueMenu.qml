import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// Compact value in a settings row. The choices live in a small glass sheet
// instead of a platform-styled ComboBox, keeping every settings page aligned.
Item {
    id: control
    property var colors
    property var model: []
    property string textRole: ""
    property int currentIndex: 0
    property bool openingUp: false
    property string placeholder: ""
    property Item backdropSource: null
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

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: pointer.containsMouse
            ? (control.colors.dark ? "#22ffffff" : "#14000000")
            : "transparent"
        border.color: pointer.containsMouse
            ? (control.colors.dark ? "#48ffffff" : "#23000000") : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
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
        Text {
            text: "⌄"
            color: control.colors.secondaryText
            font.pixelSize: 17
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -2
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.openMenu()
    }

    Popup {
        id: menu
        width: Math.max(188, control.width + 34)
        implicitHeight: choices.implicitHeight + 12
        padding: 6
        onOpened: {
            if (control.backdropSource && GraphicsInfo.api !== GraphicsInfo.Software) {
                const origin = menu.background.mapToItem(control.backdropSource, 0, 0)
                capturedBackground.sourceRect = Qt.rect(origin.x, origin.y, menu.width, menu.height)
                capturedBackground.scheduleUpdate()
            }
        }
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
            color: "transparent"
            border.color: control.colors.dark ? "#70ffffff" : "#baffffff"
            border.width: 1
            ShaderEffectSource {
                id: capturedBackground
                visible: false
                sourceItem: control.backdropSource
                textureSize: Qt.size(menu.width, menu.height)
                live: false
                recursive: false
            }
            MultiEffect {
                anchors.fill: parent
                source: capturedBackground
                blurEnabled: true
                blur: 0.75
                blurMax: 20
                maskEnabled: true
                maskSource: Rectangle {
                    width: menu.width
                    height: menu.height
                    radius: 19
                    color: "white"
                    visible: false
                }
                visible: control.backdropSource && GraphicsInfo.api !== GraphicsInfo.Software
            }
            Rectangle {
                anchors.fill: parent
                radius: 19
                color: control.colors.dark ? "#b9272b32" : "#dcf6f8fb"
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
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                height: 1
                color: "#65ffffff"
                opacity: 0.65
            }
        }
        contentItem: Column {
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
                            : hit.containsMouse
                                ? (control.colors.dark ? "#25ffffff" : "#16000000")
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
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.index === control.currentIndex
                        text: "✓"
                        color: control.colors.accent
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
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
