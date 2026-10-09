import QtQuick

Rectangle {
    id: control
    property string label: ""
    property string iconText: ""
    property bool emphasized: false
    property bool selected: false
    property bool compact: false
    property color foregroundColor: AppTheme.textPrimary
    signal clicked

    implicitWidth: compact ? 36 : Math.max(76, textItem.implicitWidth + (iconText === "" ? 28 : 48))
    implicitHeight: compact ? 36 : 38
    radius: compact ? implicitHeight / 2 : 10
    color: tapHandler.pressed ? AppTheme.actionPressed : hoverHandler.hovered ? AppTheme.actionHover : selected ? AppTheme.actionHover : AppTheme.actionSurface
    border.width: 1
    border.color: AppTheme.actionBorder
    scale: tapHandler.pressed ? 0.97 : 1

    Behavior on color { ColorAnimation { duration: AppTheme.duration(110) } }
    Behavior on scale { NumberAnimation { duration: AppTheme.duration(100); easing.type: Easing.OutCubic } }

    HoverHandler {
        id: hoverHandler
    }
    MouseArea {
        anchors.fill: parent
        id: tapHandler
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }

    Row {
        anchors.centerIn: parent
        spacing: 8
        IconGlyph {
            visible: control.iconText !== ""
            kind: control.iconText === "▶" ? "play" : control.iconText
            glyphColor: control.foregroundColor
            width: control.compact ? 18 : 16
            height: width
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: textItem
            visible: control.label !== ""
            text: control.label
            color: control.foregroundColor
            font.pixelSize: 14
            font.weight: control.emphasized ? Font.DemiBold : Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
