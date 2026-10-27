import QtQuick

// Shared by Weather's sidebar toggle and compact Demo toolbar controls.
Item {
    id: root
    property color glyphColor: AppTheme.text
    property color paneColor: AppTheme.mutedText

    Rectangle {
        anchors.centerIn: parent
        width: 18; height: 15; radius: 4
        color: "transparent"
        border.width: 1.4
        border.color: root.glyphColor
        Rectangle {
            x: 4; y: 3; width: 3; height: 9; radius: 1.5
            color: root.paneColor
        }
    }
}
