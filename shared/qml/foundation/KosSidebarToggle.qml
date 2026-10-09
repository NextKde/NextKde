import QtQuick
import QtQuick.Controls

KosToolButton {
    id: root
    property var targetWindow: null
    objectName: "sidebarToggle"
    implicitWidth: AppTheme.controlHeight
    implicitHeight: AppTheme.controlHeight
    Accessible.name: targetWindow && targetWindow.sidebarExpanded ? qsTr("Collapse sidebar") : qsTr("Expand sidebar")
    ToolTip.visible: hovered
    ToolTip.text: Accessible.name
    ToolTip.delay: 500
    onClicked: if (targetWindow) targetWindow.sidebarExpanded = !targetWindow.sidebarExpanded
    contentItem: Item {
        Rectangle {
            anchors.centerIn: parent
            width: 18; height: 15; radius: 4
            color: "transparent"; border.width: 1.4; border.color: AppTheme.text
            Rectangle {
                x: 4; y: 3; width: 3; height: 9; radius: 1.5
                color: root.targetWindow && root.targetWindow.sidebarExpanded ? AppTheme.accent : AppTheme.mutedText
            }
        }
    }
}
