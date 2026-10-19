import QtQuick

// The rounded label buttons in the history column's edit bar — "Edit" while the
// column is at rest, "Clear All" (or "Delete (n)") once it is being edited.
// The shape is the same either way; only the fill and the label colour differ,
// so both are properties rather than two components.
Item {
    id: root

    property string label: ""
    property color fill: "transparent"
    property color labelColor: "#FFFFFF"
    property real sidePadding: 12

    // Measured off the reference: both pills are 153x103 device px against a
    // 102px disc, i.e. as tall as the disc beside them, and fully rounded. The
    // 103 is 11.2% of the sheet's width, which is 30px of our column.
    implicitWidth: labelText.implicitWidth + root.sidePadding * 2
    implicitHeight: 30

    signal clicked()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.fill
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: root.label
        color: root.labelColor
        font.pixelSize: 12
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
