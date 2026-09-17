import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.desktop
import qs.desktop.modules.common
import qs.desktop.modules.dock

Item {
    id: root

    property bool dockHosted: false
    property bool verticalDock: false
    property real iconSize: 18
    rotation: verticalDock ? -90 : 0
    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        anchors.centerIn: parent
        width: 24
        height: 24
        radius: width / 2
        color: pointer.containsMouse
            ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(0, 0, 0, 0.10))
            : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
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
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: DesktopAppLauncher.openSettings()
    }
}
