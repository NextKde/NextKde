import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Basic
import "../../../shared/qml/controls" as LiquidControls
import "../../../shared/qml/i18n"

// App Store list row: artwork, identity and one primary capsule action.
Item {
    id: entry
    required property var colors
    property string title: ""
    property string description: ""
    property string category: ""
    property string iconName: "grid"
    property url iconSource: ""
    property real iconInset: 0
    property color iconColor: "#5b7cfa"
    property string actionText: ""
    property bool actionEnabled: true
    // A brief inventory read can lock input without changing availability.
    property bool actionAvailable: actionEnabled
    property string actionObjectName: ""
    signal detailsRequested
    signal activated
    implicitWidth: 300
    implicitHeight: body.implicitHeight

    data: [MouseArea {
        anchors.fill: parent
        onClicked: mouse => {
            const iconPoint = artwork.mapFromItem(entry, mouse.x, mouse.y);
            const actionPoint = action.mapFromItem(entry, mouse.x, mouse.y);
            // Leave artwork and action buttons inert for detail requests,
            // including when the action button is disabled.
            if (artwork.contains(iconPoint) || action.contains(actionPoint)) return;
            entry.detailsRequested();
        }
    }, ColumnLayout {
        id: body
        x: 0
        y: 0
        width: entry.width
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Item {
                id: artwork
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.rightMargin: 12
                Image {
                    anchors.centerIn: parent
                    width: parent.width / (1 - 2 * entry.iconInset)
                    height: width
                    source: entry.iconSource
                    sourceSize: Qt.size(132, 132)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                Rectangle {
                    visible: !entry.iconSource.toString().length
                    anchors.fill: parent
                    radius: 10
                    color: entry.iconColor
                    LiquidControls.VectorIcon {
                        anchors.centerIn: parent
                        size: 24
                        name: entry.iconName
                        color: "white"
                    }
                }
            }
            Basic.Button {
                id: identity
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 60
                padding: 0
                hoverEnabled: true
                objectName: entry.actionObjectName + "Details"
                Accessible.name: entry.title + ": " + I18n.tr("Details")
                onClicked: entry.detailsRequested()
                background: Rectangle {
                    color: "transparent"
                    radius: 10
                    border.width: identity.visualFocus ? 2 : 0
                    border.color: "#0085ff"
                }
                contentItem: ColumnLayout {
                    spacing: 2
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: entry.title
                        color: entry.colors.primaryText
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: entry.description
                        color: entry.colors.secondaryText
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
            Basic.Button {
                id: action
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 12
                Layout.preferredWidth: Math.max(50, actionLabel.implicitWidth + 20)
                implicitHeight: 24
                padding: 0
                objectName: entry.actionObjectName
                text: entry.actionText
                enabled: entry.actionEnabled
                hoverEnabled: true
                Accessible.name: entry.title + ": " + text
                onClicked: entry.activated()
                contentItem: Text {
                    textFormat: Text.PlainText
                    id: actionLabel
                    text: action.text
                    color: entry.actionAvailable ? "#0085ff" : entry.colors.secondaryText
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: height / 2
                    // Sampled from the supplied App Store reference.
                    color: action.down ? "#d4e3f5" : "#e6edf7"
                    border.width: action.visualFocus ? 2 : 0
                    border.color: "#0085ff"
                }
            }
        }
    }]
}
