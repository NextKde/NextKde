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

`KosKineticScroll` adds mouse-wheel inertia to selected long lists. It runs
behind child controls and nested views, leaves Ctrl gestures and pixel-based
trackpad scrolling to native handlers, and respects `AppTheme.reduceMotion`.
Motion advances once per rendered frame through `FrameAnimation`; no timer
continues integrating a hidden view. An empty range or a settled boundary
passes the wheel onward.

```qml
ListView {
    id: results
    KosKineticScroll { flickable: results }
}
```

The arithmetic lives in `KosKineticScrollPhysics.mjs` and has pure Node tests.
QML regression tests cover motion, sliders, nested views, trackpad handoff and
reduced motion. Menus, Dock previews, calendar ScrollView, wallpaper strip and
legacy music remain native in this integration. ListenFree is not changed.
A catcher declared beside a view must use a plain ancestor for its parent;
placing extra children in a ScrollView can invalidate its content sizing.
