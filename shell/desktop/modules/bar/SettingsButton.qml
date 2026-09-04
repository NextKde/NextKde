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

    DockStatusSvgIcon {
        anchors.centerIn: parent
        width: 16
        height: 16
        source: Qt.resolvedUrl("../../assets/status-settings.svg")
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: DesktopAppLauncher.openSettings()
    }
}
