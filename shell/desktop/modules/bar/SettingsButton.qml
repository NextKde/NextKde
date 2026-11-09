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

    // Shell status glyphs use the same opaque ink as temperature/rate labels.
    // Dock and launcher artwork styling must not tint or dim these controls.
    BundledIcon {
        // Same readability edge the bar text carries (Text.Outline).
        outlined: AppearanceTokens.isDarkTheme && !AppearanceTokens.bar.macStyle
        outlineColor: Qt.rgba(0, 0, 0, 0.40)
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        name: "status-settings"
        color: ThemeService.barInk
        scale: pointer.pressed ? 0.90 : pointer.containsMouse ? 1.06 : 1
        Behavior on scale { NumberAnimation { duration: AppearanceTokens.motion.fastDuration; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: DesktopAppLauncher.openSettings()
    }
}
