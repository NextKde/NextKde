import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Basic
import Kos.Demo as Demo
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
    default property alias details: detailsColumn.data
    property string secondaryText: ""
    property bool secondaryEnabled: true
    property bool detailsExpanded: false
    property bool attentionRequired: false
    readonly property bool showingDetails: detailsExpanded || attentionRequired
    signal activated
    signal secondaryActivated
    implicitWidth: 300
    implicitHeight: body.implicitHeight + 16

    data: [ColumnLayout {
        id: body
        x: 0
        y: 8
        width: entry.width
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Basic.Button {
                id: identity
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                implicitHeight: 44
                padding: 0
                hoverEnabled: true
                objectName: entry.actionObjectName + "Details"
                Accessible.name: entry.title + ": " + I18n.tr("Details")
                onClicked: entry.detailsExpanded = !entry.detailsExpanded
                background: Rectangle {
                    color: "transparent"
                    radius: 10
                    border.width: identity.visualFocus ? 2 : 0
                    border.color: "#0085ff"
                }
                contentItem: RowLayout {
                    spacing: 12
                    Item {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
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
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: entry.title
                            color: entry.colors.primaryText
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: entry.description
                            color: entry.colors.secondaryText
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
            Basic.Button {
                id: action
                Layout.alignment: Qt.AlignVCenter
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
        ColumnLayout {
            Layout.fillWidth: true
            visible: entry.showingDetails
            spacing: 10
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Qt.rgba(entry.colors.secondaryText.r, entry.colors.secondaryText.g,
                    entry.colors.secondaryText.b, 0.15)
            }
            ColumnLayout {
                id: detailsColumn
                Layout.fillWidth: true
                spacing: 8
            }
            Demo.LiquidActionButton {
                objectName: entry.actionObjectName + "Secondary"
                visible: entry.secondaryText.length > 0
                enabled: entry.secondaryEnabled
                text: entry.secondaryText
                materialForm: true
                secondary: true
                implicitHeight: 24
                cornerRadius: 6
                Accessible.name: entry.title + ": " + text
                onClicked: entry.secondaryActivated()
            }
        }
    }]
}
