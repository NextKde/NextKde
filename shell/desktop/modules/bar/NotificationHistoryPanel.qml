import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.notifications
import "../../../Kos/Ui"

// Independent session notification history.
AnimatedPopupWindow {
    id: panel

    property bool historyEmptyReady: true
    // ListView removal signals arrive during polish. Hide the empty state
    // before deleting data, then reveal after those exits have settled.
    function prepareHistoryRemoval() {
        historyEmptyReady = false
        emptySettlement.restart()
    }
    Timer {
        id: emptySettlement
        interval: 300
        onTriggered: panel.historyEmptyReady = true
    }
    property int historyExitCount: 0
    property var historyClearDelays: ({})
    property bool manageApplications: false
    function beginHistoryExit() { historyExitCount++ }
    function endHistoryExit() { historyExitCount = Math.max(0, historyExitCount - 1) }
    function historyGroupVisible(item) {
        return historyList.visible && panel.visible
            && item.y + item.height > historyList.contentY
            && item.y < historyList.contentY + historyList.height
    }
    function historyExitDelay(source) { return historyClearDelays[source] || 0 }
    function clearHistory() {
        const delays = ({})
        let visibleIndex = 0
        for (let i = 0; i < historyList.count; ++i) {
            const item = historyList.itemAtIndex(i)
            if (item && historyGroupVisible(item))
                delays[item.sourceKey] = Math.min(120, visibleIndex++ * 30)
        }
        historyClearDelays = delays
        // Delete the clicked snapshot now. Animation completion never mutates
        // the service, so an arrival/replacement during an exit survives.
        prepareHistoryRemoval()
        NotificationHistoryService.removeKeys(NotificationHistoryService.allKeys())
        AppNotificationService.clearAll()
    }
    property Item anchorItem: null
    property bool dockHosted: false
    property string dockEdge: "bottom"
    implicitWidth: 340
    implicitHeight: 390
    color: "transparent"
    grabFocus: interactive
    motionOrigin: !dockHosted ? Item.Top
        : dockEdge === "left" ? Item.Left
        : dockEdge === "right" ? Item.Right : Item.Bottom
    anchor {
        item: panel.anchorItem
        edges: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        gravity: !panel.dockHosted ? Edges.Bottom
            : panel.dockEdge === "left" ? Edges.Right
            : panel.dockEdge === "right" ? Edges.Left : Edges.Top
        margins.top: panel.dockHosted
            && panel.dockEdge === "bottom" ? -8 : 0
        margins.bottom: panel.dockHosted ? 0 : -8
        margins.left: panel.dockHosted
            && panel.dockEdge === "right" ? -8 : 0
        margins.right: panel.dockHosted
            && panel.dockEdge === "left" ? -8 : 0
    }

    readonly property var targetScreen: ScreenLifecycle.activeScreen

    // The surface owns both its outline and compositor blur region.
    readonly property int blurRadius: 19
    onRequestedOpenChanged: {
        if (requestedOpen && dockHosted)
            DockModelService.openDockPopup(panel)
    }
    onVisibleChanged: {
        if (!visible)
            DockModelService.releaseDockPopup(panel)
    }
    Component.onDestruction: DockModelService.releaseDockPopup(panel)
    BackgroundEffect.blurRegion: (panel.visible && panel.revealProgress > 0
        && (AppearanceConfigService.effectiveBarBlur > 0.005
            || AppearanceConfigService.effectiveBarLiquid > 0.005))
        ? panelSurface.blurRegion : null

    function toggle(item) {
        anchorItem = item
        if (requestedOpen) close()
        else show()
    }
    function close() { hide() }

    // If the display server ever closes the popup behind our back, fold the
    // open state too.
    onClosed: {
        if (panel.requestedOpen)
            panel.close()
    }

    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable)
                panel.close()
        }
    }

    // ── Outside-press and focus-loss dismissal ───────────────────────
    // An AnimatedPopupWindow anchored to the layer-shell Bar cannot take a Wayland
    // popup grab, so an explicit full-screen transparent catcher covers presses
    // on the desktop or the Bar itself when the network list is open.
    PanelWindow {
        id: dismissalCatcher
        screen: panel.targetScreen
        visible: ScreenLifecycle.outputAvailable && panel.targetScreen !== null
            && panel.requestedOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notification-history-backdrop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.ArrowCursor
            onPressed: panel.close()
        }
    }

    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            if (panel.requestedOpen)
                panel.close()
        }
    }

    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() {
            if (ContextMenuCoordinator.activeMenu
                    && panel.requestedOpen)
                panel.close()
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: panel.requestedOpen
        onActivated: panel.close()
    }

    LiquidGlassPanel {
        id: panelSurface
        anchors.fill: parent
        radius: panel.blurRadius
        cornerExponent: AppearanceTokens.shape.cornerExponent
        baseColor: ThemeService.backgroundColor
        surfaceOpacity: 1.0
        ambientPrimary: WallpaperColorSource.primary
        ambientSecondary: WallpaperColorSource.secondary
        ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
        material: "thick"
        adaptiveDarkScrim: true
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: "transparent"
    }
    GlassText {
        id: title
        anchors { left: parent.left; top: parent.top; margins: 16 }
        text: panel.manageApplications ? "应用通知" : "通知历史"
        color: panelSurface.foregroundColor
        font { pixelSize: 15; weight: Font.Bold }
    }
    GlassText {
        anchors { right: parent.right; verticalCenter: title.verticalCenter; rightMargin: 16 }
        visible: !panel.manageApplications
        text: "清空"
        color: panelSurface.foregroundColor
        opacity: NotificationHistoryService.count > 0 ? 0.8 : 0.3
        font.pixelSize: 12
        MouseArea {
            anchors.fill: parent; anchors.margins: -6
            enabled: NotificationHistoryService.count > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                panel.clearHistory()
            }
        }
    }
    Item {
        id: notificationSettings
        anchors { left: parent.left; right: parent.right; top: title.bottom; margins: 16; topMargin: 12 }
        height: 68
        GlassText {
            text: "勿扰模式"
            color: panelSurface.foregroundColor
            font.pixelSize: 13
            anchors { left: parent.left; top: parent.top; topMargin: 4 }
        }
        Rectangle {
            width: 36; height: 22; radius: 11
            anchors { right: parent.right; top: parent.top }
            color: ControlCenterService.doNotDisturbEnabled ? "#0a84ff" : Qt.rgba(0.5, 0.5, 0.5, 0.35)
            Rectangle {
                width: 18; height: 18; radius: 9; y: 2
                x: ControlCenterService.doNotDisturbEnabled ? 16 : 2
                color: "white"
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -5
                cursorShape: Qt.PointingHandCursor
                onClicked: ControlCenterService.toggleDoNotDisturb()
            }
        }
        GlassText {
            anchors { left: parent.left; top: parent.top; topMargin: 27 }
            text: "静音横幅，通知仍保留在历史中"
            color: panelSurface.foregroundColor
            opacity: 0.55
            font.pixelSize: 10
        }
        GlassText {
            anchors { left: parent.left; bottom: parent.bottom }
            text: panel.manageApplications ? "‹ 返回通知历史" : "管理应用通知 ›"
            color: panelSurface.foregroundColor
            opacity: 0.85
            font.pixelSize: 11
            MouseArea {
                anchors.fill: parent; anchors.margins: -5
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.manageApplications = !panel.manageApplications
            }
        }
    }
    ListView {
        id: applicationsList
        visible: panel.manageApplications
        anchors { left: parent.left; right: parent.right; top: notificationSettings.bottom; bottom: parent.bottom; margins: 16; topMargin: 12 }
        clip: true
        spacing: 6
        model: NotificationPolicyService.sources
        delegate: Item {
            required property var modelData
            width: applicationsList.width
            height: 54
            NotificationSourceIcon {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: 24; height: 24
                appIcon: modelData.appIcon
                desktopEntry: modelData.desktopEntry
                ink: panelSurface.foregroundColor
            }
            Column {
                anchors { left: parent.left; right: allowToggle.left; verticalCenter: parent.verticalCenter; leftMargin: 32; rightMargin: 8 }
                spacing: 3
                GlassText {
                    width: parent.width
                    text: modelData.appName
                    textFormat: Text.PlainText
                    color: panelSurface.foregroundColor
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }
                GlassText {
                    width: parent.width
                    text: modelData.desktopEntry || "按应用名称识别"
                    textFormat: Text.PlainText
                    color: panelSurface.foregroundColor
                    opacity: 0.5
                    elide: Text.ElideRight
                    font.pixelSize: 9
                }
            }
            Rectangle {
                id: allowToggle
                readonly property bool blocked: NotificationPolicyService.isKeyBlocked(modelData.key)
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 58; height: 26; radius: 13
                color: blocked ? Qt.rgba(0.5, 0.5, 0.5, 0.2) : Qt.rgba(0.04, 0.52, 1, 0.55)
                GlassText {
                    anchors.centerIn: parent
                    text: allowToggle.blocked ? "已屏蔽" : "允许"
                    color: panelSurface.foregroundColor
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: NotificationPolicyService.ready
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationPolicyService.setBlocked(modelData.key, !allowToggle.blocked)
                }
            }
        }
        KosKineticScroll { flickable: applicationsList }
        GlassText {
            anchors.centerIn: parent
            visible: applicationsList.count === 0
            text: "收到通知后可在这里管理应用"
            color: panelSurface.foregroundColor
            opacity: 0.5
            font.pixelSize: 12
        }
    }
    GlassText {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
        visible: panel.manageApplications && NotificationPolicyService.saveError.length > 0
        text: NotificationPolicyService.saveError
        color: "#ff6b61"
        font.pixelSize: 10
    }
    ListView {
        id: historyList
        visible: !panel.manageApplications
        anchors { left: parent.left; right: parent.right; top: notificationSettings.bottom; bottom: parent.bottom; margins: 16; topMargin: 12 }
        clip: true
        model: NotificationHistoryService.groups
        spacing: 12
        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 } }
        displaced: Transition { NumberAnimation { property: "y"; duration: 200; easing.type: Easing.OutCubic } }
        delegate: NotificationHistoryGroup {
            width: historyList.width
            ink: panelSurface.foregroundColor
            dark: ThemeService.isDark
            coordinator: panel
            onToggleRequested: (source, expanded) => NotificationHistoryService.setExpanded(source, expanded)
            onRemoveRequested: key => {
                panel.historyClearDelays = ({})
                panel.prepareHistoryRemoval()
                NotificationHistoryService.remove(key)
            }
            onClearRequested: keys => {
                panel.historyClearDelays = ({})
                panel.prepareHistoryRemoval()
                NotificationHistoryService.removeKeys(keys)
            }
        }
        KosKineticScroll { flickable: historyList }
    }
    GlassText {
        anchors.centerIn: historyList
        visible: opacity > 0
        text: "暂无通知"
        color: panelSurface.foregroundColor
        opacity: !panel.manageApplications && NotificationHistoryService.count === 0
            && panel.historyEmptyReady && panel.historyExitCount === 0 ? 0.5 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        font.pixelSize: 14
    }
}
