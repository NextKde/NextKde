pragma Singleton

import QtQuick
import Quickshell
// StartupInputMonitor (the frame gate at the bottom of this file) lives here,
// not in Quickshell or the desktop modules. Removing this import breaks the
// whole shell configuration.
import Kos.SurfaceShape 1.0
import qs.desktop.modules.dock
import qs.desktop.modules.applauncher
import qs.desktop.modules.wallpaper

Scope {
    id: reveal

    property real progress: 0
    property bool loaded: false
    property bool started: false
    property bool preparing: false
    property double startedAt: 0
    readonly property bool active: progress < 1
    readonly property string phase: !active ? "done" : !started ? "idle"
        : progress < 0.12 ? "fading" : progress < 0.38 ? "bar"
        : progress < 0.62 ? "dock" : "icons"
    // Warm-up: every surface is mapped but invisible behind the spinner. The
    // first paint of each window compiles its glass material and decodes its
    // icons; on a cold login that work landed exactly on top of the arrival
    // and froze the fade at a random opacity. Rendering at a sliver of
    // opacity lets the arrival start on an already-warm scene.
    property bool warmup: false
    property double warmupStartedAt: 0
    // Overlapping windows rather than strict phases: the bar leads, dock and
    // widgets drift in together, icons land last. Each one finishes before the
    // clock does, so the arrival settles instead of freezing on its final
    // frame, and the shared ease-in-out curve keeps entries from starting with
    // a visible kick.
    readonly property real barProgress: warmup ? 0.004 : smooth(segment(0.05, 0.45))
    readonly property real dockProgress: warmup ? 0.004 : smooth(segment(0.22, 0.80))
    readonly property real widgetProgress: warmup ? 0.004 : smooth(segment(0.30, 0.82))
    readonly property real dockOffset: warmup ? 1 : 1 - smooth(segment(0.22, 0.88))
    readonly property bool ready: loaded && AppearanceConfigService.ready
        && ConfigService.ready && ScreenLifecycle.outputAvailable
        && (!WallpaperService.takeoverEnabled || WallpaperService.allOutputsReady())

    function segment(start, end) {
        return Math.max(0, Math.min(1, (progress - start) / (end - start)))
    }
    // Ease-in-out cubic: the same curve in both directions reads as one slow
    // arrival rather than a snap followed by a settle.
    function smooth(t) {
        return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2
    }
    function iconProgress(index, count) {
        if (!active) return 1
        if (warmup) return 0.004
        const delay = Math.max(0, index) / Math.max(1, count - 1) * 0.12
        return smooth(segment(0.55 + delay, 0.92 + delay))
    }
    function initialize() {
        // reloadCompleted is emitted for reloads, not the first configuration.
        // callLater runs after construction of the complete desktop object tree.
        Qt.callLater(configurationLoaded)
    }
    function configurationLoaded() {
        if (loaded) return
        loaded = true
        watchdog.start()
        Qt.callLater(begin)
    }
    function finish() {
        timeline.stop()
        settle.stop()
        warmup = false
        progress = 1
        watchdog.stop()
    }
    function begin() {
        if (!active || started || warmup || preparing || !ready)
            return
        if (AppearanceConfigService.reduceMotion) {
            finish()
            return
        }
        preparing = true
        inputMonitor.prepareFrame()
    }
    function startTimeline() {
        preparing = false
        if (!active || started || warmup) return
        if (!ready) {
            begin()
            return
        }
        // The first frame is prepared; keep the spinner up and let the rest of
        // the scene paint before the arrival begins.
        watchdog.stop()
        warmup = true
        warmupStartedAt = Date.now()
        console.info("[StartupReveal] warmup")
        armSettle()
    }
    function armSettle() {
        settle.lastTick = 0
        settle.calm = 0
        settle.start()
    }
    // Two handovers. The first waits for every window to paint once behind the
    // spinner. The second runs after the spinner is gone: the compositor only
    // starts painting the layers the spinner was covering at that point, and on
    // a slow machine that is one very long frame. The fade must not be running
    // through it, so it waits for the thread to go quiet again.
    function land() {
        settle.stop()
        if (!started) {
            started = true
            warmupStartedAt = Date.now()
            armSettle()
            return
        }
        warmup = false
        startedAt = Date.now()
        timeline.lastTick = 0
        timeline.start()
    }
    onReadyChanged: if (ready) Qt.callLater(begin)
    onPhaseChanged: console.info("[StartupReveal] " + phase)

    // Watches the GUI thread while the warm-up scene paints. About twelve
    // quiet ticks (200ms without a stall) mean the login's remaining work is
    // done; the cap keeps a permanently busy machine from leaving the spinner
    // up forever.
    Timer {
        id: settle
        interval: 16
        repeat: true
        property double lastTick: 0
        property int calm: 0
        onTriggered: {
            const now = Date.now()
            if (lastTick > 0)
                calm = now - lastTick <= 24 ? calm + 1 : 0
            lastTick = now
            if (calm >= 12 || now - reveal.warmupStartedAt > 2500)
                reveal.land()
        }
    }

    Timer {
        id: timeline
        interval: 16
        repeat: true
        property double lastTick: 0
        onTriggered: {
            const now = Date.now()
            // At most one display frame of progress per tick: the login is
            // still loading windows, shaders and the wallpaper in the
            // background, and a half-second stall used to jump the arrival
            // straight to its last frame. A stalled arrival may now run past
            // the configured duration; the wall clock below still ends it
            // rather than leaving the desktop half-transparent.
            const step = Math.min(48, now - (lastTick || reveal.startedAt))
            lastTick = now
            reveal.progress = Math.min(1, reveal.progress
                + step / AppearanceConfigService.startupRevealDuration)
            // The safety cap is deliberately loose: a busy login can hold the
            // GUI thread for a couple of seconds while the first glass frames
            // compile, and the arrival should resume from where it was rather
            // than being cut to its last frame. Only a genuinely wedged shell
            // skips the rest.
            if (reveal.progress >= 1 || now - reveal.startedAt > 8000)
                reveal.finish()
        }
    }
    // A missing wallpaper/output/config must never leave a hidden desktop.
    Timer {
        id: watchdog
        interval: 1200
        onTriggered: reveal.finish()
    }
    StartupInputMonitor {
        id: inputMonitor
        active: reveal.loaded && reveal.active
        onActivity: reveal.finish()
        onFramePrepared: reveal.startTimeline()
    }
    Connections {
        target: Quickshell
        function onReloadCompleted() { reveal.configurationLoaded() }
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
