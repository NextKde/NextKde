pragma Singleton

import QtQuick
import Quickshell.Io

// NetworkService is the single NetworkManager adapter for shell surfaces.
// It normalizes `nmcli` output into a stable interface and owns the Wi-Fi
// write operations (connect / connectEnterprise / disconnect / forget /
// radio toggle) as explicit methods, each reporting success or failure back
// to its caller so a Bar icon never silently changes system networking.
QtObject {
    id: service

    // Public presentation contract. Consumers must not parse nmcli output or
    // infer internet health from a device state; `connectivity` is separate.
    property bool available: false
    property bool networkingEnabled: true
    property bool wifiEnabled: true
    property string connectionType: "none" // wifi | ethernet | none
    property string deviceState: "unknown" // connected | connecting | disconnected | disabled | unknown
    property string connectivity: "unknown" // full | portal | limited | none | unknown
    property string deviceName: ""
    property string connectionName: ""
    property string ssid: ""
    property int signalStrength: -1 // 0..100; -1 when irrelevant/unavailable
    property string ipv4: ""
    // Nearby access points are a presentation-ready, de-duplicated list that
    // the connection UI consumes instead of parsing nmcli itself.
    property var nearbyWifi: []
    property bool wifiScanInProgress: false
    property int wifiScanRevision: 0
    // Write-operation state is public so the panel and later control centre
    // can show one consistent connecting/error state without polling nmcli.
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
    property var _refreshProcess: null
    property var _detailsProcess: null
    property var _wifiScanProcess: null
    property var _wifiToggleProcess: null
    property var _wifiDisconnectProcess: null
    property var _wifiForgetProcess: null
    // A Wi-Fi device needs a short settling period after the radio is turned
    // back on. This flag ties the follow-up scan to that explicit user action
    // instead of increasing the normal background polling work.
    property bool _scanAfterWifiEnable: false
    property string _lastLoggedState: ""

    function _logStateIfChanged() {
        const state = connectionType + "|" + deviceState + "|" + connectivity
            + "|" + deviceName + "|" + connectionName
        if (state === _lastLoggedState)
            return
        _lastLoggedState = state
        console.log("[Network] type=" + connectionType + " state=" + deviceState
            + " connectivity=" + connectivity + " device=" + deviceName
            + " connection=" + connectionName)
    }

    function _splitNmcliLine(line) {
        // nmcli terse output escapes delimiters as `\\:`. Keep parsing here
        // so SSIDs/connection names containing a colon remain valid data.
        const fields = []
        let value = ""
        let escaped = false
        for (let i = 0; i < line.length; i++) {
            const character = line[i]
            if (escaped) {
                value += character
                escaped = false
            } else if (character === "\\") {
                escaped = true
            } else if (character === ":") {
                fields.push(value)
                value = ""
            } else {
                value += character
            }
        }
        fields.push(value)
        return fields
    }

    function _resetUnavailable() {
        available = false
        connectionType = "none"
        deviceState = "unknown"
        connectivity = "unknown"
        deviceName = ""
        connectionName = ""
        ssid = ""
        signalStrength = -1
        ipv4 = ""
    }

    function _applySnapshot(output) {
        const parts = output.split("\u001e")
        const general = _splitNmcliLine((parts[0] || "").trim())
        if (general.length < 3 || general[0] !== "running") {
            _resetUnavailable()
            return
        }

        available = true
        networkingEnabled = general[0] === "running"
        // `nmcli general` reports the radio independently from device state:
        // a disabled Wi-Fi card may still appear in `device status`.
        if (general.length >= 4)
            wifiEnabled = String(general[3]).toLowerCase() !== "disabled"
        // NetworkManager uses connected/connecting/disconnected values here.
        // The connectivity check is authoritative for portal/limited/full.
        connectivity = String(general[2] || "unknown").toLowerCase()
        if (["full", "portal", "limited", "none", "unknown"].indexOf(connectivity) < 0)
            connectivity = "unknown"

        const rows = (parts[1] || "").trim().split("\n")
        let chosen = null
        let fallback = null
        for (let i = 0; i < rows.length; i++) {
            if (!rows[i])
                continue
            const fields = _splitNmcliLine(rows[i])
            if (fields.length < 3)
                continue
            const type = fields[1] === "wifi" ? "wifi"
                : (fields[1] === "ethernet" ? "ethernet" : "")
            if (!type)
                continue
            const candidate = {
                device: fields[0], type: type,
                state: String(fields[2] || "").toLowerCase(),
                connection: fields.slice(3).join(":")
            }
            if (!fallback)
                fallback = candidate
            if (candidate.state === "connected") {
                chosen = candidate
                break
            }
            if (!chosen && candidate.state.indexOf("connect") >= 0)
                chosen = candidate
        }
        chosen = chosen || fallback
        if (!chosen) {
            connectionType = "none"
            deviceState = networkingEnabled ? "disconnected" : "disabled"
            deviceName = ""
            connectionName = ""
            ssid = ""
            signalStrength = -1
            ipv4 = ""
            _logStateIfChanged()
            return
        }

        connectionType = chosen.type
        deviceName = chosen.device
        connectionName = chosen.connection === "--" ? "" : chosen.connection
        deviceState = chosen.state === "connected" ? "connected"
            : (chosen.state.indexOf("connect") >= 0 ? "connecting"
                : (chosen.state === "disconnected" ? "disconnected" : "unknown"))
        ssid = chosen.type === "wifi" && deviceState === "connected"
            ? connectionName : ""
        signalStrength = -1
        ipv4 = ""
        if (deviceState === "connected")
            _refreshDetails(chosen.device, chosen.type)
        _logStateIfChanged()
    }

    function _refreshDetails(device, type) {
        if (_detailsProcess)
            return
        // `-g` emits one value per line. The device name is passed as a
        // positional argument, never interpolated into a shell command.
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "nmcli -g GENERAL.CONNECTION,IP4.ADDRESS device show \"$1\"; "
                + "if [ \"$2\" = wifi ]; then "
                + "nmcli -t -f IN-USE,SIGNAL device wifi list ifname \"$1\" "
                + "2>/dev/null | awk -F: '$1 == \"*\" { print $2; exit }'; fi",
                "network-details", device, type]
        })
        _detailsProcess = proc
        proc.exited.connect(function(code) {
            if (service._detailsProcess === proc)
                service._detailsProcess = null
            if (code === 0 && service.deviceName === device) {
                const rows = (proc.stdout?.text ?? "").trim().split("\n")
                // `GENERAL.CONNECTION` repeats the active profile name. Keep
                // the snapshot value unless NetworkManager returns a better
                // device-scoped value here.
                if (rows[0] && rows[0] !== "--")
                    service.connectionName = rows[0]
                service.ipv4 = (rows[1] || "").replace(/\/\d+$/, "")
                if (type === "wifi") {
                    service.ssid = service.connectionName
                    const strength = Number(rows[2])
                    service.signalStrength = Number.isFinite(strength)
                        ? Math.max(0, Math.min(100, Math.round(strength))) : -1
                }
            }
            proc.destroy()
        })
        proc.running = true
    }

    function refreshWifiNetworks() {
        const device = deviceName
        if (_wifiScanProcess || !device || connectionType !== "wifi" || !wifiEnabled)
            return
        wifiScanInProgress = true
        // Scan only when the user opens the network panel. `--rescan auto`
        // lets NetworkManager decide whether its recent AP cache is fresh;
        // this avoids a permanent background RF scan just for the Bar.
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                // A connection name is user-editable and therefore cannot be
                // used as a stable saved-network identifier. Resolve SSID to
                // the immutable UUID here, alongside the user-triggered scan.
                "nmcli -t -f UUID,TYPE connection show | "
                    + "while IFS=: read -r uuid type; do "
                    + "[ \"$type\" = \"802-11-wireless\" ] || continue; "
                    + "ssid=$(nmcli -g 802-11-wireless.ssid connection show uuid \"$uuid\" 2>/dev/null | sed -n '1p'); "
                    + "[ -n \"$ssid\" ] && printf '%s\\t%s\\n' \"$ssid\" \"$uuid\"; "
                    + "done; printf '\\036'; "
                    + "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list "
                    + "ifname \"$1\" --rescan auto",
                "network-wifi-scan", device]
        })
        _wifiScanProcess = proc
        proc.exited.connect(function(code) {
            if (service._wifiScanProcess === proc)
                service._wifiScanProcess = null
            service.wifiScanInProgress = false
            if (code === 0 && service.deviceName === device) {
                const sections = (proc.stdout?.text ?? "").split("\u001e")
                const savedProfileBySsid = ({})
                const savedRows = (sections[0] || "").split("\n")
                for (let i = 0; i < savedRows.length; i++) {
                    const fields = savedRows[i].split("\t")
                    const savedSsid = String(fields[0] || "").trim()
                    const uuid = String(fields[1] || "").trim()
                    if (savedSsid && uuid)
                        savedProfileBySsid[savedSsid] = uuid
                }
                const bySsid = ({})
                const rows = (sections[1] || "").split("\n")
                for (let i = 0; i < rows.length; i++) {
                    if (!rows[i])
                        continue
                    const fields = service._splitNmcliLine(rows[i])
                    const ssid = String(fields[1] || "").trim()
                    const signal = Math.max(0, Math.min(100, Number(fields[2]) || 0))
                    if (!ssid)
                        continue // Hidden APs need a separate manual flow.
                    const record = {
                        ssid: ssid,
                        signalStrength: signal,
                        security: fields.slice(3).join(":"),
                        secured: fields.slice(3).join(":").trim().length > 0,
                        // NetworkManager represents WPA-Enterprise APs as
                        // e.g. "WPA2 802.1X". Expose that semantic once here
                        // so every future network surface gets the same
                        // credential flow without re-parsing raw nmcli text.
                        enterprise: fields.slice(3).join(":").toLowerCase()
                            .indexOf("802.1x") >= 0,
                        // UUID, rather than profile name, survives users
                        // renaming a NetworkManager connection.
                        savedProfileUuid: savedProfileBySsid[ssid] || "",
                        active: String(fields[0] || "").trim() === "*"
                    }
                    const existing = bySsid[ssid]
                    if (!existing || record.active || signal > existing.signalStrength)
                        bySsid[ssid] = record
                }
                const networks = Object.keys(bySsid).map(function(key) {
                    return bySsid[key]
                })
                networks.sort(function(left, right) {
                    if (left.active !== right.active)
                        return left.active ? -1 : 1
                    if (left.signalStrength !== right.signalStrength)
                        return right.signalStrength - left.signalStrength
                    return left.ssid.localeCompare(right.ssid)
                })
                service.nearbyWifi = networks
                service.wifiScanRevision++
                console.log("[Network] wifi scan networks=" + networks.length)
            }
            proc.destroy()
        })
        proc.running = true
    }

    function connectWifi(ssid, password, savedProfileUuid) {
        const targetSsid = String(ssid || "").trim()
        const targetPassword = String(password || "")
        const targetProfileUuid = String(savedProfileUuid || "").trim()
        const device = deviceName
        if (wifiConnectInProgress || !targetSsid || !device)
            return false
        wifiConnectInProgress = true
        wifiConnectSsid = targetSsid
        wifiConnectError = ""
        // With no supplied password, activate the UUID resolved during the
        // scan. This lets a user reconnect after “断开” without re-entering a
        // secret even when their saved profile was renamed.
        // All user values are positional arguments; password is deliberately
        // absent from command strings and logs.
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "if [ -n \"$3\" ]; then "
                    + "nmcli --wait 20 device wifi connect \"$1\" password \"$3\" ifname \"$2\"; "
                + "elif [ -n \"$4\" ]; then nmcli --wait 20 connection up uuid \"$4\" ifname \"$2\"; "
                + "else nmcli --wait 20 device wifi connect \"$1\" ifname \"$2\"; fi",
                "network-wifi-connect", targetSsid, device, targetPassword,
                targetProfileUuid]
        })
        proc.exited.connect(function(code) {
            service.wifiConnectInProgress = false
            const success = code === 0
            if (success) {
                service.wifiConnectError = ""
                console.log("[Network] connected ssid=" + targetSsid)
                service.refresh()
                service.refreshWifiNetworks()
            } else {
                // Do not surface stderr: NetworkManager output can vary and
                // must never become an accidental channel for secret data.
                service.wifiConnectError = targetPassword.length
                    ? "无法连接，请检查密码或网络状态"
                    : "未找到已保存的网络，请输入 Wi‑Fi 密码"
                console.warn("[Network] connection failed ssid=" + targetSsid)
            }
            service.wifiConnectionFinished(targetSsid, success)
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function connectEnterpriseWifi(ssid, identity, password, eapMethod,
                                   anonymousIdentity) {
        const targetSsid = String(ssid || "").trim()
        const targetIdentity = String(identity || "").trim()
        const targetPassword = String(password || "")
        const targetAnonymousIdentity = String(anonymousIdentity || "").trim()
        const device = deviceName
        // Keep the supported methods deliberately small and explicit. A
        // caller may never inject arbitrary nmcli setting names or values.
        const method = String(eapMethod || "").toLowerCase()
        const phase2 = method === "peap" ? "mschapv2"
            : (method === "ttls" ? "pap" : "")
        if (wifiConnectInProgress || !targetSsid || !targetIdentity
                || !targetPassword || !device || !phase2)
            return false

        wifiConnectInProgress = true
        wifiConnectSsid = targetSsid
        wifiConnectError = ""
        // This deterministic prefix marks a profile as shell-owned. We only
        // replace this exact profile, never an arbitrary user-created nmcli
        // connection with the same SSID. Sensitive values remain positional
        // process arguments and never occur in logs or command text.
        const profile = "quickshell-8021x-" + targetSsid
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "nmcli connection delete \"$8\" >/dev/null 2>&1 || true; "
                    + "nmcli connection add type wifi ifname \"$2\" con-name \"$8\" ssid \"$1\"; "
                    + "nmcli connection modify \"$8\" wifi-sec.key-mgmt wpa-eap "
                    + "802-1x.eap \"$3\" 802-1x.identity \"$4\" "
                    + "802-1x.password \"$5\" 802-1x.phase2-auth \"$6\" "
                    + "connection.autoconnect yes; "
                    + "if [ -n \"$7\" ]; then nmcli connection modify \"$8\" "
                    + "802-1x.anonymous-identity \"$7\"; fi; "
                    + "nmcli --wait 25 connection up \"$8\" ifname \"$2\"",
                "network-enterprise-connect", targetSsid, device, method,
                targetIdentity, targetPassword, phase2, targetAnonymousIdentity,
                profile]
        })
        proc.exited.connect(function(code) {
            service.wifiConnectInProgress = false
            const success = code === 0
            if (success) {
                service.wifiConnectError = ""
                console.log("[Network] enterprise connected ssid=" + targetSsid
                    + " eap=" + method)
                service.refresh()
                service.refreshWifiNetworks()
            } else {
                service.wifiConnectError = "无法完成 802.1X 认证，请确认账号、密码和认证方式"
                console.warn("[Network] enterprise connection failed ssid="
                    + targetSsid + " eap=" + method)
            }
            service.wifiConnectionFinished(targetSsid, success)
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function disconnectActiveWifi() {
        const device = deviceName
        if (wifiDisconnectInProgress || connectionType !== "wifi"
                || deviceState !== "connected" || !device)
            return false
        wifiDisconnectInProgress = true
        wifiDisconnectError = ""
        const proc = processFactory.createObject(service, {
            command: ["nmcli", "device", "disconnect", device]
        })
        _wifiDisconnectProcess = proc
        proc.exited.connect(function(code) {
            if (service._wifiDisconnectProcess === proc)
                service._wifiDisconnectProcess = null
            service.wifiDisconnectInProgress = false
            if (code === 0) {
                console.log("[Network] wifi disconnected device=" + device)
                service.refresh()
                service.wifiPostDisconnectScanTimer.restart()
            } else {
                service.wifiDisconnectError = "无法断开当前 Wi‑Fi"
                console.warn("[Network] wifi disconnect failed device=" + device)
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function forgetWifiProfile(ssid, profileUuid) {
        const targetSsid = String(ssid || "").trim()
        const targetUuid = String(profileUuid || "").trim()
        // The UUID originated from our own scan result. Never accept a name
        // here: names are ambiguous, while deleting a UUID is precise.
        if (wifiForgetInProgress || !targetSsid || !targetUuid)
            return false
        wifiForgetInProgress = true
        wifiForgetError = ""
        const proc = processFactory.createObject(service, {
            command: ["nmcli", "connection", "delete", "uuid", targetUuid]
        })
        _wifiForgetProcess = proc
        proc.exited.connect(function(code) {
            if (service._wifiForgetProcess === proc)
                service._wifiForgetProcess = null
            service.wifiForgetInProgress = false
            const success = code === 0
            if (success) {
                console.log("[Network] forgot wifi profile ssid=" + targetSsid)
                service.refreshWifiNetworks()
            } else {
                service.wifiForgetError = "无法忘记此网络"
                console.warn("[Network] forget wifi failed ssid=" + targetSsid)
            }
            service.wifiForgetFinished(targetSsid, success)
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function setWifiEnabled(enabled) {
        const desired = Boolean(enabled)
        if (wifiToggleInProgress || desired === wifiEnabled)
            return false
        wifiToggleInProgress = true
        wifiToggleError = ""
        const proc = processFactory.createObject(service, {
            command: ["nmcli", "radio", "wifi", desired ? "on" : "off"]
        })
        _wifiToggleProcess = proc
        proc.exited.connect(function(code) {
            if (service._wifiToggleProcess === proc)
                service._wifiToggleProcess = null
            service.wifiToggleInProgress = false
            if (code === 0) {
                // Update immediately, then let the normal snapshot confirm
                // all device fields without making UI wait for the poll.
                service.wifiEnabled = desired
                if (!desired) {
                    service.nearbyWifi = []
                    service._scanAfterWifiEnable = false
                } else {
                    service._scanAfterWifiEnable = true
                }
                service.refresh()
            } else {
                service.wifiToggleError = "无法切换 Wi‑Fi，请检查 NetworkManager"
                console.warn("[Network] wifi radio toggle failed desired=" + desired)
            }
            proc.destroy()
        })
        proc.running = true
        return true
    }

    function refresh() {
        if (_refreshProcess)
            return
        const proc = processFactory.createObject(service, {
            command: ["sh", "-c",
                "nmcli -t -f RUNNING,STATE,CONNECTIVITY,WIFI general; "
                + "printf '\\036'; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device",
                "network-snapshot"]
        })
        _refreshProcess = proc
        proc.exited.connect(function(code) {
            if (service._refreshProcess === proc)
                service._refreshProcess = null
            if (code === 0) {
                service._applySnapshot(proc.stdout?.text ?? "")
                if (service._scanAfterWifiEnable) {
                    service._scanAfterWifiEnable = false
                    service.wifiEnableScanTimer.restart()
                }
            } else {
                service._resetUnavailable()
            }
            proc.destroy()
        })
        proc.running = true
    }

    // Wi-Fi write operations (connect / connectEnterprise / disconnectActive /
    // forgetWifiProfile / setWifiEnabled) are implemented above. Each runs an
    // explicit nmcli call and reports success/failure back to its caller, so a
    // Bar icon never silently changes system network configuration.
    property Component processFactory: Component {
        Process {
            stdout: StdioCollector {}
            stderr: StdioCollector {}
        }
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
        onTriggered: {
            // Refresh once more after NetworkManager has recreated the Wi-Fi
            // device state, then scan from the confirmed interface name.
            service.refresh()
            service.refreshWifiNetworks()
        }
    }

    property Timer wifiPostDisconnectScanTimer: Timer {
        interval: 400
        repeat: false
        onTriggered: service.refreshWifiNetworks()
    }

    Component.onCompleted: refresh()
}
