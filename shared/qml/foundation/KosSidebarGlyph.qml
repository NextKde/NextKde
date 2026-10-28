import QtQuick

// Shared by Weather's sidebar toggle and compact Demo toolbar controls.
Item {
    id: root
    property color glyphColor: AppTheme.text
    property color paneColor: AppTheme.mutedText

    Rectangle {
        anchors.centerIn: parent
        width: 16; height: 13; radius: 3.5
        color: "transparent"
        border.width: 1.25
        border.color: root.glyphColor
        Rectangle {
            x: 3.5; y: 2.5; width: 2.5; height: 8; radius: 1.25
            color: root.paneColor
        }
    }
}
