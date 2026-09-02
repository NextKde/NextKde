import QtQuick
import Quickshell
import qs.desktop.modules.dock
import "./DockAutoHideMath.mjs" as DockMath

// ────────────────────────────────────────────────────────────────
// DockAutoHideController — per-surface show/hide state machine.
//
// One ordinary (non-singleton) instance lives in each concrete DockWindow, so
// a multi-screen setup gets an independent controller per dock. It owns the
// reveal progress, the delay timers and the reveal animation, and derives all
// visual offsets/opacities from that single progress value. It never persists
// configuration, never creates windows and never touches icons.
//
// Collision judgement always uses the static rectangle the dock would occupy
// at full reveal — never the animated transform — see docs/DockArchitecture.md,
// "Visibility modes and auto-hide".
// ────────────────────────────────────────────────────────────────

Item {
    id: ctl

    // ────────────────────────────────────────────────────────────
    // Inputs (wired by DockWindow / DockContainer)
    // ────────────────────────────────────────────────────────────
    property string mode: "always"          // "always" | "smart" | "persistent"
    property bool configReady: false
    property bool windowDataReady: false
    property string position: "bottom"
    property var targetScreen: null          // Quickshell ShellScreen
    property real dockWidth: 0               // full-reveal container width
    property real dockHeight: 0
    property real edgeMargin: 5
    property bool pointerInsideDock: false
    property bool editing: false
    property bool dragging: false
    property bool popupOpen: false
    property bool launcherOpen: false

    // ────────────────────────────────────────────────────────────
    // Outputs
    // ────────────────────────────────────────────────────────────
    property string phase: "Bootstrapping"
    // Start hidden: the saved mode is only known after config loads, so a
    // persistent/smart dock must never flash fully shown during boot. The
    // boot-resolve step then reveals (or stays hidden) per the real mode.
    property real revealProgress: 0.0
    readonly property bool hidden: ctl.phase === "Hidden"
    readonly property bool handleActive: ctl.mode !== "always"
    property bool hasWindowConflict: false
    readonly property bool policyWantsHidden:
        DockMath.policyWantsHidden(ctl.mode, ctl.hasWindowConflict)
    readonly property bool hasInhibitor:
        ctl.pointerInsideDock || ctl.editing || ctl.dragging
        || ctl.popupOpen || ctl.launcherOpen || ctl._temporaryRevealHold
        // Hovering the reveal handle (the off-screen pill) counts as an
        // inhibitor too: a dock revealed by parking the cursor at the edge must
        // stay up while the cursor is still there, otherwise it re-hides the
        // instant the reveal animation ends and the user is forced to chase it
        // onto the glass before it disappears.
        || ctl._handleHovered

    readonly property real offsetX: ctl.position === "bottom" ? 0
        : (ctl.position === "left"
            ? -(1 - ctl.revealProgress) * (ctl.dockWidth + ctl.edgeMargin + 2)
            :  (1 - ctl.revealProgress) * (ctl.dockWidth + ctl.edgeMargin + 2))
    readonly property real offsetY: ctl.position === "bottom"
        ? (1 - ctl.revealProgress) * (ctl.dockHeight + ctl.edgeMargin + 2)
        : 0
    readonly property real dockOpacity: DockMath.dockOpacity(ctl.revealProgress)
    readonly property real dockScale: DockMath.dockScale(ctl.revealProgress)
    readonly property real handleOpacity: DockMath.handleOpacity(ctl.revealProgress)

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
                onAllDesktops: !!r.onAllDesktops,
                desktopIds: Array.isArray(r.desktopIds) ? r.desktopIds : []
            })
        }
        return out
    }

    function _recomputeConflict() {
        if (!ctl.windowDataReady || ctl.dockWidth <= 0 || ctl.dockHeight <= 0) {
            const changed = ctl.hasWindowConflict
            ctl.hasWindowConflict = false
            return changed
        }
        const target = ctl._targetRect()
        const base = DockMath.visibleDockRect(target, ctl.position,
            ctl.dockWidth, ctl.dockHeight, ctl.edgeMargin)
        const cands = ctl._windowCandidates()
        const next = DockMath.hasConflict(cands, target,
            DockMath.avoidanceRect(base), DockMath.releaseRect(base),
            ctl.hasWindowConflict, WindowService.currentDesktopId)
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
        console.log("[DockAutoHide] " + ctl.phase + " -> " + next
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

    function _enterHiding() { ctl._animateTo(0) }

    function _enterShownOrHeld() {
        ctl._setPhase(ctl.policyWantsHidden ? "Held" : "Shown")
    }

    // ────────────────────────────────────────────────────────────
    // Bootstrapping — wait for config + (smart) window snapshot, and gate the
    // very first visibility so a persistent/smart dock never flashes fully
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
            // Boot went straight to Hidden (not a runtime always→persistent
            // switch), so skip the 700ms confirmation grace for later leaves.
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
            // Only force-show once the saved mode is confirmed; during boot the
            // real mode may still be smart/persistent.
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
                // Conflict cleared (smart) or an inhibitor opened (popup /
                // launcher / urgent) — reveal; the handle-hover path is handled
                // separately by handleEntered.
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
    onModeChanged: ctl._scheduleEvaluate()
    onTargetScreenChanged: ctl._scheduleEvaluate()
    onPositionChanged: ctl._scheduleEvaluate()
    onDockWidthChanged: ctl._scheduleEvaluate()
    onDockHeightChanged: ctl._scheduleEvaluate()
    onPointerInsideDockChanged: ctl._scheduleEvaluate()
    on_HandleHoveredChanged: ctl._scheduleEvaluate()
    onEditingChanged: ctl._scheduleEvaluate()
    onDraggingChanged: ctl._scheduleEvaluate()
    onPopupOpenChanged: ctl._scheduleEvaluate()
    onLauncherOpenChanged: ctl._scheduleEvaluate()
    onConfigReadyChanged: ctl._tryResolveBoot(false)
    onWindowDataReadyChanged: { ctl._recomputeConflict(); ctl._scheduleEvaluate() }

    Connections {
        target: WindowService
        // Geographic/desktop changes to windows, or a just-completed first
        // snapshot, all wake the conflict pass. A revision bump means a window
        // moved/resized/appeared — the cached conflict must be recomputed, not
        // just re-evaluated against the stale value (otherwise a window that
        // arrives after boot never hides a smart dock).
        function onRevisionChanged() {
            // Geometry snapshots are already throttled at the KWin boundary.
            // React to an actual collision edge immediately; waiting on the
            // generic 80ms debounce made reveal/hide lag behind the window.
            if (ctl._recomputeConflict())
                ctl._doEvaluate()
        }
        function onCurrentDesktopIdChanged() {
            if (ctl._recomputeConflict())
                ctl._doEvaluate()
        }
    }

    Component.onCompleted: {
        ctl._bootTimeout.start()
        ctl._tryResolveBoot(false)
    }
}
