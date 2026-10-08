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

It also owns the shell's wheel scrolling: `KosKineticScroll` is a non-visual
companion for any `Flickable`, `ListView` or `GridView` that gives the wheel
browser-style inertia (aim, accelerate, coast, stop exactly on the target)
instead of the platform's per-notch step. Drop it inside the view:

```qml
ListView {
    id: results
    KosKineticScroll { flickable: results }
}
```

The curve and its tuning live in `KosKineticScrollPhysics.mjs`, which has no
QML dependency and is replayed by `test_kinetic_scroll.mjs`. A `ScrollView`
cannot take the companion as a child -- an extra child in its `contentItem`
unsizes the view (`contentWidth`/`contentHeight` become -1) -- so those declare
it beside the view with `parent:` pointing at a plain ancestor.
