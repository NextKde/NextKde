import QtQuick
import QtQuick.Layouts

// Ordinary settings section. Only supplied controls may use liquid material.
Item {
    id: root
    default property alias content: items.data
    property string title: ""
    property color backgroundColor: AppTheme.dark ? "#242426" : "#f7f7f7"
    property color titleColor: AppTheme.text
    property real cornerRadius: 12
    property real titleSpacing: 6
    property real verticalPadding: 4
    property alias titleFont: heading.font
    readonly property alias background: panel
    readonly property alias contentItem: items

    implicitWidth: 420
    implicitHeight: (heading.visible ? heading.implicitHeight + titleSpacing : 0)
        + items.implicitHeight + verticalPadding * 2
    Layout.fillWidth: true
    Layout.minimumWidth: 0

    data: [Text {
        id: heading
        objectName: root.objectName + "Title"
        x: 16
        width: Math.max(0, parent.width - 32)
        visible: root.title.length > 0
        text: root.title
        color: root.titleColor
        font.pixelSize: 15
        font.weight: Font.Bold
        wrapMode: Text.Wrap
        Accessible.role: Accessible.Heading
    },

    Rectangle {
        id: panel
        x: 0
        y: heading.visible ? heading.implicitHeight + root.titleSpacing : 0
        width: parent.width
        height: items.implicitHeight + root.verticalPadding * 2
        radius: root.cornerRadius
        color: root.backgroundColor
        border.width: 0
    },

    ColumnLayout {
        id: items
        x: panel.x
        y: panel.y + root.verticalPadding
        width: panel.width
        spacing: 0
    }]
}
