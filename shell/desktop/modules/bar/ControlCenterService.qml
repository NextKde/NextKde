pragma Singleton

import QtQuick
import Quickshell
import qs.desktop.modules.platform

// Shared Control Centre state. The resident platform service owns PipeWire,
// BlueZ, brightness, session, screenshot and theme integration.
QtObject {
    id: service

    property bool audioAvailable: false
    property int volumePercent: 0
    property bool audioMuted: false
    property bool volumeChangeInProgress: false
    property bool brightnessAvailable: false
    property int brightnessPercent: 0
    property bool brightnessChangeInProgress: false
    property string brightnessBacklightName: ""
    property bool bluetoothAvailable: false
    property bool bluetoothPowered: false
    property bool bluetoothChangeInProgress: false
    property var bluetoothDevices: []
    property bool bluetoothDevicesRefreshInProgress: false
    property bool bluetoothDeviceChangeInProgress: false
    property string bluetoothChangingAddress: ""
    property bool doNotDisturbEnabled: false
    property ListModel notificationHistory: ListModel {}
    property int notificationHistoryMax: 50
    property var historyGroups: []
    property int historyRevision: 0
    property bool screenshotInProgress: false
    property bool sessionActionInProgress: false
    property alias logoutInProgress: service.sessionActionInProgress
    property string lastSessionError: ""
    property string currentUserName: Quickshell.env("USER") || "用户"
    property bool canSuspend: true
    property bool canHibernate: false
    property bool themeChangeInProgress: false
    signal toggleRequested()

    function rebuildHistoryGroups() {
        const groups = []
        const groupIndex = ({})
        for (let i = 0; i < notificationHistory.count; ++i) {
            const row = notificationHistory.get(i)
            const key = row.appName || "其他"
            let index = groupIndex[key]
            if (index === undefined) {
                index = groups.length
                groupIndex[key] = index
                groups.push({ appName: key, appIcon: row.appIcon, items: [] })
            }
            groups[index].items.push({ notifId: row.notifId, summary: row.summary,
                body: row.body, timestamp: row.timestamp })
        }
        historyGroups = groups
        historyRevision++
    }

    function removeHistoryById(notifId) {
        for (let i = 0; i < notificationHistory.count; ++i) {
            if (notificationHistory.get(i).notifId === notifId) {
                notificationHistory.remove(i)
                return
            }
        }
    }

    property Connections _historyConnections: Connections {
        target: service.notificationHistory
        function onRowsInserted() { service.rebuildHistoryGroups() }
        function onRowsRemoved() { service.rebuildHistoryGroups() }
        function onRowsMoved() { service.rebuildHistoryGroups() }
        function onModelReset() { service.rebuildHistoryGroups() }
    }

    function refresh() {
        PlatformClient.request("audio.get", {}, function(response) {
            if (response?.ok) {
                const value = response.result || ({})
                audioAvailable = !!value.available
                volumePercent = Number(value.percent || 0)
                audioMuted = !!value.muted
            } else {
                audioAvailable = false
            }
        })
        PlatformClient.request("bluetooth.list", {}, function(response) {
            if (response?.ok) {
                const value = response.result || ({})
                bluetoothAvailable = !!value.available
                // setBluetoothEnabled() owns bluetoothPowered while a toggle
                // is in flight (it polls bluetooth.list itself until the
                // adapter actually confirms the desired state); applying a
                // periodic refresh's read here too could still catch BlueZ
                // mid-transition and flip the disc back and forth.
                if (!bluetoothChangeInProgress)
                    bluetoothPowered = !!value.powered
                bluetoothDevices = Array.isArray(value.devices) ? value.devices : []
            } else {
                bluetoothAvailable = false
            }
        })
        PlatformClient.request("display.brightness.get", {}, function(response) {
            if (response?.ok) {
                const value = response.result || ({})
                brightnessAvailable = !!value.available
                brightnessPercent = Number(value.percent || 0)
                brightnessBacklightName = value.device || ""
            } else {
                brightnessAvailable = false
                brightnessBacklightName = ""
            }
        })
    }

    function setVolume(percent) {
        const value = Math.round(Math.max(0, Math.min(100, Number(percent) || 0)))
        if (!audioAvailable || volumeChangeInProgress)
            return false
        volumeChangeInProgress = true
        PlatformClient.request("audio.set-volume", { percent: value }, function(response) {
            volumeChangeInProgress = false
            if (response?.ok)
                volumePercent = value
            refresh()
        })
        return true
    }

    function setMuted(muted) {
        const desired = !!muted
        if (!audioAvailable || volumeChangeInProgress || desired === audioMuted)
            return false
        volumeChangeInProgress = true
        PlatformClient.request("audio.set-mute", { muted: desired }, function(response) {
            volumeChangeInProgress = false
            if (response?.ok)
                audioMuted = desired
            refresh()
        })
        return true
    }

    function setBrightness(percent) {
        const value = Math.round(Math.max(0, Math.min(100, Number(percent) || 0)))
        if (!brightnessAvailable || brightnessChangeInProgress)
            return false
        brightnessChangeInProgress = true
        PlatformClient.request("display.brightness.set", { percent: value }, function(response) {
            brightnessChangeInProgress = false
            if (response?.ok)
                brightnessPercent = value
            refresh()
        })
        return true
    }

    // bluetoothctl's own "power on/off succeeded" is not proof BlueZ has
    // actually settled: it is a separate process invocation from the one
    // that later re-reads Powered, and can return before the adapter's
    // property has propagated. Rather than guess a timeout, keep
    // bluetoothChangeInProgress set (toggle disabled, busy arc showing) and
    // re-poll bluetooth.list until it actually reports the desired state,
    // then apply it and release the toggle. A capped retry count is only a
    // safety net against a genuinely stuck adapter, not the normal path.
    property int _bluetoothPollAttempt: 0
    property bool _bluetoothPollDesired: false
    readonly property int _bluetoothPollMaxAttempts: 15
    property Timer _bluetoothPollTimer: Timer {
        interval: 200
        repeat: false
        onTriggered: service._pollBluetoothPower()
    }

    function _pollBluetoothPower() {
        PlatformClient.request("bluetooth.list", {}, function(response) {
            const value = response?.result || ({})
            const observedPowered = !!value.powered
            // The attempt cap must terminate the loop even if bluetooth.list
            // itself keeps failing, not only once it reports the desired
            // state — otherwise a failing request retries forever.
            const settled = service._bluetoothPollAttempt >= service._bluetoothPollMaxAttempts
                || (response?.ok && observedPowered === service._bluetoothPollDesired)
            if (!settled) {
                service._bluetoothPollAttempt++
                service._bluetoothPollTimer.restart()
                return
            }
            if (response?.ok) {
                bluetoothAvailable = !!value.available
                bluetoothPowered = observedPowered
                bluetoothDevices = Array.isArray(value.devices) ? value.devices : bluetoothDevices
            } else {
                bluetoothAvailable = false
            }
            bluetoothChangeInProgress = false
        })
    }

    function setBluetoothEnabled(enabled) {
        const desired = !!enabled
        if (!bluetoothAvailable || bluetoothChangeInProgress || desired === bluetoothPowered)
            return false
        bluetoothChangeInProgress = true
        PlatformClient.request("bluetooth.power", { enabled: desired }, function(response) {
            if (!response?.ok) {
                bluetoothChangeInProgress = false
                refresh()
                return
            }
            _bluetoothPollDesired = desired
            _bluetoothPollAttempt = 0
            _pollBluetoothPower()
        })
        return true
    }

    function refreshBluetoothDevices() {
        if (bluetoothDevicesRefreshInProgress)
            return
        bluetoothDevicesRefreshInProgress = true
        PlatformClient.request("bluetooth.list", {}, function(response) {
            bluetoothDevicesRefreshInProgress = false
            if (response?.ok)
                bluetoothDevices = response.result?.devices || []
        })
    }

    function setBluetoothDeviceConnected(device, connected) {
        if (!device?.address || bluetoothDeviceChangeInProgress)
            return false
        bluetoothDeviceChangeInProgress = true
        bluetoothChangingAddress = device.address
        PlatformClient.request(connected ? "bluetooth.connect" : "bluetooth.disconnect",
            { address: device.address }, function() {
            bluetoothDeviceChangeInProgress = false
            bluetoothChangingAddress = ""
            refreshBluetoothDevices()
        })
        return true
    }

    function captureInteractiveScreenshot() {
        if (screenshotInProgress)
            return false
        screenshotInProgress = true
        PlatformClient.request("screenshot.capture", {}, function(response) {
            screenshotInProgress = false
            if (!response?.ok)
                lastSessionError = response?.error?.message || "截图失败"
        })
        return true
    }

    function _sessionAction(operation, errorMessage) {
        if (sessionActionInProgress)
            return false
        sessionActionInProgress = true
        lastSessionError = ""
        PlatformClient.request(operation, {}, function(response) {
            sessionActionInProgress = false
            if (!response?.ok)
                lastSessionError = errorMessage
        })
        return true
    }
    function lockSession() { return _sessionAction("session.lock", "锁屏失败") }
    function suspendSystem() { return _sessionAction("session.suspend", "睡眠操作失败") }
    function hibernateSystem() { return _sessionAction("session.hibernate", "休眠操作失败") }
    function rebootSystem() { return _sessionAction("session.reboot", "重启操作失败") }
    function powerOffSystem() { return _sessionAction("session.poweroff", "关机操作失败") }
    function switchUser() { return _sessionAction("session.switch-user", "切换用户失败") }
    function logoutCurrentSession() { return _sessionAction("session.logout", "注销失败") }

    function toggleDarkMode() {
        if (themeChangeInProgress)
            return false
        themeChangeInProgress = true
        PlatformClient.request("theme.toggle", {}, function(response) {
            themeChangeInProgress = false
            if (!response?.ok)
                lastSessionError = response?.error?.message || "主题切换失败"
        })
        return true
    }

    function toggleDoNotDisturb() {
        doNotDisturbEnabled = !doNotDisturbEnabled
        return doNotDisturbEnabled
    }

    property Timer refreshTimer: Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: service.refresh()
    }
    property Connections platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected)
                service.refresh()
        }
    }
    Component.onCompleted: refresh()
}
