import QtQuick
import Quickshell
import qs.desktop
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"

// The leftmost bar logo uses the same popup and session actions as the rest
// of the shell. Unsupported Apple-menu counterparts remain visibly disabled.
Item {
    id: root

    property real size: 18
    property color color: ThemeService.barInk
    readonly property bool menuOpen: menu.visible
    implicitWidth: 30
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight

    function installedId(candidates) {
        for (const id of candidates) {
            if (AppPresentationService.entryFor(id))
                return id
        }
        return ""
    }

    function openMenu() {
        const aboutId = installedId(["org.kde.kinfocenter.desktop", "kinfocenter.desktop"])
        const storeId = installedId(["org.kde.discover.desktop"])
        const sessionReady = !ControlCenterService.sessionActionInProgress
        const missing = " " + I18n.tr("(Not installed)")
        const unsupported = " " + I18n.tr("(Not supported yet)")
        menu.setItems([
            { label: I18n.tr("About This Computer") + (aboutId ? "" : missing),
              cmd: "launch", desktopId: aboutId, enabled: aboutId.length > 0 },
            { separator: true },
            { label: I18n.tr("System Settings…"), cmd: "settings" },
            { label: I18n.tr("App Store…") + (storeId ? "" : missing),
              cmd: "launch", desktopId: storeId, enabled: storeId.length > 0 },
            { separator: true },
            { label: I18n.tr("Recent Items") + unsupported, enabled: false },
            { separator: true },
            { label: I18n.tr("Force Quit…") + unsupported, enabled: false },
            { separator: true },
            { label: I18n.tr("Sleep"), cmd: "suspend",
              enabled: sessionReady && ControlCenterService.canSuspend },
            { label: I18n.tr("Restart…"), cmd: "reboot", enabled: sessionReady },
            { label: I18n.tr("Shut Down…"), cmd: "poweroff", enabled: sessionReady },
            { separator: true },
            { label: I18n.tr("Lock Screen"), cmd: "lock", enabled: sessionReady },
            { label: I18n.tr("Log Out %1…").replace("%1", ControlCenterService.currentUserName),
              cmd: "logout", enabled: sessionReady }
        ])
        menu.show()
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: (pointer.containsMouse || root.menuOpen)
            ? Qt.rgba(root.color.r, root.color.g, root.color.b, 0.16) : "transparent"
    }

    BundledIcon {
        anchors.centerIn: parent
        name: "nextkde"
        size: root.size
        color: root.color
        outlined: !AppearanceTokens.bar.macStyle
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (menu.visible)
                menu.hide()
            else
                root.openMenu()
        }
    }

    ContextMenu {
        id: menu
        anchorItem: root
        implicitWidth: 300
        scrimLevel: "readable"
        blurOverrideEnabled: true
        blurStrength: Math.min(1, AppearanceConfigService.effectiveDockBlur + 0.2)
        position: "bottom"
        centerBelowAnchor: false
        centerBelowOffset: root.height
            + Math.max(0, (root.parent?.height ?? root.height) - root.height) / 2 + 4
        customAnchorEdges: Edges.Top | Edges.Left
        customGravity: Edges.Bottom | Edges.Right
        customMarginsTop: 0
        globalDismissGraceMs: 250
        onAction: function(cmd, item) {
            if (cmd === "settings")
                DesktopAppLauncher.openSettings()
            else if (cmd === "launch")
                AppActionService.launchById(item.desktopId)
            else if (cmd === "lock")
                ControlCenterService.lockSession()
            else if (cmd === "suspend")
                ControlCenterService.suspendSystem()
            else if (cmd === "reboot" || cmd === "poweroff" || cmd === "logout") {
                // Let ContextMenu finish its click dispatch before presenting
                // the existing control-center confirmation dialog.
                Qt.callLater(function() { ControlCenterService.requestSessionAction(cmd) })
            }
        }
    }
}
