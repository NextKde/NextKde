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
    // The wireless interface's ifname, reported by network.refresh
    // independently of which device currently carries connectivity. The
    // ethernet device wins `deviceName` whenever Wi-Fi is idle, so scans
    // must target this name or they never run while a cable is plugged in.
    property string wifiDeviceName: ""
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
    // Set by refreshWifiNetworks() when no wifi ifname is known yet (the
    // first refresh is still in flight); _applySnapshot drains it once the
    // daemon reports wifiDeviceName.
    property bool _scanPendingDevice: false

    function _applySnapshot(result) {
        available = !!result.available
        networkingEnabled = result.networkingEnabled !== false
        // A radio power change is not instant: NetworkManager can still
        // report the pre-toggle state for a moment after setWifiEnabled()'s
        // own request already resolved. Applying a periodic refresh's stale
        // read here raced that resolution and flipped the toggle back and
        // forth (off -> briefly on -> off again). Trust only the toggle's
        // own response while one is in flight.
        if (!wifiToggleInProgress)
            wifiEnabled = result.wifiEnabled !== false
        connectionType = result.connectionType || "none"
        deviceState = result.deviceState || "unknown"
        connectivity = result.connectivity || "unknown"
        deviceName = result.deviceName || ""
        if (result.wifiDeviceName !== undefined)
            wifiDeviceName = String(result.wifiDeviceName)
        connectionName = result.connectionName || ""
        ssid = result.ssid || ""
        // network.refresh never carries real ipv4/signalStrength (nmcli's
        // device table has neither); network.details fills them in a moment
        // later via _refreshDetails(). Leaving them alone here avoids
        // clobbering the last known-good value to a placeholder every
        // refreshTimer tick, which made the tooltip/icon flicker empty and
        // resize every few seconds.
        if (deviceState === "connected") {
            if (connectionType !== "wifi")
                signalStrength = -1
            _refreshDetails()
        } else {
            ipv4 = ""
            signalStrength = -1
        }
        // A scan requested before the first refresh knew the wifi ifname
        // drains here once the snapshot supplies it.
        if (_scanPendingDevice && wifiDeviceName) {
            _scanPendingDevice = false
            refreshWifiNetworks()
        }
    }

    function _refreshDetails() {
        if (!deviceName)
            return
        PlatformClient.request("network.details", { device: deviceName }, function(response) {
            if (!response?.ok || deviceName === "")
                return
            const result = response.result || ({})
            if (result.connectionName)
                connectionName = String(result.connectionName)
            ipv4 = String(result.ipv4 || "").replace(/\/\d+$/, "")
            if (connectionType === "wifi" && result.ssid)
                ssid = String(result.ssid)
            if (connectionType === "wifi" && result.signalStrength !== undefined)
                signalStrength = Number(result.signalStrength)
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
        // Scan the wifi interface itself, not whichever device currently
        // carries connectivity: with ethernet plugged in `connectionType`
        // is "ethernet" and `deviceName` the NIC, which is exactly the
        // state where the list must still show nearby APs. If the first
        // refresh has not delivered wifiDeviceName yet, queue the scan.
        const device = wifiDeviceName
        if (!device) {
            _scanPendingDevice = wifiEnabled && !wifiScanInProgress
            return
        }
        _scanPendingDevice = false
        if (wifiScanInProgress || !wifiEnabled)
            return
        wifiScanInProgress = true
        PlatformClient.request("network.scan", { device: device }, function(response) {
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
        // Wi-Fi connections must target the wireless interface, not whichever
        // device currently carries connectivity: with ethernet plugged in
        // `deviceName` is the NIC and ActivateConnection would resolve the
        // wired path, and NM rejects activating a wifi profile on it.
        if (wifiConnectInProgress || !target || !wifiDeviceName)
            return false
        wifiConnectInProgress = true
        wifiConnectSsid = target
        wifiConnectError = ""
        PlatformClient.request("network.connect", { ssid: target, password: String(password || ""),
            savedProfileUuid: String(savedProfileUuid || ""), device: wifiDeviceName }, function(response) {
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
        // Same as connectWifi: the wireless interface, not `deviceName`.
        if (wifiConnectInProgress || !target || !identity || !password || !wifiDeviceName
                || ["peap", "ttls"].indexOf(method) < 0)
            return false
        wifiConnectInProgress = true
        wifiConnectSsid = target
        wifiConnectError = ""
        PlatformClient.request("network.connect-enterprise", { ssid: target, device: wifiDeviceName,
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
            if (response?.ok) {
                refresh()
                // The radio only learns the full AP set after the link is
                // down; rescan shortly after disconnect so the list is not
                // stuck at the one previously-connected SSID.
                wifiPostDisconnectScanTimer.restart()
            }
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

    // Network state still comes from polling: the daemon's PropertiesChanged
    // watches only invalidate its reply cache, they never push to the shell.
    // Poll fast while a status panel is showing the data and drop to a
    // once-a-minute floor otherwise, so the tray icon still tracks
    // connectivity changes without a constant 3s churn.
    readonly property bool _panelOpen: ControlCenterService.anyPanelOpen
    property Connections _panelState: Connections {
        target: ControlCenterService
        function onAnyPanelOpenChanged() {
            if (ControlCenterService.anyPanelOpen)
                service.refresh()
        }
    }
    property Timer refreshTimer: Timer {
        interval: service._panelOpen ? 3000 : 60000
        repeat: true
        running: PlatformClient.socket.connected
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
    property Connections platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                service.refresh()
            } else {
                // The client fails every outstanding callback on disconnect,
                // which already clears these; reset defensively so a Wi-Fi
                // control can never stay wedged by a lost response.
                wifiScanInProgress = false
                wifiConnectInProgress = false
                wifiDisconnectInProgress = false
                wifiForgetInProgress = false
                wifiToggleInProgress = false
            }
        }
    }
    Component.onCompleted: refresh()
}
