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

    // A spring follows the pointer without the hard stop of a fixed-duration
    // animation. It is used only for visual transforms.
    //
    // Measured with an offscreen probe (0 -> 100 step, 60 Hz sampler):
    //   previous  s6.0 / d0.84 / m0.45 -> t90 304 ms, settle 432 ms  (sluggish)
    //   current   s8.0 / d0.40 / m0.60 -> t90  96 ms, settle 160 ms, 0.1% overshoot
    // Qt's `damping` is not a physical damping ratio: the lower it is, the sooner
    // the motion comes to rest (docs: "The lower the value, the faster it comes
    // to rest"). Below ~0.2 it overshoots visibly (d0.20 -> 13%, d0.10 -> 45%);
    // a small `mass` together with a high `damping` makes the integrator diverge,
    // so keep mass >= ~0.45.
    // `spring` sits above Qt's documented useful range (0 - 5.0). It is stable
    // here and it is what buys the speed; s5.0 / d0.30 / m0.50 settles just as
    // fast (t90 112 ms) and stays inside the documented range.
    readonly property real  iconSpring:         8.0
    readonly property real  iconDamping:        0.40
    readonly property real  iconMass:           0.60

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
    // Window previews should feel like a direct hover affordance, while still
    // ignoring brief pointer passes across neighbouring Dock icons.
    readonly property int   windowPreviewDelay:         300
    // Leave enough hand-off time to move from the Dock icon into the separate
    // preview surface, while keeping the preview responsive when abandoned.
    readonly property int   windowPreviewCloseDelay:     130
    readonly property int   windowPreviewHandoffDuration: 30
    readonly property int   windowPreviewExitDuration:   110
    readonly property real  windowPreviewExitScale:      0.94
    // A transparent 1px layer-shell margins reparenting of the dock content to
    // the true screen edge: the white reveal handle sits this far (dp) from the
    // physical edge whereas the dock glass keeps edgeMargin-1 breathing room.
    readonly property real  smartHideHandleEdgeInset:  6
}
