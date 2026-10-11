pragma Singleton

import QtQuick
import Quickshell
import qs.desktop.modules.platform
import qs.desktop.modules.common
import qs.desktop.modules.dock
import Quickshell.Services.SystemTray

// Shared Control Centre state. The resident platform service owns PipeWire,
// BlueZ, brightness, session, screenshot and theme integration.
QtObject {
    id: service

    property bool audioAvailable: false
    property int volumePercent: 0
    property bool audioMuted: false
    property var audioApplications: []
    property bool audioApplicationsAvailable: false
    property bool audioApplicationsRefreshInProgress: false
    property var audioOutputs: []
    property bool audioOutputsRefreshInProgress: false
    property bool audioOutputChangeInProgress: false
    property string _audioOutputReadError: ""
    property string _audioOutputChangeError: ""
    readonly property string audioOutputError: _audioOutputChangeError || _audioOutputReadError
    property bool volumeChangeInProgress: false
    property bool brightnessAvailable: false
    property int brightnessPercent: 0
    property var brightnessDisplays: []
    property string brightnessPrimaryDisplayId: ""
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
    property bool keepAwakeAvailable: false
    property bool keepAwakeEnabled: false
    property bool keepAwakeChangeInProgress: false
    property string keepAwakeError: ""
    property bool nightLightAvailable: true
    property bool nightLightEnabled: false
    property bool nightLightActive: false
    property bool nightLightChangeInProgress: false
    signal toggleRequested()

    // Every surface that shows this service's live data (network/bluetooth
    // quick panels, the control centre itself) registers while it is open.
    // The fast poll only runs while someone can see the result; a slow floor
    // keeps the always-on consumers (DeskCenter card, first-open paint) from
    // going fully stale at a fraction of the idle cost.
    property int _openPanelCount: 0
    readonly property bool anyPanelOpen: _openPanelCount > 0
    function notePanelOpen(open) {
        _openPanelCount = Math.max(0, _openPanelCount + (open ? 1 : -1))
    }
    onAnyPanelOpenChanged: if (anyPanelOpen) refresh()

    function notificationActionLabel(action) {
        const label = String(action?.text || "").trim()
        const identifier = String(action?.identifier || "").trim().toLowerCase()
        const translations = {
            "default": "查看", "view": "查看", "open": "打开",
            "reply": "回复", "close": "关闭", "mark as read": "标为已读"
        }
        const translated = translations[label.toLowerCase()]
        if (translated) return translated
        if (identifier === "default" || identifier === "view") return "查看"
        if (!label) return translations[identifier] || "查看"
        return label
    }

    function notificationCategory(appName, desktopEntry) {
        const key = String(appName || "") + " " + String(desktopEntry || "")
        if (/(^|[^a-z])qq([^a-z]|$)/i.test(key)) return "QQ"
        if (/wechat|weixin|微信/i.test(key)) return "微信"
        if (/telegram/i.test(key)) return "Telegram"
        return "其他"
    }

    function rebuildHistoryGroups() {
        const groups = []
        const groupIndex = ({})
        for (let i = 0; i < notificationHistory.count; ++i) {
            const row = notificationHistory.get(i)
            const category = notificationCategory(row.appName, row.desktopEntry)
            const key = category === "其他" ? (row.appName || "其他") : category
            let index = groupIndex[key]
            if (index === undefined) {
                index = groups.length
                groupIndex[key] = index
                groups.push({ appName: key, appIcon: row.appIcon, items: [] })
            }
            groups[index].items.push({ notifId: row.notifId, summary: row.summary,
                body: row.body, timestamp: row.timestamp, desktopEntry: row.desktopEntry || "" })
        }
        historyGroups = groups
        historyRevision++
    }

    property var groupService: null
    property var _liveNotifications: ({})

    function registerLiveNotification(notification) {
        if (!notification) return
        if (notification.id !== undefined && notification.id !== null) {
            _liveNotifications[notification.id] = notification
            _liveNotifications[String(notification.id)] = notification
        }
    }

    function unregisterLiveNotification(notifId) {
        if (notifId !== undefined && notifId !== null) {
            delete _liveNotifications[notifId]
            delete _liveNotifications[String(notifId)]
        }
    }

    function invokeNotificationAction(notifId, appName, desktopEntry, actionIdentifier) {
        let live = null
        if (notifId !== undefined && notifId !== null) {
            live = _liveNotifications[notifId] || _liveNotifications[String(notifId)]
        }
        // A history row must invoke its own message, never another chat's
        // latest notification. Closed/replaced notifications cannot be invoked.

        if (live && live.tracked && live.actions && live.actions.length > 0) {
            // A banner button supplies its exact action, including reply and
            // custom actions. Never substitute another button for it.
            const requested = actionIdentifier === undefined ? null : String(actionIdentifier)
            let action = null
            for (let i = 0; i < live.actions.length; i++) {
                const act = live.actions[i]
                if (!act) continue
                if (requested !== null) {
                    if (act.identifier === requested) { action = act; break }
                    continue
                }
                const ident = String(act.identifier || "").trim().toLowerCase()
                const text = String(act.text || "").trim().toLowerCase()
                if (ident === "default" || ident === "view" || ident === "open"
                    || text === "查看" || text === "打开" || text.indexOf("查看") >= 0) {
                    action = act; break
                }
            }
            if (!action && requested === null) action = live.actions[0]
            if (action) {
                // Quickshell closes non-resident notifications itself. Do not
                // touch the destroyed object or dismiss its app's other chats.
                try { action.invoke(); return true; } catch (e) {
                    console.warn("[ControlCenterService] invoke failed: " + e)
                }
            }
        }
        return false
    }

    function matchesApp(value, target) {
        const category = ControlCenterService.notificationCategory(target, target)
        if (category !== "其他") return ControlCenterService.notificationCategory(value, value) === category
        return AppIdentityService.normalize(value) === AppIdentityService.normalize(target)
    }

    function activateAppWindow(targetId) {
        if (!targetId) return false
        // 1. Check direct WindowService match
        const windows = WindowService.windowsForApp(targetId)
        if (windows && windows.length > 0) {
            WindowService.activateWindow(windows[0].windowId)
            return true
        }

        // 2. Exact match in open windows
        const cleanTarget = targetId.toLowerCase().replace(/\.desktop$/i, "").trim()
        if (!cleanTarget) return false
        const records = WindowService.records || []
        for (let i = 0; i < records.length; i++) {
            const rec = records[i]
            const identity = rec.identity || {}
            const desktopId = (identity.desktopId || "").toLowerCase().replace(/\.desktop$/i, "")
            const rawAppId = (identity.rawAppId || "").toLowerCase().replace(/\.desktop$/i, "")
            const name = (identity.name || "").toLowerCase()
            if ((desktopId && matchesApp(desktopId, cleanTarget)) ||
                (rawAppId && matchesApp(rawAppId, cleanTarget)) ||
                (name && matchesApp(name, cleanTarget))) {
                WindowService.activateWindow(rec.windowId)
                return true
            }
        }

        // 3. Check SystemTray items (if window was hidden to tray)
        const trayItems = SystemTray.items.values || []
        for (let t = 0; t < trayItems.length; t++) {
            const item = trayItems[t]
            if (!item) continue
            const friendly = (SysTrayIdentityService.friendlyName(item) || "").toLowerCase()
            const itemId = (item.id || "").toLowerCase()
            const itemTitle = (item.title || "").toLowerCase()
            if ((friendly && matchesApp(friendly, cleanTarget)) ||
                (itemId && matchesApp(itemId, cleanTarget)) ||
                (itemTitle && matchesApp(itemTitle, cleanTarget))) {
                try {
                    item.activate()
                    return true
                } catch (e) {}
            }
        }
        return false
    }

    function isAppRunning(targetId) {
        if (!targetId) return false
        const cleanTarget = targetId.toLowerCase().replace(/\.desktop$/i, "").trim()
        if (!cleanTarget) return false
        const records = WindowService.records || []
        for (let i = 0; i < records.length; i++) {
            const rec = records[i]
            const identity = rec.identity || {}
            const desktopId = (identity.desktopId || "").toLowerCase().replace(/\.desktop$/i, "")
            const rawAppId = (identity.rawAppId || "").toLowerCase().replace(/\.desktop$/i, "")
            const name = (identity.name || "").toLowerCase()
            if (desktopId === cleanTarget || rawAppId === cleanTarget || name === cleanTarget) {
                return true
            }
        }
        // Also check if running in tray
        const trayItems = SystemTray.items.values || []
        for (let t = 0; t < trayItems.length; t++) {
            const item = trayItems[t]
            if (!item) continue
            const friendly = (SysTrayIdentityService.friendlyName(item) || "").toLowerCase()
            const itemId = (item.id || "").toLowerCase()
            const itemTitle = (item.title || "").toLowerCase()
            if ((friendly && matchesApp(friendly, cleanTarget)) ||
                (itemId && matchesApp(itemId, cleanTarget)) ||
                (itemTitle && matchesApp(itemTitle, cleanTarget))) {
                return true
            }
        }
        return false
    }

    function openNotification(notifId, appName, desktopEntry, actionIdentifier) {
        const targetId = (desktopEntry || appName || "").trim()

        // Deliver the original message/action ID before raising the existing
        // client. Some clients handle ActionInvoked without raising their
        // window under Wayland, so the callback alone is not enough to view it.
        if (invokeNotificationAction(notifId, appName, desktopEntry, actionIdentifier)) {
            activateAppWindow(targetId)
            return true
        }

        // 2. Try to activate the window if the app is already running in KWin
        if (targetId.length > 0) {
            const windowActivated = activateAppWindow(targetId)
            if (windowActivated) {
                const live = _liveNotifications[notifId]
                if (live && groupService) groupService.hideNotification(live)
                return true
            }

            // 3. Fallback: ONLY launch if the app is NOT already running
            // Never launch a new process for an already running app like QQ/WeChat
            // Chat notifications never start a second client/login window.
            if (ControlCenterService.notificationCategory(appName, desktopEntry) !== "其他") return false
            if (!isAppRunning(targetId)) {
                if (AppActionService.launchById(targetId, [])) return true
                if (!targetId.endsWith(".desktop"))
                    return AppActionService.launchById(targetId + ".desktop", [])
            }
        }
        return false
    }

    function removeHistoryById(notifId) {
        const live = _liveNotifications[notifId] || _liveNotifications[String(notifId)]
        if (live && typeof live.dismiss === "function") {
            try { live.dismiss() } catch (e) {}
        }
        unregisterLiveNotification(notifId)
        for (let i = 0; i < notificationHistory.count; ++i) {
            if (notificationHistory.get(i).notifId === notifId) {
                notificationHistory.remove(i)
                return
            }
        }
    }

    function clearAllNotifications() {
        for (let i = 0; i < notificationHistory.count; ++i) {
            const notifId = notificationHistory.get(i).notifId
            const live = _liveNotifications[notifId] || _liveNotifications[String(notifId)]
            if (live && typeof live.dismiss === "function") {
                try { live.dismiss() } catch (e) {}
            }
        }
        _liveNotifications = ({})
        notificationHistory.clear()
        AppNotificationService.clearAll()
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
        refreshKeepAwake()
        refreshAudioApplications()
        if (anyPanelOpen) refreshAudioOutputs()
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
                brightnessDisplays = Array.isArray(value.displays) ? value.displays : []
                brightnessPrimaryDisplayId = value.displayId || ""
            } else {
                brightnessAvailable = false
                brightnessBacklightName = ""
                brightnessDisplays = []
                brightnessPrimaryDisplayId = ""
            }
        })
        PlatformClient.request("nightlight.get", {}, function(response) {
            if (response?.ok) {
                const value = response.result || ({})
                nightLightAvailable = value.available !== false
                if (!nightLightChangeInProgress) {
                    nightLightEnabled = !!value.enabled
                    nightLightActive = !!value.running
                }
            }
        })
    }

    function refreshKeepAwake() {
        if (!PlatformClient.supports("keepawake")) {
            keepAwakeAvailable = false
            keepAwakeEnabled = false
            return
        }
        PlatformClient.request("keepawake.get", {}, function(response) {
            if (response?.ok) {
                keepAwakeAvailable = !!response.result?.available
                if (!keepAwakeChangeInProgress)
                    keepAwakeEnabled = !!response.result?.enabled
            } else {
                keepAwakeAvailable = false
            }
        })
    }

    function toggleKeepAwake() {
        if (keepAwakeChangeInProgress || !keepAwakeAvailable)
            return false
        keepAwakeChangeInProgress = true
        keepAwakeError = ""
        PlatformClient.request("keepawake.set", { enabled: !keepAwakeEnabled }, function(response) {
            keepAwakeChangeInProgress = false
            if (response?.ok) {
                keepAwakeEnabled = !!response.result?.enabled
                keepAwakeAvailable = !!response.result?.available
            } else {
                keepAwakeError = response?.error?.message || "保持唤醒切换失败"
                refreshKeepAwake()
            }
        })
        return true
    }

    function refreshAudioApplications() {
        if (audioApplicationsRefreshInProgress)
            return
        audioApplicationsRefreshInProgress = true
        PlatformClient.request("audio.applications", {}, function(response) {
            audioApplicationsRefreshInProgress = false
            if (response?.ok) {
                const value = response.result || ({})
                audioApplicationsAvailable = value.available !== false
                audioApplications = Array.isArray(value.applications) ? value.applications : []
            } else {
                audioApplicationsAvailable = false
                audioApplications = []
            }
        })
    }

    function refreshAudioOutputs() {
        if (audioOutputsRefreshInProgress || audioOutputChangeInProgress) return
        audioOutputsRefreshInProgress = true
        PlatformClient.request("audio.outputs", {}, function(response) {
            audioOutputsRefreshInProgress = false
            if (response?.ok) {
                audioOutputs = response.result?.outputs || []
                _audioOutputReadError = ""
            } else {
                audioOutputs = []
                _audioOutputReadError = response?.error?.message || "无法读取输出设备"
            }
        })
    }

    function retryAudioOutputs() {
        _audioOutputChangeError = ""
        _audioOutputReadError = ""
        refreshAudioOutputs()
    }

    function setAudioOutput(name) {
        if (audioOutputChangeInProgress || audioOutputsRefreshInProgress) return
        audioOutputChangeInProgress = true
        _audioOutputChangeError = ""
        PlatformClient.request("audio.output.set-default", { name: name }, function(response) {
            audioOutputChangeInProgress = false
            if (!response?.ok)
                _audioOutputChangeError = response?.error?.message || "切换输出设备失败"
            refreshAudioOutputs()
            refresh()
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

    function setApplicationVolume(id, percent) {
        const value = Math.round(Math.max(0, Math.min(150, Number(percent) || 0)))
        PlatformClient.request("audio.application.set-volume", { id: id, percent: value }, function(response) {
            if (response?.ok)
                refreshAudioApplications()
        })
        return true
    }

    function setApplicationMuted(id, muted) {
        PlatformClient.request("audio.application.set-mute", { id: id, muted: !!muted }, function(response) {
            if (response?.ok)
                refreshAudioApplications()
        })
        return true
    }

    function setBrightness(percent) {
        if (brightnessPrimaryDisplayId)
            return setDisplayBrightness(brightnessPrimaryDisplayId, percent)
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

    function setDisplayBrightness(displayId, percent) {
        const id = String(displayId || "")
        const value = Math.round(Math.max(0, Math.min(100, Number(percent) || 0)))
        if (!id || !brightnessAvailable || brightnessChangeInProgress)
            return false
        brightnessChangeInProgress = true
        PlatformClient.request("display.brightness.set", { displayId: id, percent: value }, function(response) {
            brightnessChangeInProgress = false
            if (response?.ok) {
                const updated = brightnessDisplays.map(function(display) {
                    if (display.id !== id)
                        return display
                    return Object.assign({}, display, { percent: value })
                })
                brightnessDisplays = updated
                if (updated.length > 0) {
                    // 主读数跟"被调节的那块屏"：外接屏行调节后回写
                    // displays[0] 会让滑条预览跳到 1 号屏的值（审计 🟡）
                    let primary = updated[0]
                    for (let i = 0; i < updated.length; i++) {
                        if (updated[i].id === brightnessPrimaryDisplayId) {
                            primary = updated[i]
                            break
                        }
                    }
                    brightnessPercent = Number(primary.percent || 0)
                    brightnessBacklightName = primary.label || primary.id || ""
                }
            }
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
    // Locking goes through the session, like every other action here.
    //
    // It used to stay in-process, on the argument that `loginctl lock-session`
    // would put the Plasma greeter on top of the shell's own lock surface and
    // leave two locks to get past. The shell's lock surface is gone: the skin
    // under apps/lockscreen is the Plasma shell package now, so the greeter
    // *is* the lock screen and there is nothing left to stack it on.
    //
    // It is also the only locking the compositor knows about. An in-process
    // overlay is just a window -- a very large, very convincing one, with a
    // real PAM conversation behind it, that the compositor will happily route
    // global shortcuts past and drop when the process dies.
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

    function toggleNightLight() {
        if (!nightLightAvailable || nightLightChangeInProgress)
            return false
        nightLightChangeInProgress = true
        const requestedEnabled = !nightLightEnabled
        const previousEnabled = nightLightEnabled
        const previousActive = nightLightActive
        nightLightEnabled = requestedEnabled
        nightLightActive = requestedEnabled
        PlatformClient.request("nightlight.toggle", { enabled: requestedEnabled }, function(response) {
            nightLightChangeInProgress = false
            if (response?.ok) {
                nightLightEnabled = !!response.result?.enabled
                nightLightActive = !!response.result?.running
            } else {
                nightLightEnabled = previousEnabled
                nightLightActive = previousActive
                const message = response?.error?.message || "夜灯切换失败"
                console.warn("[ControlCenter] nightlight.toggle failed: " + message)
                lastSessionError = message
            }
        })
        return true
    }

    property Timer refreshTimer: Timer {
        interval: service.anyPanelOpen ? 3000 : 120000
        repeat: true
        running: PlatformClient.socket.connected
        onTriggered: service.refresh()
    }
    // The per-application mixer list is only visible inside the control
    // centre, so it gets no floor of its own; refresh() repopulates it on
    // open and on each slow fallback tick.
    property Timer audioApplicationsTimer: Timer {
        interval: 1800
        repeat: true
        running: PlatformClient.socket.connected && service.anyPanelOpen
        onTriggered: {
            service.refreshAudioApplications()
            service.refreshAudioOutputs()
        }
    }
    property Connections platformTransport: Connections {
        target: PlatformClient
        function onCapabilitiesChanged() { service.refreshKeepAwake() }
        function onTransportChanged(connected) {
            if (connected) {
                service.refresh()
            } else {
                // The client fails every outstanding callback on disconnect,
                // which already clears these; reset defensively so no tile or
                // session button can stay wedged by a lost response.
                audioOutputsRefreshInProgress = false
                audioOutputChangeInProgress = false
                audioOutputs = []
                _audioOutputReadError = "音频服务已断开"
                audioApplicationsRefreshInProgress = false
                volumeChangeInProgress = false
                brightnessChangeInProgress = false
                bluetoothChangeInProgress = false
                bluetoothDevicesRefreshInProgress = false
                bluetoothDeviceChangeInProgress = false
                bluetoothChangingAddress = ""
                screenshotInProgress = false
                sessionActionInProgress = false
                themeChangeInProgress = false
                keepAwakeChangeInProgress = false
                keepAwakeAvailable = false
                keepAwakeEnabled = false
                keepAwakeError = ""
                nightLightChangeInProgress = false
                _bluetoothPollTimer.stop()
            }
        }
    }
    Component.onCompleted: refresh()
}
