pragma Singleton
import QtQuick
import Quickshell
import "../platform"
import "ScreenSelection.mjs" as ScreenSelection

// Keeps output-bound windows away from Qt's synthetic placeholder screen.
// During suspend/resume the compositor may briefly publish no real outputs;
// retain the last real screen reference and hide surfaces until a valid output
// is available again instead of rebinding every PanelWindow to the placeholder.
QtObject {
    id: service

    property var activeScreen: null
    property bool outputAvailable: false
    // 缓存 KDE 屏幕输出配置（包含真实 Priority 与连接状态）
    property var outputConfiguration: []
    property bool requestPending: false

    // Every real output, refreshed on the same schedule as activeScreen.
    // Surfaces that live on one chosen screen read activeScreen; surfaces that
    // have to cover the whole session -- the lock is the only one -- build one
    // window per entry here, so they inherit the settle delay below instead of
    // racing Qt's placeholder screen with their own screen list.
    property var usableScreens: []

    // 请求 PlatformServer 获取 KDE KScreen 的真实显示输出优先级
    function updateOutputConfiguration() {
        if (requestPending || !PlatformClient.socket.connected)
            return
        requestPending = true
        PlatformClient.request("display.outputs.get", {}, function(reply) {
            requestPending = false
            if (reply.ok && reply.result && reply.result.available)
                outputConfiguration = reply.result.outputs || []
            if (!settleTimer.running)
                refresh()
        })
    }

    function _isUsableScreen(screen) {
        return screen !== null
            && screen !== undefined
            && String(screen.name || "").length > 0
            && Number(screen.width) > 0
            && Number(screen.height) > 0
    }

    function _usableScreens() {
        const result = []
        const screens = Quickshell.screens
        for (let index = 0; index < screens.length; ++index) {
            if (_isUsableScreen(screens[index]))
                result.push(screens[index])
        }
        return result
    }

    function refresh() {
        const screens = _usableScreens()
        // 通过 ScreenSelection 智能选择主屏幕（优先 Priority 1，保底居中外接屏）
        const nextScreen = ScreenSelection.selectScreen(screens, outputConfiguration, activeScreen)

        usableScreens = screens
        outputAvailable = nextScreen !== null
        if (nextScreen !== null && nextScreen !== activeScreen) {
            console.log("[ScreenLifecycle] 选定主屏幕:", nextScreen.name, "几何坐标:", nextScreen.x, nextScreen.y, nextScreen.width, nextScreen.height)
            activeScreen = nextScreen
        }
    }

    function refreshAndSettle() {
        // Hide all output-bound surfaces before Qt tears down/recreates its
        // QScreen objects, then drop the wrapper before its QObject destructor
        // can notify bindings that still reach into a QQuickWindow item tree.
        outputAvailable = false
        activeScreen = null
        usableScreens = []
        settleTimer.restart()
    }

    property Connections screenConnections: Connections {
        target: Quickshell
        function onScreensChanged() { service.refreshAndSettle() }
    }

    property Timer settleTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: {
            service.refresh()
            service.updateOutputConfiguration()
        }
    }

    property Connections platformConnections: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            service.requestPending = false
            if (connected)
                service.updateOutputConfiguration()
        }
    }

    // 针对用户在 KDE 系统设置中仅调整优先级而不插拔屏幕的情况，设置 2s 轮询检测
    property Timer outputPollTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: service.updateOutputConfiguration()
    }

    Component.onCompleted: {
        refresh()
        updateOutputConfiguration()
    }
}
