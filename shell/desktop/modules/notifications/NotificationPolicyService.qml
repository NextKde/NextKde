pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform
import "NotificationIdentity.mjs" as NotificationIdentity

// Per-source policy persists independently of session-only notification history.
QtObject {
    id: service
    readonly property string configPath: Quickshell.stateDir + "/notifications/config.json"
    property bool ready: false
    property var sources: []
    property var blockedKeys: []
    property string saveError: ""

    function sourceKey(notification) { return NotificationIdentity.sourceKey(notification) }
    function isBlocked(notification) { return isKeyBlocked(sourceKey(notification)) }
    function isKeyBlocked(key) { return blockedKeys.indexOf(key) >= 0 }
    function remember(notification) {
        const key = sourceKey(notification)
        const source = { key: key, desktopEntry: String(notification.desktopEntry || ""),
            appName: String(notification.appName || notification.desktopEntry || "其他"),
            appIcon: String(notification.appIcon || "") }
        const next = sources.slice()
        const index = next.findIndex(value => value.key === key)
        if (index >= 0 && JSON.stringify(next[index]) === JSON.stringify(source)) return
        if (index >= 0) next[index] = source
        else next.push(source)
        sources = next
        saveTimer.restart()
    }
    function setBlocked(key, blocked) {
        if (!ready || !sources.some(source => source.key === key)) return
        const next = blockedKeys.filter(value => value !== key)
        if (blocked) next.push(key)
        blockedKeys = next
        saveTimer.restart()
    }
    property Timer saveTimer: Timer {
        interval: 150
        onTriggered: service.save()
    }
    function save() {
        if (!ready) return
        JsonConfigStore.writePath(configPath, JSON.stringify({version: 1, sources: sources,
            blockedKeys: blockedKeys}, null, 2), function(ok) {
                service.saveError = ok ? "" : "通知设置保存失败"
            })
    }
    Component.onCompleted: JsonConfigStore.readPath(configPath, function(data, exists) {
        if (exists && data) {
            try {
                const parsed = JSON.parse(data)
                if (Array.isArray(parsed.sources)) {
                    const seen = new Set()
                    service.sources = parsed.sources.filter(source => source
                        && typeof source.key === "string"
                        && /^(desktop:|name:).+/.test(source.key)
                        && !seen.has(source.key) && (seen.add(source.key), true))
                        .map(source => ({key: source.key,
                            desktopEntry: String(source.desktopEntry || ""),
                            appName: String(source.appName || source.desktopEntry || "其他"),
                            appIcon: String(source.appIcon || "")}))
                }
                if (Array.isArray(parsed.blockedKeys))
                    service.blockedKeys = [...new Set(parsed.blockedKeys.filter(key =>
                        service.sources.some(source => source.key === key)))]
            } catch (error) {
                console.warn("[Notifications] invalid policy: " + error)
            }
        }
        service.ready = true
    })
}
