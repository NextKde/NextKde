# Cooperative window controls

[简体中文](CooperativeWindowControls.zh-CN.md)

Custom Qt Quick apps can reserve a controls region and let KOS Bridge draw only the declared green maximize/restore, yellow minimize and red close buttons (zero to three). The app retains its own title bar and background. Selecting the KOS window decoration is unnecessary.

The shared **KOS window appearance** switch and always/hover glyph preference govern takeover. The app draws its controls until the compositor grants takeover. Turning the switch off, unsupported layout or service loss returns drawing to the app. A declared surface also opts out of legacy overlays while drawing its fallback; unadapted third-party apps retain their existing path. See [GTK controls](GtkWindowButtons.md) for GTK styling.

## Integration

Use the shared `Kos.Ui` `KosWindowControls` in a frameless/client-decorated window, set `targetWindow`, `maximizeMode: true`, and position it using normal QML layout. Weather and Calendar use this component. For example:

```qml
KosWindowControls {
    targetWindow: root
    maximizeMode: true
    actions: ["maximize", "minimize", "close"]
    circleSize: 14
    buttonWidth: 22
    buttonHeight: 22
    spacing: 6
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 10
    anchors.rightMargin: 14
}
```

An updated `Kos.SurfaceShape` module, KOS Bridge and Wayland are required for takeover. The native adapter is loaded optionally: missing modules, X11 and other desktops retain client rendering. Missing modules may emit a Loader warning without failing the app root. `compositorIntegration: false` requests self drawing; layouts containing a green fullscreen-mode control (`maximizeMode: false`) also remain client rendered.

Use `actions: ["close"]` for close only, or `actions: []` to remove all controls and their hit areas. Lists may be reordered; action names determine behavior. `buttonLayout` reports actual circle rectangles local to the component.

## Contract

`shell/native/surface-shape/kos-window-controls-v1.xml` defines one controls object per `wl_surface`. Version 2 atomically replaces the complete list with `set_buttons`, carrying an action and rectangle per button. Coordinates are surface-local logical pixels, not app-ID or title-based guesses. Layout, visibility, window-state and configure events trigger updates. This path performs no title-bar polling, pixel readback or background color sampling; ordinary repaint and input handling still apply.

After configure, the app changes its own controls, acknowledges the serial and commits a frame. Ownership and geometry changes apply on surface commit. Transparent gaps remain available to the app. Cooperative controls do not offer the legacy overlay's right-click placement editor or Alt tiling menu.

The adapter supports normal windows/dialogs and axis-aligned uniform scaling. Fullscreen, translucent controls, rotation/nonuniform scaling, out-of-bounds regions or service loss use client fallback. Version 2 allows zero to three unique actions, square circles 6–40 logical pixels, independent placement and a union at most 4096×4096. Overlapping, duplicate, unknown or out-of-bounds entries reject the whole list. The server retains version 1 trio compatibility; updated clients self-render on older servers. Other toolkits need their own protocol adapter; third-party apps do not acquire this capability automatically.

Custom arrangements can use `WindowControlSlot { target: header; buttons: layout }` in the application platform adapter, with entries such as `{action: "close", x: 300, y: 12, width: 14, height: 14}` local to target. Aggregate all groups in a window into one list/adapter per surface. Bind its `active` state to client fallback visibility; never hide fallback permanently.

The portable nextkdeAppDemo contract lives in that repository's `docs/WindowControls.md`. Its `KosWindowControls` exposes `actions`, `buttonLayout`, `externalDrawing` and `hoverGlyphs` without a native dependency. Protocol integration stays in the consuming application's adapter.

## Validation

Run builds and tests only in a VM. The [nested compositor test](../tests/cooperative-controls/README.md) uses Breeze and checks independent surfaces, geometry changes, shared settings, fallback, transparent rendering and absence of sampling caches. Optional X11 backend input tests exercise maximize, minimize and close.

Legacy overlay `showButtons: false` does not reject an explicit cooperative request. The common appearance switch and protocol negotiation determine ownership.

Deploy the updated `Kos/SurfaceShape` module to both system and Shell import
locations. A launcher with `QML2_IMPORT_PATH=~/.config/quickshell/kos` loads that
copy before the system module. `WindowControlSlot is not a type` indicates an
old module without the cooperative type; the application falls back to drawing
its own controls. Update the shadowing copy and reopen the application.
