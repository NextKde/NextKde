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

    function setBluetoothEnabled(enabled) {
        const desired = !!enabled
        if (!bluetoothAvailable || bluetoothChangeInProgress || desired === bluetoothPowered)
            return false
        bluetoothChangeInProgress = true
        PlatformClient.request("bluetooth.power", { enabled: desired }, function(response) {
            bluetoothChangeInProgress = false
            if (response?.ok)
                bluetoothPowered = desired
            refresh()
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
