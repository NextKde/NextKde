import QtQuick
import QtQuick.Controls

KosToolButton {
    id: root
    property var targetWindow: null
    property color glyphColor: AppTheme.text
    property color glyphPaneColor: root.targetWindow && root.targetWindow.sidebarExpanded ? AppTheme.accent : AppTheme.mutedText
    objectName: "sidebarToggle"
    implicitWidth: AppTheme.controlHeight
    implicitHeight: AppTheme.controlHeight
    Accessible.name: targetWindow && targetWindow.sidebarExpanded ? qsTr("Collapse sidebar") : qsTr("Expand sidebar")
    ToolTip.visible: hovered
    ToolTip.text: Accessible.name
    ToolTip.delay: 500
    onClicked: if (targetWindow) targetWindow.sidebarExpanded = !targetWindow.sidebarExpanded
    contentItem: KosSidebarGlyph {
        glyphColor: root.glyphColor
        paneColor: root.glyphPaneColor
    }
}
