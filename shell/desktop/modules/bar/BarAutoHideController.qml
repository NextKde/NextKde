import QtQuick
import Quickshell
import qs.desktop.modules.dock
import "../dock/DockAutoHideMath.mjs" as DockMath

// ────────────────────────────────────────────────────────────────
// BarAutoHideController — per-surface show/hide state machine for top Bar.
//
// One instance lives in each concrete BarWindow, so multi-screen setups
// get an independent controller per screen. It owns the reveal progress,
// the delay timers and the reveal animation, and derives all visual
// offsets/opacities from that single progress value.
//
// Collision judgement always uses the static rectangle the Bar occupies
// at full reveal — never the animated transform.
// ────────────────────────────────────────────────────────────────

Item {
    id: ctl

    // ────────────────────────────────────────────────────────────
    // Inputs (wired by BarWindow)
    // ────────────────────────────────────────────────────────────
    property string mode: "always"          // "always" | "smart" | "persistent"
    property bool configReady: false
    property bool windowDataReady: false
    property var targetScreen: null          // Quickshell ShellScreen
    property real barHeight: 35
    property real edgeMargin: 15
    property bool pointerInsideBar: false
    property bool popupOpen: false
    property bool launcherOpen: false

    // ────────────────────────────────────────────────────────────
    // Outputs
    // ────────────────────────────────────────────────────────────
    property string phase: "Bootstrapping"
    property real revealProgress: 0.0
    readonly property bool hidden: ctl.phase === "Hidden"
    // Reserve as soon as reveal begins, keep the reservation throughout the
    // hide animation, and release it only at the Hidden boundary. This avoids
    // resizing maximized windows on every animation frame.
    readonly property bool workspaceReserved: ctl.mode === "always"
        || (ctl.phase !== "Bootstrapping" && ctl.phase !== "Hidden"
            && ctl.phase !== "RevealPending")
    readonly property bool handleActive: ctl.mode !== "always"
    property bool hasWindowConflict: false
    readonly property bool policyWantsHidden:
        DockMath.policyWantsHidden(ctl.mode, ctl.hasWindowConflict)
    readonly property bool hasInhibitor:
        ctl.pointerInsideBar || ctl.popupOpen || ctl.launcherOpen
        || ctl._temporaryRevealHold || ctl._handleHovered

    readonly property real offsetY: -(1 - ctl.revealProgress) * (ctl.barHeight + 2)
    readonly property real barOpacity: Math.max(0.0, Math.min(1.0, ctl.revealProgress))

    property bool _temporaryRevealHold: false
    property bool _handleHovered: false
    property bool _persistentGraceUsed: false

    function _targetRect() {
        const s = ctl.targetScreen
        if (!s || s.x === undefined || s.width === undefined)
            return { x: 0, y: 0, width: 1, height: 1 }
        return { x: s.x, y: s.y, width: s.width, height: s.height }
    }

    function _windowCandidates() {
        const recs = WindowService.records || []
        const out = []
        for (let i = 0; i < recs.length; i++) {
            const r = recs[i]
            if (!r || !r.geometry)
                continue
            out.push({
                geometry: r.geometry,
                screenName: r.screenName || "",
                isMinimized: !!r.toplevel?.minimized || r.isVisible === false,
                isFullscreen: !!r.toplevel?.fullscreen,
                isMaximized: !!r.isMaximized,
                isVisible: r.isVisible !== false,
                onAllDesktops: !!r.onAllDesktops,
                desktopIds: Array.isArray(r.desktopIds) ? r.desktopIds : []
            })
        }
        return out
    }

    function _recomputeConflict() {
        if (!ctl.windowDataReady || ctl.barHeight <= 0) {
            const changed = ctl.hasWindowConflict
            ctl.hasWindowConflict = false
            return changed
        }
        const target = ctl._targetRect()
        const barWidth = target.width > ctl.edgeMargin * 2
            ? target.width - ctl.edgeMargin * 2 : target.width
        const base = DockMath.visibleDockRect(target, "top",
            barWidth, ctl.barHeight, ctl.edgeMargin)
        const cands = ctl._windowCandidates()
        const next = DockMath.hasConflict(cands, target,
            base, base,
            ctl.hasWindowConflict, WindowService.currentDesktopId, true)
        const changed = next !== ctl.hasWindowConflict
        if (changed)
            ctl.hasWindowConflict = next
        return changed
    }

    // ────────────────────────────────────────────────────────────
    // Timers
    // ────────────────────────────────────────────────────────────
    property Timer _evaluateTimer: Timer {
        interval: 80
        repeat: false
        onTriggered: ctl._doEvaluate()
    }
    property Timer _hidePendingTimer: Timer {
        repeat: false
        onTriggered: ctl._enterHiding()
    }
    property Timer _revealDelayTimer: Timer {
        interval: DockAnimation.smartHideHoverShowDelay
        repeat: false
        onTriggered: ctl._animateTo(1)
    }
    property Timer _tempHoldTimer: Timer {
        repeat: false
        onTriggered: {
            ctl._temporaryRevealHold = false
            ctl._scheduleEvaluate()
        }
    }
    property Timer _bootTimeout: Timer {
        interval: DockAnimation.smartHideBootWaitLimit
        repeat: false
        onTriggered: ctl._tryResolveBoot(true)
    }

    function _scheduleEvaluate() { ctl._evaluateTimer.restart() }

    // ────────────────────────────────────────────────────────────
    // Animation — a single NumberAnimation on revealProgress
    // ────────────────────────────────────────────────────────────
    property int _animTarget: 1
    property NumberAnimation _anim: NumberAnimation {
        target: ctl
        property: "revealProgress"
        onFinished: ctl._onAnimationFinished()
    }

    function _animateTo(target) {
        if (target === ctl.revealProgress)
            return
        ctl._animTarget = target
        ctl._anim.stop()
        const distance = Math.abs(target - ctl.revealProgress)
        const full = target > ctl.revealProgress
            ? DockAnimation.smartHideRevealDuration
            : DockAnimation.smartHideHideDuration
        ctl._anim.from = ctl.revealProgress
        ctl._anim.to = target
        ctl._anim.duration = Math.max(DockAnimation.smartHideMinRemaining,
            Math.round(full * distance))
        ctl._anim.easing.type = target > ctl.revealProgress
            ? DockAnimation.smartHideRevealEasing
            : DockAnimation.smartHideHideEasing
        if (target > ctl.revealProgress)
            ctl._setPhase("Showing")
        else
            ctl._setPhase("Hiding")
        ctl._anim.start()
    }

    function _onAnimationFinished() {
        if (ctl._animTarget <= 0) {
            ctl._setPhase("Hidden")
            return
        }
        // Reached full reveal.
        if (ctl.policyWantsHidden && !ctl.hasInhibitor) {
            ctl._enterHidePending()
        } else if (ctl.policyWantsHidden) {
            ctl._setPhase("Held")
        } else {
            ctl._setPhase("Shown")
        }
    }

    // ────────────────────────────────────────────────────────────
    // Phase helpers
    // ────────────────────────────────────────────────────────────
    function _setPhase(next) {
        if (ctl.phase === next)
            return
        console.log("[BarAutoHide] " + ctl.phase + " -> " + next
            + " mode=" + ctl.mode + " conflict=" + ctl.hasWindowConflict
            + " inhibit=" + ctl.hasInhibitor)
        ctl.phase = next
    }

    function hideDelay() {
        if (ctl.mode === "persistent") {
            if (!ctl._persistentGraceUsed) {
                ctl._persistentGraceUsed = true
                return DockAnimation.smartHideModeSwitchGrace
            }
            return DockAnimation.smartHideLeaveDelay
        }
        return DockAnimation.smartHideConflictDelay
    }

    function _enterHidePending() {
        ctl._setPhase("HidePending")
        ctl._hidePendingTimer.interval = ctl.hideDelay()
        ctl._hidePendingTimer.stop()
        ctl._hidePendingTimer.start()
    }

    function _enterHiding() {
        ctl._setPhase("Hiding")
        ctl._animateTo(0)
    }

    function _enterShownOrHeld() {
        ctl._setPhase(ctl.policyWantsHidden ? "Held" : "Shown")
    }

    // ────────────────────────────────────────────────────────────
    // Bootstrapping — wait for config + (smart) window snapshot, and gate the
    // very first visibility so a persistent/smart bar never flashes fully
    // shown at startup.
    // ────────────────────────────────────────────────────────────
    function _tryResolveBoot(forced) {
        if (ctl.mode === "always") {
            ctl._enterAlwaysShown()
            return
        }
        if (!ctl.configReady && !forced) return
        if (ctl.mode === "smart" && !ctl.windowDataReady && !forced) return

        ctl._bootTimeout.stop()
        if (ctl.mode === "persistent") {
            ctl._persistentGraceUsed = true
            ctl.revealProgress = 0
            ctl._setPhase("Hidden")
            return
        }
        // smart
        ctl._recomputeConflict()
        if (ctl.hasWindowConflict) {
            ctl.revealProgress = 0
            ctl._setPhase("Hidden")
        } else {
            ctl._setPhase("Showing")
            ctl._animateTo(1)
        }
    }

    // ────────────────────────────────────────────────────────────
    // Main transition dispatch
    // ────────────────────────────────────────────────────────────
    function _doEvaluate() {
        if (ctl.mode === "always") {
            if (ctl.configReady && ctl.phase !== "Shown")
                ctl._enterAlwaysShown()
            return
        }
        switch (ctl.phase) {
        case "Bootstrapping":
            ctl._tryResolveBoot(false)
            return
        case "Shown":
        case "Held":
            if (!DockMath.shouldBeVisible(ctl.mode, ctl.hasWindowConflict, ctl.hasInhibitor)) {
                ctl._enterHidePending()
            } else if (ctl.phase === "Held" && !ctl.policyWantsHidden) {
                ctl._setPhase("Shown")
            }
            return
        case "HidePending":
            if (DockMath.shouldBeVisible(ctl.mode, ctl.hasWindowConflict, ctl.hasInhibitor)) {
                ctl._hidePendingTimer.stop()
                ctl._enterShownOrHeld()
            }
            return
        case "Hiding":
            if (DockMath.shouldBeVisible(ctl.mode, ctl.hasWindowConflict, ctl.hasInhibitor))
                ctl._animateTo(1)
            return
        case "Hidden":
            if (DockMath.shouldBeVisible(ctl.mode, ctl.hasWindowConflict, ctl.hasInhibitor)
                    && !ctl._handleHovered) {
                ctl._setPhase("Showing")
                ctl._animateTo(1)
            }
            return
        case "RevealPending":
            if (!ctl._handleHovered) {
                ctl._revealDelayTimer.stop()
                ctl._setPhase("Hidden")
            }
            return
        case "Showing":
            if (!ctl.hasInhibitor && ctl.policyWantsHidden)
                ctl._animateTo(0)
            return
        }
    }

    function _enterAlwaysShown() {
        ctl._hidePendingTimer.stop()
        ctl._revealDelayTimer.stop()
        ctl._tempHoldTimer.stop()
        ctl._anim.stop()
        ctl.revealProgress = 1
        ctl._setPhase("Shown")
    }

    // ────────────────────────────────────────────────────────────
    // Public methods
    // ────────────────────────────────────────────────────────────
    function handleEntered() {
        if (ctl.mode === "always" || !ctl.handleActive) return
        ctl._handleHovered = true
        if (ctl.phase === "Hidden") {
            ctl._setPhase("RevealPending")
            ctl._revealDelayTimer.restart()
        } else if (ctl.phase === "RevealPending") {
            ctl._revealDelayTimer.restart()
        }
    }

    function handleExited() {
        ctl._handleHovered = false
        ctl._revealDelayTimer.stop()
        if (ctl.phase === "RevealPending")
            ctl._setPhase("Hidden")
    }

    function handleClicked() {
        if (ctl.mode === "always" || !ctl.handleActive) return
        ctl._revealDelayTimer.stop()
        if (ctl.phase === "Hidden" || ctl.phase === "RevealPending"
                || ctl.revealProgress < 1) {
            ctl._setPhase("Showing")
            ctl._animateTo(1)
        }
    }

    function requestReveal(reason, holdMs) {
        if (ctl.mode === "always") return
        ctl._temporaryRevealHold = true
        ctl._tempHoldTimer.interval = holdMs || DockAnimation.smartHideLeaveDelay
        ctl._tempHoldTimer.restart()
        if (ctl.phase === "Hidden" || ctl.phase === "RevealPending"
                || ctl.revealProgress < 1) {
            ctl._setPhase("Showing")
            ctl._animateTo(1)
        }
    }

    function requestHideEvaluation(reason) { ctl._scheduleEvaluate() }

    function resetForScreenChange() {
        ctl._anim.stop()
        ctl._hidePendingTimer.stop()
        ctl._revealDelayTimer.stop()
        ctl._tempHoldTimer.stop()
        ctl._temporaryRevealHold = false
        ctl._handleHovered = false
        ctl.revealProgress = ctl.mode === "always" ? 1 : 0
        ctl._setPhase("Bootstrapping")
        ctl._bootTimeout.restart()
        ctl._recomputeConflict()
        ctl._tryResolveBoot(false)
    }

    // ────────────────────────────────────────────────────────────
    // Input plumbing
    // ────────────────────────────────────────────────────────────
    onModeChanged: { ctl._recomputeConflict(); ctl._scheduleEvaluate() }
    onTargetScreenChanged: { ctl._recomputeConflict(); ctl._scheduleEvaluate() }
    onBarHeightChanged: { ctl._recomputeConflict(); ctl._scheduleEvaluate() }
    onPointerInsideBarChanged: ctl._scheduleEvaluate()
    on_HandleHoveredChanged: ctl._scheduleEvaluate()
    onPopupOpenChanged: ctl._scheduleEvaluate()
    onLauncherOpenChanged: ctl._scheduleEvaluate()
    onConfigReadyChanged: ctl._tryResolveBoot(false)
    onWindowDataReadyChanged: { ctl._recomputeConflict(); ctl._scheduleEvaluate() }

    Connections {
        target: WindowService
        function onRevisionChanged() {
            if (ctl._recomputeConflict())
                ctl._doEvaluate()
            else if (ctl.mode !== "always")
                ctl._scheduleEvaluate()
        }
        function onCurrentDesktopIdChanged() {
            if (ctl._recomputeConflict())
                ctl._doEvaluate()
            else if (ctl.mode !== "always")
                ctl._scheduleEvaluate()
        }
    }

    Component.onCompleted: {
        ctl._bootTimeout.start()
        ctl._tryResolveBoot(false)
    }
}
