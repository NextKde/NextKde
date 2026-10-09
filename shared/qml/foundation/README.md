# Foundation

Portable Qt Quick foundations for standalone applications. The components in
this directory are built as the static `Kos.Ui` QML module and must not import
Quickshell, KWin, or Wayland-specific APIs.

The module provides the application window, semantic palette and material
surfaces, cards, empty states, navigation controls, rounded buttons, switch,
slider, segmented control, text field, and the common application settings
dialog. KDE compositor integration remains in `apps/common`; when native blur
is unavailable these portable QML surfaces automatically use a high-opacity
fallback.

`KosKineticScroll` centralizes scrolling policy for Flickable, ListView,
GridView and ScrollView. Applications do not need device detection, motion
constants or layout-parent workarounds. It preserves Ctrl gestures, nested
views and `AppTheme.reduceMotion`.

```qml
ListView {
    KosKineticScroll {} // Automatically finds and attaches to this view.
}
// For a ScrollView, declare alongside it or as a separate object property:
ScrollView { id: page; /* content */ }
KosKineticScroll { target: page }
```

Attach one instance per view. Existing explicit `flickable: view` usage remains
supported. The component owns placement, respects visibility/enabled state,
includes originX/originY in bounds, and restores ScrollView's original wheel
handling when disabled or destroyed. Dragging, scrollbar changes and
programmatic positioning cancel synthetic motion.

Angle input preserves 72px/notch, averages the recent 80ms of input and adds
at most 72px of coast (900px/s cap, 6000px/s² deceleration). A critically
damped follow settles a lone notch in about 200ms. Pixel input follows the
fingers directly: slow movement stays 1:1, with a smooth gain from 250 to
1500px/s capped at 1.6x. Raw pixels, not amplified movement, determine speed.
Both paths stop at hard boundaries without rebound.

Qt Quick's QML WheelEvent does not expose scroll phases. Pixel streams may
already include system momentum, so this component never synthesizes another
coast after them. Sources without pixel deltas use the angle-input fallback.
These are KOS tuning defaults inspired by Kirigami's bounded scrolling,
not universal optimal values. Wheel motion uses FrameAnimation and stops
while hidden, disabled or settled. Pixel movement needs no animation loop.

The arithmetic lives in `KosKineticScrollPhysics.mjs` with pure Node tests.
QML regression tests cover both input paths, automatic placement, ScrollView,
sliders, nested views, device switching and reduced motion. The current app
integration still leaves menus, Dock previews, calendar, wallpaper strip and
legacy music on their existing paths. ListenFree is not changed.
