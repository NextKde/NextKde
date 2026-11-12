import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import "../../../Kos/Ui"
import "ThemeWallpaperPolicy.mjs" as Policy

// Both wallpaper modes wait for five uninterrupted seconds on an empty
// desktop. Pointer movement remains available once that wait has completed.
QtObject {
    id: root
    property bool enabled: false
    property bool preview: false
    property bool locked: false
    property bool lockPollPending: false
    readonly property bool hasVisibleWindows: {
        const revision = WindowService.revision + WindowService.placementRevision
        return Policy.hasVisibleWindows(WindowService.records, WindowService.currentDesktopId)
    }
    readonly property bool idleEligible: enabled && !preview && !locked
        && !AppTheme.reduceMotion && ScreenLifecycle.outputAvailable
        && WindowService.providerReady && !hasVisibleWindows
    property bool idleReady: false
    readonly property bool running: enabled && !locked && ScreenLifecycle.outputAvailable
        && (preview || idleEligible && idleReady)

    function rearmIdle() {
        idleReady = false
        if (!idleDelay) return
        idleDelay.stop()
        if (idleEligible) idleDelay.start()
    }
    property Timer idleDelay: Timer {
        interval: 5000
        repeat: false
        onTriggered: if (root.idleEligible) root.idleReady = true
    }
    property Connections desktopChanges: Connections {
        target: WindowService
        function onCurrentDesktopIdChanged() { root.rearmIdle() }
    }

    function pollLock() {
        if (lockPollPending || !PlatformClient.supports("session.visibility")) return
        lockPollPending = true
        PlatformClient.request("session.visibility", {}, response => {
            lockPollPending = false
            if (response?.ok) locked = !!response.result.locked
        })
    }
    property Timer lockState: Timer {
        interval: 5000
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: root.pollLock()
    }
    onIdleEligibleChanged: rearmIdle()
    Component.onCompleted: rearmIdle()
}
