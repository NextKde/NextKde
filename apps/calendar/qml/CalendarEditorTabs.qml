pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Demo as Demo

Item {
    id: root
    CalendarStyle { id: design }
    property real leftInset: 16
    property real rightInset: 16
    property int currentIndex: 0
    property bool switchingEnabled: true
    signal switchRequested(int index)
    // 28px selector, 8px above and 19px below (15px extra breathing room).
    implicitHeight: 55
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 8
        anchors.bottomMargin: 19
        anchors.leftMargin: root.leftInset
        anchors.rightMargin: root.rightInset
        radius: height/2
        color: Demo.AppTheme.dark ? "#303032" : "#DDDDDF"
        RowLayout {
            anchors.fill: parent
            spacing: 0
            Repeater {
                model: [qsTr("Event"), qsTr("Reminder")]
                delegate: Button {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    enabled: root.switchingEnabled || index === root.currentIndex
                    text: modelData
                    contentItem: Label {
                        text: modelData
                        color: index === root.currentIndex ? "#FFFFFF" : Demo.AppTheme.text
                        opacity: parent.enabled ? 1 : 0.45
                        font.pixelSize: 13
                        font.weight: index === root.currentIndex ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: height/2
                        color: index === root.currentIndex ? design.workspaceActive : "transparent"
                    }
                    onClicked: if (index !== root.currentIndex) root.switchRequested(index)
                }
            }
        }
    }
}
