import QtQuick
import QtQuick.Layouts
import Kos.Demo as Demo
import "../../../shared/qml/controls" as LiquidControls

// Catalogue identity is content; setting geometry and actions remain canonical.
Demo.SettingsGroup {
    id: entry
    required property var colors
    property string description: ""
    property string category: ""
    property string iconName: "grid"
    property url iconSource: ""
    property color iconColor: "#5b7cfa"
    property string actionText: ""
    property bool actionEnabled: true
    property string actionObjectName: ""
    default property alias details: detailsColumn.data
    property string secondaryText: ""
    property bool secondaryEnabled: true
    signal activated
    signal secondaryActivated
    backgroundColor: colors.card
    content: [
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Item {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 56
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 40
                    radius: 9
                    color: entry.iconSource.toString().length ? "transparent" : entry.iconColor
                    Image {
                        anchors.fill: parent
                        source: entry.iconSource
                        sourceSize: Qt.size(120, 120)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    LiquidControls.VectorIcon {
                        visible: !entry.iconSource.toString().length
                        anchors.centerIn: parent
                        size: 24
                        name: entry.iconName
                        color: "white"
                    }
                }
            }
            Demo.SettingsItem {
                title: entry.description
                description: entry.category
                separator: false
                minimumLabelWidth: 80
                Demo.LiquidActionButton {
                    objectName: entry.actionObjectName + "Secondary"
                    visible: entry.secondaryText.length > 0
                    enabled: entry.secondaryEnabled
                    text: entry.secondaryText
                    materialForm: true
                    implicitHeight: 24
                    cornerRadius: 6
                    onClicked: entry.secondaryActivated()
                }
                Demo.LiquidActionButton {
                    objectName: entry.actionObjectName
                    text: entry.actionText
                    enabled: entry.actionEnabled
                    materialForm: true
                    implicitHeight: 24
                    cornerRadius: 6
                    Accessible.name: entry.title + ": " + text
                    onClicked: entry.activated()
                }
            }
        },
        ColumnLayout {
            id: detailsColumn
            visible: implicitHeight > 0
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 4
        }
    ]
}
