import QtQuick
import QtQuick.Layouts

Item {
    id: row
    property var colors
    property string label: ""
    property bool separator: false
    property bool actionable: false
    default property alias controls: trailing.data
    signal activated()
    implicitHeight: 54
    height: implicitHeight
    Rectangle {
        anchors.fill: parent
        color: row.colors.primaryText
        opacity: hit.containsMouse ? 0.035 : 0
        radius: 18
    }
    MouseArea {
        id: hit
        anchors.fill: parent
        enabled: row.actionable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        Text {
            Layout.fillWidth: true
            text: row.label
            color: row.colors.primaryText
            font.pixelSize: 14
            elide: Text.ElideRight
        }
        Row {
            id: trailing
            spacing: 8
        }
        Text {
            visible: row.actionable
            text: "›"
            color: row.colors.secondaryText
            font.pixelSize: 24
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        height: 1
        color: row.colors.separator
        visible: row.separator
    }
}
