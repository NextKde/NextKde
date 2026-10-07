import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.desktop
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

Item {
    id: root

    property bool dockHosted: false
    property bool verticalDock: false
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0
    implicitWidth: 24
    implicitHeight: 24
    width: implicitWidth
    height: implicitHeight

    SelectionHighlight {
        objectName: "status-settings-selection-highlight"
        anchors.fill: parent
        cornerRadius: 8
        enabled: AppearanceTokens.surface.selectionHighlightStyle === "glass"
        hovered: pointer.containsMouse || pointer.activeFocus
        pressed: pointer.pressed
        dark: AppearanceTokens.isDarkTheme
        fillStrength: 0.85
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        visible: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
            && pointer.containsMouse
        color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)
    }

    // 外观（描边色 / 不透明度）来自 IconAppearanceService，与状态区其余
    // 图标保持一致；图案本身来自 BundledIcons，不查系统主题。
    BundledIcon {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        name: "status-settings"
        color: IconAppearanceService.mode === "tint"
            ? IconAppearanceService.styledSymbolicColor()
            : ThemeService.foregroundColor
        opacity: IconAppearanceService.mode !== "color"
            ? IconAppearanceService.opacity : 1.0
        scale: pointer.pressed ? 0.90 : pointer.containsMouse ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: AppearanceTokens.motion.fastDuration } }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: DesktopAppLauncher.openSettings()
    }
}
