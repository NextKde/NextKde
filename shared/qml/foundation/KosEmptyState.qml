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

    // Optional palette overrides; defaults keep the original light-panel
    // look (music/todo). Weather passes sky-text colors for legibility on
    // the full-window sky background (empty-state title measured near-black
    // (35,38,41) on sky (57,126,195) — unreadable).
    property color symbolColor: AppTheme.withAlpha(AppTheme.accent, 0.86)
    property color titleColor: AppTheme.text
    property color descriptionColor: AppTheme.mutedText

    signal actionTriggered()

    implicitWidth: 320
    implicitHeight: content.implicitHeight

    ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: Math.min(root.width, 320)
        spacing: 12

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: root.symbol
            color: root.symbolColor
            font.pixelSize: 40
            Accessible.name: root.title
        }

        Label {
            Layout.fillWidth: true
            text: root.title
            color: root.titleColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Label {
            Layout.fillWidth: true
            text: root.description
            color: root.descriptionColor
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 14
            lineHeight: 1.22
            visible: text.length > 0
        }

        KosButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            text: root.actionText
            enabled: root.actionEnabled
            visible: text.length > 0
            onClicked: root.actionTriggered()
        }
    }
}
