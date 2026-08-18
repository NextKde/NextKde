import QtQuick
import QtQuick.Controls

// A compact glass field for search and inline text entry. It avoids a bright
// desktop-style focus outline; focus is communicated by a lifted material and
// a thin, tinted inner edge instead.
TextField {
    id: root

    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    verticalAlignment: TextInput.AlignVCenter
    selectByMouse: true

    property color glassColor: Qt.rgba(1, 1, 1, 0.10)
    property color focusColor: "#0a84ff"
    property color textColor: "#f5f5f7"
    property color mutedTextColor: "#98989d"

    color: textColor
    placeholderTextColor: mutedTextColor

    HoverHandler {
        id: hover
        cursorShape: Qt.IBeamCursor
    }

    background: Rectangle {
        id: fieldSurface
        radius: height * 0.38
        color: root.activeFocus
            ? Qt.rgba(root.glassColor.r, root.glassColor.g, root.glassColor.b,
                      Math.min(1.0, root.glassColor.a + 0.08))
            : (hover.hovered
               ? Qt.rgba(root.glassColor.r, root.glassColor.g, root.glassColor.b,
                         Math.min(1.0, root.glassColor.a + 0.035))
               : root.glassColor)
        border.width: 1
        border.color: root.activeFocus
            ? Qt.rgba(root.focusColor.r, root.focusColor.g, root.focusColor.b, 0.42)
            : Qt.rgba(1, 1, 1, hover.hovered ? 0.13 : 0.08)

        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.activeFocus ? 0.16 : 0.10) }
                GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.045) }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: root.activeFocus ? 1 : 0
            border.color: Qt.rgba(root.focusColor.r, root.focusColor.g, root.focusColor.b, 0.20)
            Behavior on border.width { NumberAnimation { duration: 130 } }
        }
    }
}
