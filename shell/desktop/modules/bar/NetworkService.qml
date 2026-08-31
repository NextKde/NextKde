pragma Singleton

import QtQuick
import qs.desktop.modules.platform

// Network presentation model. NetworkManager is an implementation detail of
// kos-platform; no shell surface parses nmcli or starts a child process.
QtObject {
    id: service

    property bool available: false
    property bool networkingEnabled: true
    property bool wifiEnabled: true
    property string connectionType: "none"
    property string deviceState: "unknown"
    property string connectivity: "unknown"
    property string deviceName: ""
    property string connectionName: ""
    property string ssid: ""
    property int signalStrength: -1
    property string ipv4: ""
    property var nearbyWifi: []
    property bool wifiScanInProgress: false
    property int wifiScanRevision: 0
    property bool wifiConnectInProgress: false
    property string wifiConnectSsid: ""
    property string wifiConnectError: ""
    property bool wifiDisconnectInProgress: false
    property string wifiDisconnectError: ""
    property bool wifiForgetInProgress: false
    property string wifiForgetError: ""
    property bool wifiToggleInProgress: false
    property string wifiToggleError: ""
    signal wifiConnectionFinished(string ssid, bool success)
    signal wifiForgetFinished(string ssid, bool success)
    property bool _scanAfterWifiEnable: false

    function _applySnapshot(result) {
        available = !!result.available
        networkingEnabled = result.networkingEnabled !== false
        wifiEnabled = result.wifiEnabled !== false
        connectionType = result.connectionType || "none"
        deviceState = result.deviceState || "unknown"
        connectivity = result.connectivity || "unknown"
        deviceName = result.deviceName || ""
        connectionName = result.connectionName || ""
        ssid = result.ssid || ""
        signalStrength = Number(result.signalStrength ?? -1)
        ipv4 = result.ipv4 || ""
        if (deviceState === "connected")
            _refreshDetails()
    }

    function _refreshDetails() {
        if (!deviceName)
            return
        PlatformClient.request("network.details", { device: deviceName }, function(response) {
            if (!response?.ok || deviceName === "")
                return
            const rows = String(response.result?.stdout || "").trim().split("\n")
            if (rows[0] && rows[0] !== "--")
                connectionName = rows[0]
            ipv4 = (rows[1] || "").replace(/\/\d+$/, "")
            if (connectionType === "wifi")
                ssid = connectionName
        })
    }

    function refresh() {
        PlatformClient.request("network.refresh", {}, function(response) {
            if (response?.ok)
                _applySnapshot(response.result || ({}))
            else {
                available = false
                connectionType = "none"
                deviceState = "unknown"
            }
        })
    }

    function refreshWifiNetworks() {
        if (wifiScanInProgress || !deviceName || connectionType !== "wifi" || !wifiEnabled)
            return
        wifiScanInProgress = true
        PlatformClient.request("network.scan", { device: deviceName }, function(response) {
            wifiScanInProgress = false
            if (!response?.ok)
                return
            nearbyWifi = Array.isArray(response.result?.networks)
                ? response.result.networks : []
            wifiScanRevision++
        })
    }

    function connectWifi(ssid, password, savedProfileUuid) {
        const target = String(ssid || "").trim()
        if (wifiConnectInProgress || !target || !deviceName)
            return false
        wifiConnectInProgress = true
        wifiConnectSsid = target
        wifiConnectError = ""
        PlatformClient.request("network.connect", { ssid: target, password: String(password || ""),
            savedProfileUuid: String(savedProfileUuid || ""), device: deviceName }, function(response) {
            const success = !!response?.ok
            wifiConnectInProgress = false
            wifiConnectError = success ? "" : "无法连接，请检查密码或网络状态"
            if (success)
                refresh()
            wifiConnectionFinished(target, success)
        })
        return true
    }

    function connectEnterpriseWifi(ssid, identity, password, eapMethod, anonymousIdentity) {
        const target = String(ssid || "").trim()
        const method = String(eapMethod || "").toLowerCase()
        if (wifiConnectInProgress || !target || !identity || !password || !deviceName
                || ["peap", "ttls"].indexOf(method) < 0)
            return false
        wifiConnectInProgress = true
        wifiConnectSsid = target
        wifiConnectError = ""
        PlatformClient.request("network.connect-enterprise", { ssid: target, device: deviceName,
            identity: String(identity), password: String(password), eapMethod: method,
            anonymousIdentity: String(anonymousIdentity || "") }, function(response) {
            const success = !!response?.ok
            wifiConnectInProgress = false
            wifiConnectError = success ? "" : "无法完成 802.1X 认证，请确认账号、密码和认证方式"
            if (success)
                refresh()
            wifiConnectionFinished(target, success)
        })
        return true
    }

    function disconnectActiveWifi() {
        if (wifiDisconnectInProgress || connectionType !== "wifi" || !deviceName)
            return false
        wifiDisconnectInProgress = true
        wifiDisconnectError = ""
        PlatformClient.request("network.disconnect", { device: deviceName }, function(response) {
            wifiDisconnectInProgress = false
            if (response?.ok)
                refresh()
            else
                wifiDisconnectError = "无法断开当前 Wi‑Fi"
        })
        return true
    }

    function forgetWifiProfile(ssid, profileUuid) {
        const target = String(ssid || "").trim()
        const uuid = String(profileUuid || "").trim()
        if (wifiForgetInProgress || !target || !uuid)
            return false
        wifiForgetInProgress = true
        wifiForgetError = ""
        PlatformClient.request("network.forget", { uuid: uuid }, function(response) {
            wifiForgetInProgress = false
            const success = !!response?.ok
            if (success)
                refreshWifiNetworks()
            else
                wifiForgetError = "无法忘记此网络"
            wifiForgetFinished(target, success)
        })
        return true
    }

    function setWifiEnabled(enabled) {
        const desired = !!enabled
        if (wifiToggleInProgress || desired === wifiEnabled)
            return false
        wifiToggleInProgress = true
        wifiToggleError = ""
        PlatformClient.request("network.wifi-power", { enabled: desired }, function(response) {
            wifiToggleInProgress = false
            if (response?.ok) {
                wifiEnabled = desired
                nearbyWifi = desired ? nearbyWifi : []
                refresh()
                if (desired)
                    wifiEnableScanTimer.restart()
            } else {
                wifiToggleError = "无法切换 Wi‑Fi，请检查 NetworkManager"
            }
        })
        return true
    }

    property Timer refreshTimer: Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: service.refresh()
    }
    property Timer wifiEnableScanTimer: Timer {
        interval: 900
        repeat: false
        onTriggered: { service.refresh(); service.refreshWifiNetworks() }
    }
    property Timer wifiPostDisconnectScanTimer: Timer {
        interval: 400
        repeat: false
        onTriggered: service.refreshWifiNetworks()
    }
    Component.onCompleted: refresh()
}
