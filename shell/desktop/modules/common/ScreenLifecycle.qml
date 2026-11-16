pragma Singleton
import QtQuick
import Quickshell
import "../platform"
import "ScreenSelection.mjs" as ScreenSelection

// Keeps output-bound windows away from Qt's synthetic placeholder screen.
// During suspend/resume the compositor may briefly publish no real outputs;
// clear screen references and hide surfaces until the output list settles,
// then bind windows to a usable output again.
QtObject {
    id: service

    property var activeScreen: null
    property bool outputAvailable: false
    // 缓存 KDE 屏幕输出配置（包含真实 Priority 与连接状态）
    property var outputConfiguration: []
    property bool requestPending: false
    // DPMS off makes the compositor publish no outputs. Video actions must
    // not treat that transient state as a hotplug and remap surfaces while
    // the session is locked; doing so can wake the display repeatedly.
    property bool sessionLocked: false
    property bool lockCheckPending: false
    property int _lockEventGeneration: 0
    property var _lockCheckCallbacks: []

    // Every real output, refreshed on the same schedule as activeScreen.
    // Surfaces that live on one chosen screen read activeScreen; surfaces that
    // have to cover the whole session -- the lock is the only one -- build one
    // window per entry here, so they inherit the settle delay below instead of
    // racing Qt's placeholder screen with their own screen list.
    property var usableScreens: []

    function pauseForLock() {
        // Keep the last known screen binding. Clearing it while the compositor
        // has no outputs makes every screen-bound surface remap and can wake
        // the display. Only stop the probes and retry ladder.
        settleTimer.stop()
        retryTimer.stop()
        _settleRetryRemaining = 0
    }

    function resumeAfterLock() {
        refreshAndSettle()
    }

    // The platform forwards ScreenSaver.ActiveChanged as session.lock-changed.
    // Use that event as the authoritative gate; GetActive is only a startup /
    // reconnect fallback before the event has arrived.
    function setSessionLocked(value) {
        const next = !!value
        if (next === sessionLocked)
            return
        sessionLocked = next
        if (next)
            pauseForLock()
        else
            resumeAfterLock()
    }

    function updateSessionVisibility(callback, allowWhileLocked) {
        // Never let a poll overtake a lock event. Once locked, only the
        // ScreenSaver signal (or an explicit reconnect resync) may release the gate.
        if (sessionLocked && !allowWhileLocked)
            return
        if (!PlatformClient.connected) {
            if (!sessionLocked && callback)
                callback()
            return
        }
        if (callback) {
            const queued = _lockCheckCallbacks.slice()
            queued.push(callback)
            _lockCheckCallbacks = queued
        }
        if (lockCheckPending)
            return
        const requestGeneration = _lockEventGeneration
        lockCheckPending = true
        PlatformClient.request("session.visibility", {}, function(reply) {
            lockCheckPending = false
            const queued = _lockCheckCallbacks
            _lockCheckCallbacks = []
            if (requestGeneration === _lockEventGeneration
                    && reply.ok && reply.result && reply.result.locked !== undefined) {
                setSessionLocked(reply.result.locked)
            }
            if (!sessionLocked) {
                for (let i = 0; i < queued.length; ++i)
                    queued[i]()
            }
        })
    }

    // 请求 PlatformServer 获取 KDE KScreen 的真实显示输出优先级
    function updateOutputConfiguration() {
        if (requestPending || sessionLocked || !PlatformClient.connected)
            return
        requestPending = true
        PlatformClient.request("display.outputs.get", {}, function(reply) {
            requestPending = false
            if (sessionLocked)
                return
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
        // Polls and older request callbacks must respect the same settle
        // delay as screensChanged, rather than remapping surfaces early.
        if (sessionLocked || settleTimer.running)
            return
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
        retryTimer.stop()
        _settleRetryRemaining = 0
        if (sessionLocked)
            return
        outputAvailable = false
        activeScreen = null
        usableScreens = []
        settleTimer.restart()
    }

    property Connections screenConnections: Connections {
        target: Quickshell
        function onScreensChanged() {
            if (service.sessionLocked) {
                service.pauseForLock()
                return
            }
            service.refreshAndSettle()
        }
    }

    property int _settleRetryRemaining: 0

    property Timer settleTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: {
            if (service.sessionLocked)
                return
            service.refresh()
            service.updateOutputConfiguration()
            // 如果唤醒瞬间恰好命中 Qt Wayland 占位屏导致无可用输出，启动逃生重试梯队
            if (!service.outputAvailable && !service.sessionLocked) {
                service._settleRetryRemaining = 5
                retryTimer.restart()
            }
        }
    }

    property Timer retryTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: {
            if (service.sessionLocked)
                return
            service.refresh()
            service.updateOutputConfiguration()
            if (!service.outputAvailable && !service.sessionLocked && service._settleRetryRemaining > 0) {
                service._settleRetryRemaining--
                retryTimer.restart()
            }
        }
    }

    property Connections platformEvents: Connections {
        target: PlatformClient
        function onEventReceived(eventName, payload) {
            if (eventName === "session.lock-changed" && payload && payload.locked !== undefined) {
                service._lockEventGeneration++
                service.setSessionLocked(payload.locked)
            }
        }
    }

    property Connections platformConnections: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            service.requestPending = false
            if (connected) {
                service.updateSessionVisibility(function() {
                    if (!service.sessionLocked)
                        service.updateOutputConfiguration()
                }, true)
            }
        }
    }

    // 针对用户在 KDE 系统设置中仅调整优先级而不插拔屏幕的情况，设置 2s 轮询检测；
    // 并在输出异常丢失（!outputAvailable）时自动触发 refresh() 自愈逃生。
    property Timer outputPollTimer: Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (service.sessionLocked)
                return
            service.updateSessionVisibility(function() {
                if (service.sessionLocked)
                    return
                service.updateOutputConfiguration()
                if (!service.outputAvailable)
                    service.refresh()
            })
        }
    }

    Component.onCompleted: {
        updateSessionVisibility(function() {
            if (service.sessionLocked)
                return
            service.refresh()
            service.updateOutputConfiguration()
        })
    }
}
