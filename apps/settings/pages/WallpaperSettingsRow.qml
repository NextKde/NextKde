import QtQuick
import Kos.Demo as Demo

// Compatibility adapter: all label, spacing and trailing-slot geometry is canonical.
Demo.SettingsItem {
    id: row
    property var colors
    property alias label: row.title
    property bool actionable: false
    signal activated
    height: implicitHeight
    property Item activationArea: MouseArea {
        parent: row
        anchors.fill: parent
        enabled: row.actionable
        cursorShape: Qt.PointingHandCursor
        onClicked: row.activated()
    }
    Text {
        visible: row.actionable
        text: "›"
        color: row.colors ? row.colors.secondaryText : row.titleColor
        font.pixelSize: 18
    }
}
