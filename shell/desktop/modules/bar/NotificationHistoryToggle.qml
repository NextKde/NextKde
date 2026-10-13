import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.notifications
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// Dedicated entry for session notification history.
Item {
    id: root
    signal panelToggleRequested()
    property bool panelOpen: false
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0
    implicitWidth: 24
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight

    SelectionHighlight {
        objectName: "notification-history-toggle-highlight"
        anchors.fill: parent
        cornerRadius: 8
        enabled: AppearanceTokens.surface.selectionHighlightStyle === "glass"
        hovered: hoverArea.containsMouse || hoverArea.activeFocus
        pressed: hoverArea.pressed
        selected: root.panelOpen
        dark: AppearanceTokens.isDarkTheme
    }
    BundledIcon {
        // Same readability edge the bar text carries (Text.Outline).
        outlined: AppearanceTokens.isDarkTheme
        outlineColor: Qt.rgba(0, 0, 0, 0.40)
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        name: "bell"
        color: IconAppearanceService.mode === "tint"
            ? IconAppearanceService.styledSymbolicColor()
            : ThemeService.foregroundColor
        opacity: IconAppearanceService.mode !== "color"
            ? IconAppearanceService.opacity * (root.panelOpen ? 1.0 : 0.88)
            : (root.panelOpen ? 1.0 : 0.88)
        scale: hoverArea.pressed ? 0.90 : hoverArea.containsMouse ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: AppearanceTokens.motion.fastDuration } }
    }
    Rectangle {
        anchors { right: parent.right; top: parent.top; margins: 2 }
        width: 6; height: 6; radius: 3
        visible: NotificationHistoryService.count > 0
        color: "#0a84ff"
        border.width: 1
        border.color: ThemeService.foregroundColor
    }
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.panelToggleRequested()
    }
    StatusTooltip {
        anchorItem: root
        shown: hoverArea.containsMouse && !root.panelOpen
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
        primaryText: "通知历史"
        minimumWidth: 92
    }
}
