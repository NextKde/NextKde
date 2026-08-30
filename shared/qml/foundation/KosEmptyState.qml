import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string symbol: "◇"
    property string title: ""
    property string description: ""
    property string actionText: ""
    property bool actionEnabled: true

    signal actionTriggered()

    implicitWidth: 420
    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: Math.min(root.width, 420)
        spacing: 10

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.symbol
            color: AppTheme.withAlpha(AppTheme.accent, 0.86)
            font.pixelSize: 48
            Accessible.name: root.title
        }

        Label {
            Layout.fillWidth: true
            text: root.title
            color: AppTheme.text
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 21
            font.weight: Font.DemiBold
        }

        Label {
            Layout.fillWidth: true
            text: root.description
            color: AppTheme.mutedText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.22
            visible: text.length > 0
        }

        Button {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            text: root.actionText
            enabled: root.actionEnabled
            visible: text.length > 0
            onClicked: root.actionTriggered()
        }
    }
}
