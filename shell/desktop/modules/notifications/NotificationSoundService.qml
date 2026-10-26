pragma Singleton
import QtQuick
import qs.desktop.modules.notifications

QtObject {
    id: service
    property double lastPlayTime: 0

    // Default-off profiles never load QtMultimedia. Missing optional runtimes
    // disable only sound, even if the user explicitly enables the preference.
    property Loader backend: Loader {
        active: NotificationPolicyService.ready && NotificationPolicyService.soundEnabled
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
    function play(notification) {
        if (!notification || startupGuard.running || !NotificationPolicyService.ready
                || !NotificationPolicyService.soundEnabled
                || NotificationPolicyService.doNotDisturbEnabled
                || NotificationPolicyService.isBlocked(notification)) return
        const hints = notification.hints || ({})
        if (hints["suppress-sound"] === true || hints["suppress-sound"] === 1) return
        if (!backend.item || backend.item.busy) return

        // A bounded global cooldown coalesces bursts without an ever-growing
        // identity cache or a permanent ban on the last notification key.
        const now = Date.now()
        if (now - lastPlayTime < 600) return
        if (backend.item.play()) lastPlayTime = now
    }
}
