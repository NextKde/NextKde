import QtQuick
import qs.desktop.modules.platform
import "LockScreenNotificationSnapshot.mjs" as Snapshot

// Optional publisher only. The platform daemon owns the read-only D-Bus name;
// this component never creates another org.freedesktop.Notifications server.
QtObject {
    id: bridge
    required property var historyService
    required property var policyService
    property var transport: PlatformClient
    readonly property bool available: transport.connected
        && transport.supports("lockscreen.notifications-publish")
    property bool warned: false

    function publish() {
        if (!available) return
        // PlatformClient treats this as a write: disconnected updates are NOT
        // queued/replayed. Every reconnect sends a fresh session snapshot.
        transport.request("lockscreen.notifications-publish", {
            notifications: Snapshot.snapshot(historyService.history, policyService)
        }, function(response) {
            if (!response?.ok && !warned) {
                warned = true
                console.warn("[Notifications] lock-screen privacy bridge unavailable")
            } else if (response?.ok) warned = false
        })
    }
    function schedule() { updateTimer.restart() }
    property Timer updateTimer: Timer { interval: 0; onTriggered: bridge.publish() }
    // A crashed/hung shell cannot leave stale data indefinitely in the daemon.
    // The daemon's 30s lease is renewed even when session history is unchanged.
    property Timer heartbeat: Timer {
        interval: 10000
        repeat: true
        running: bridge.available
        onTriggered: bridge.publish()
    }
    property Connections historyChanges: Connections {
        target: bridge.historyService
        function onHistoryUpdated() { bridge.schedule() }
    }
    property Connections policyChanges: Connections {
        target: bridge.policyService
        function onReadyChanged() { bridge.schedule() }
        function onHistoryEnabledChanged() { bridge.schedule() }
        function onDoNotDisturbEnabledChanged() { bridge.schedule() }
        function onBlockedKeysChanged() { bridge.schedule() }
    }
    onAvailableChanged: if (available) schedule()
    Component.onCompleted: schedule()
}
