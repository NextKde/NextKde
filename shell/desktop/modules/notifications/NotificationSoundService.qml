pragma Singleton
import QtQuick
import qs.desktop.modules.notifications

QtObject {
    id: service

    property double lastPlayTime: 0
    property string lastKey: ""
    readonly property string qqSoundPath: "/opt/QQ/resources/app/resource/msg.wav"
    readonly property string defaultSoundPath: "/usr/share/sounds/ocean/stereo/message-new-instant.oga"
    readonly property string fallbackSoundPath: "/usr/share/sounds/freedesktop/stereo/message.oga"

    // Keep QtMultimedia optional: a missing runtime must not take down the UI.
    property Loader backend: Loader {
        source: Qt.resolvedUrl("NotificationAudioPlayer.qml")
        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("[NotificationSoundService] QtMultimedia backend unavailable")
        }
    }
    property Timer startupGuard: Timer { interval: 2000; running: true }
    property Connections policy: Connections {
        target: NotificationPolicyService
        function onDoNotDisturbEnabledChanged() {
            if (NotificationPolicyService.doNotDisturbEnabled && service.backend.item)
                service.backend.item.cancel()
        }
    }

    function fileUrl(path) {
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
    }

    function play(notification) {
        if (!notification) return
        if (startupGuard.running) {
            console.info("[NotificationSoundService] sound suppressed by startup guard")
            return
        }
        if (!NotificationPolicyService.ready
                || NotificationPolicyService.doNotDisturbEnabled
                || NotificationPolicyService.isBlocked(notification)) return
        const hints = notification.hints || ({})
        if (hints["suppress-sound"] === true || hints["suppress-sound"] === 1) return
        if (!backend.item) {
            console.warn("[NotificationSoundService] backend not ready")
            return
        }
        if (backend.item.busy) return

        const desktopEntry = String(notification.desktopEntry || "").toLowerCase()
        const appName = String(notification.appName || "").toLowerCase()
        const key = [desktopEntry, appName, notification.id || "",
            notification.summary || "", notification.body || ""].join("\n")
        const now = Date.now()
        if (key === lastKey || now - lastPlayTime < 600) return

        let soundPath = defaultSoundPath
        if (["qq", "qq.desktop", "linuxqq", "com.qq.qq"].indexOf(desktopEntry) >= 0
                || appName === "qq" || appName === "腾讯qq") {
            soundPath = qqSoundPath
        } else if (typeof hints["sound-file"] === "string" && hints["sound-file"]) {
            soundPath = hints["sound-file"]
        } else if (typeof hints["sound-name"] === "string"
                && /^[a-zA-Z0-9_-]+$/.test(hints["sound-name"])) {
            soundPath = "/usr/share/sounds/ocean/stereo/" + hints["sound-name"] + ".oga"
        }
        // Only local files are notification sounds; never fetch notification URLs.
        if (soundPath.indexOf("file://") === 0) {
            try { soundPath = decodeURIComponent(soundPath.slice(7)) }
            catch (error) { soundPath = defaultSoundPath }
        }
        if (soundPath.charAt(0) !== "/") soundPath = defaultSoundPath
        const fallbacks = [defaultSoundPath, fallbackSoundPath]
            .filter(path => path !== soundPath).map(fileUrl)
        if (backend.item.play(fileUrl(soundPath), fallbacks)) {
            lastKey = key
            lastPlayTime = now
            console.info("[NotificationSoundService] prewarming then playing "
                + soundPath + " for " + (desktopEntry || appName))
        }
    }
}
