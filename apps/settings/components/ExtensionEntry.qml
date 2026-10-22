import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../shared/qml/controls" as LiquidControls

// A compact catalogue row, shared by downloadable apps and optional services.
Rectangle {
    id: entry
    required property var colors
    required property string title
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
    signal activated()
    signal secondaryActivated()

    implicitHeight: content.implicitHeight + 28
    radius: 14
    color: colors.card

    data: [ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 64
            spacing: 10
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 48
                Layout.minimumWidth: 48
                Layout.maximumWidth: 48
                Layout.preferredHeight: 48
                radius: 11
                color: entry.iconSource.toString().length ? "transparent" : entry.iconColor
                Image {
                    anchors.fill: parent
                    source: entry.iconSource
                    sourceSize: Qt.size(144, 144)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                LiquidControls.VectorIcon {
                    visible: !entry.iconSource.toString().length
                    anchors.centerIn: parent
                    size: 28
                    name: entry.iconName
                    color: "white"
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        text: entry.title
                        color: entry.colors.primaryText
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        visible: entry.category.length > 0
                        implicitWidth: categoryLabel.implicitWidth + 10
                        implicitHeight: categoryLabel.implicitHeight + 4
                        radius: 4
                        color: Qt.rgba(0.5, 0.5, 0.5, 0.10)
                        Text {
                            id: categoryLabel
                            anchors.centerIn: parent
                            text: entry.category
                            color: entry.colors.secondaryText
                            font.pixelSize: 9
                            font.weight: Font.Medium
                        }
                    }
                }
                Text {
                    id: descriptionLabel
                    Layout.fillWidth: true
                    Layout.minimumHeight: descriptionMetrics.height * 2
                    FontMetrics { id: descriptionMetrics; font: descriptionLabel.font }
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: entry.description
                    color: entry.colors.secondaryText
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 10
                spacing: 2
                Button {
                    id: action
                    objectName: entry.actionObjectName
                    text: entry.actionText
                    enabled: entry.actionEnabled
                    implicitWidth: Math.max(60, implicitContentWidth + 22)
                    implicitHeight: 28
                    focusPolicy: Qt.StrongFocus
                    Accessible.name: entry.title + ": " + text
                    onClicked: entry.activated()
                    contentItem: Text {
                        text: action.text
                        color: entry.colors.accent
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: action.enabled ? 1 : 0.5
                    }
                    background: Rectangle {
                        radius: height / 2
                        color: Qt.rgba(entry.colors.accent.r, entry.colors.accent.g, entry.colors.accent.b,
                            action.down ? 0.2 : action.hovered ? 0.14 : 0.09)
                        border.width: action.visualFocus ? 2 : 0
                        border.color: entry.colors.accent
                    }
                }
                Button {
                    objectName: entry.actionObjectName + "Secondary"
                    Layout.alignment: Qt.AlignHCenter
                    visible: entry.secondaryText.length > 0
                    enabled: entry.secondaryEnabled
                    text: entry.secondaryText
                    implicitHeight: 24
                    flat: true
                    onClicked: entry.secondaryActivated()
                    contentItem: Text {
                        text: entry.secondaryText
                        color: entry.colors.secondaryText
                        font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: parent.enabled ? 1 : 0.5
                    }
                    background: Rectangle { color: "transparent" }
                }
            }
        }
        ColumnLayout {
            id: detailsColumn
            visible: implicitHeight > 0
            Layout.fillWidth: true
            spacing: 8
        }
    }]
}
