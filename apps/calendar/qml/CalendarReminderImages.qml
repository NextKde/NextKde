pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

GridLayout {
    id: root
    property var images: []
    property bool editable: false
    signal removeRequested(int index)
    columns: 4
    columnSpacing: 6
    rowSpacing: 6
    CalendarStyle { id: design }
    Repeater {
        model: root.images
        delegate: Rectangle {
            id: thumbnail
            required property string modelData
            required property int index
            implicitWidth: 60; implicitHeight: 60
            radius: 8
            color: design.controlFill
            Image { id: preview; anchors.fill: parent; anchors.margins: 4; source: thumbnail.modelData; sourceSize: Qt.size(120,120); fillMode: Image.PreserveAspectFit; asynchronous: true }
            Label { anchors.centerIn: parent; visible: preview.status === Image.Error; text: qsTr("Unavailable"); font.pixelSize: 10; color: design.labelSecondary }
            MouseArea { anchors.fill: parent; onClicked: Qt.openUrlExternally(thumbnail.modelData); cursorShape: Qt.PointingHandCursor }
            ToolButton {
                id: remove
                visible: root.editable
                anchors.right: parent.right; anchors.top: parent.top
                width: 20; height: 20; padding: 5
                Accessible.name: qsTr("Remove image")
                contentItem: Demo.VectorIcon { name: "close"; size: 10; color: design.labelPrimary }
                background: Rectangle { radius: 10; color: remove.hovered ? design.rowHoverFill : design.controlFill }
                onClicked: root.removeRequested(thumbnail.index)
            }
        }
    }
}
