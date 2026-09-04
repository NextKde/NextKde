pragma Singleton
import QtQuick
import qs.desktop.modules.common

// ────────────────────────────────────────────────────────────────
// DockAnimation — Central animation configuration.
// Every timing constant, easing curve, and spring parameter lives
// here. Components reference these values; nothing is hardcoded.
//
// Design philosophy: natural, physics-informed motion.
// No gratuitous flourishes — every animation has a purpose.
// ────────────────────────────────────────────────────────────────

QtObject {
    id: svc

    // ═══════════════════════════════════════════════════════════
    // Dock resize (triggered by window open/close, music appear)
    // OutCubic: fast start, soft stop. InCubic's slow start was rejected by
    // A/B test — it reads as "creeping" even at 100ms.
    // ═══════════════════════════════════════════════════════════
    readonly property int   dockResizeDuration: AppearanceTokens.motion.fastDuration
    readonly property var   dockResizeEasing:   AppearanceTokens.motion.standardEasing

    // ═══════════════════════════════════════════════════════════
    // Icon hover magnification
    // ═══════════════════════════════════════════════════════════
    // Hover is an explicit pointer affordance: the icon lifts and grows while
    // its layout slot remains unchanged, so adaptive Dock geometry is stable.
    readonly property int   iconHoverDuration:  AppearanceTokens.motion.fastDuration
    readonly property real  iconHoverScale:     AppearanceTokens.dock.hoverScale
    readonly property var   iconHoverEasing:    AppearanceTokens.motion.standardEasing

    // ═══════════════════════════════════════════════════════════
    // Music player expand / collapse
    // ═══════════════════════════════════════════════════════════
    readonly property int   musicExpandDuration: 320
    readonly property var   musicExpandEasing:   Easing.InOutCubic

    // ═══════════════════════════════════════════════════════════
    // Dock appearance / disappearance
    // ═══════════════════════════════════════════════════════════
    readonly property int   dockFadeDuration:   AppearanceTokens.motion.normalDuration
    readonly property var   dockFadeEasing:     AppearanceTokens.motion.standardEasing

    // ═══════════════════════════════════════════════════════════
    // Directional motion semantics (Material-inspired, same idea as
    // end-4/dots-hyprland): entering elements decelerate into place
    // (fast start, soft settle), exiting elements accelerate away
    // (slow start, quick departure). Use these in explicit animations
    // that have a direction — not on two-way Behaviors.
    // ═══════════════════════════════════════════════════════════
    readonly property var elementEnterEasing: AppearanceTokens.motion.standardEasing
    readonly property var elementExitEasing:  Easing.InCubic

    // ═══════════════════════════════════════════════════════════
    // Dock show-mode (smart auto-hide / persistent) timings.
    // Times and curves are tuned constants consumed by the auto-hide
    // controller; nothing is scattered into UI components. See
    // docs/DockArchitecture.md, "Visibility modes and auto-hide".
    // ═══════════════════════════════════════════════════════════
    readonly property int   smartHideConflictDelay:   200   // GNOME-like stable-overlap debounce
    readonly property int   smartHideModeSwitchGrace: 700   // persistent switch confirmation period
    readonly property int   smartHideLeaveDelay:      900   // pointer/inhibitor-all-cleared leave
    readonly property int   smartHideHoverShowDelay:   90   // handle hover reveal threshold
    readonly property int   smartHideHideDuration:    180
    readonly property int   smartHideRevealDuration:  180
    readonly property var   smartHideHideEasing:      Easing.InCubic
    readonly property var   smartHideRevealEasing:    Easing.OutCubic
    readonly property int   smartHideBootWaitLimit:    450   // max wait for config+KWin snapshot
    readonly property int   smartHideMinRemaining:      70   // floor for reversible animation
    readonly property int   smartHideUrgentRevealMs:   2200  // §5.8 temporary reveal for an urgent window
    // A transparent 1px layer-shell margins reparenting of the dock content to
    // the true screen edge: the white reveal handle sits this far (dp) from the
    // physical edge whereas the dock glass keeps edgeMargin-1 breathing room.
    readonly property real  smartHideHandleEdgeInset:  6
}
