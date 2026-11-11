pragma Singleton

import QtQuick
import Quickshell
import Kos.SurfaceShape 1.0
import qs.desktop.modules.dock
import qs.desktop.modules.applauncher
import qs.desktop.modules.wallpaper

Scope {
    id: reveal

    property real progress: 0
    property bool loaded: false
    property bool started: false
    readonly property bool active: progress < 1
    readonly property string phase: !active ? "done" : !started ? "idle"
        : progress < 0.25 ? "fading" : progress < 0.45 ? "bar"
        : progress < 0.70 ? "dock" : "icons"
    readonly property real wallpaperProgress: segment(0, 0.25)
    readonly property real barProgress: ease(segment(0.25, 0.50))
    readonly property real dockProgress: segment(0.45, 0.78)
    readonly property real dockOffset: {
        const t = dockProgress - 1
        return 1 - (1 + 2.2 * t * t * t + 1.2 * t * t)
    }
    readonly property bool ready: loaded && AppearanceConfigService.ready
        && ConfigService.ready && ScreenLifecycle.outputAvailable
        && (!WallpaperService.takeoverEnabled || WallpaperService.allOutputsReady())

    function segment(start, end) {
        return Math.max(0, Math.min(1, (progress - start) / (end - start)))
    }
    function ease(t) { return 1 - Math.pow(1 - t, 3) }
    function iconProgress(index, count) {
        const delay = Math.max(0, index) / Math.max(1, count - 1) * 0.12
        return ease(segment(0.70 + delay, 0.88 + delay))
    }
    function initialize() {} // Force singleton construction before configuration completion.
    function finish() {
        timeline.stop()
        progress = 1
        watchdog.stop()
    }
    function begin() {
        if (!active || started || !ready)
            return
        if (AppearanceConfigService.reduceMotion) {
            finish()
            return
        }
        started = true
        timeline.start()
    }
    onReadyChanged: if (ready) Qt.callLater(begin)
    onPhaseChanged: console.info("[StartupReveal] " + phase)

    NumberAnimation {
        id: timeline
        target: reveal
        property: "progress"
        from: 0
        to: 1
        duration: AppearanceConfigService.startupRevealDuration
        easing.type: Easing.Linear
    }
    // A missing wallpaper/output/config must never leave a hidden desktop.
    Timer {
        id: watchdog
        interval: 1200
        onTriggered: reveal.finish()
    }
    StartupInputMonitor {
        active: reveal.active
        onActivity: reveal.finish()
    }
    Connections {
        target: Quickshell
        function onReloadCompleted() {
            reveal.loaded = true
            watchdog.start()
            Qt.callLater(reveal.begin)
        }
    }
    Connections {
        target: AppearanceConfigService
        function onReduceMotionChanged() {
            if (AppearanceConfigService.reduceMotion) reveal.finish()
        }
    }
    Connections {
        target: AppLauncherService
        function onOpenChanged() { if (AppLauncherService.open) reveal.finish() }
    }
}
