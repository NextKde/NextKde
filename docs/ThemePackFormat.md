# Wallpaper theme pack format

[简体中文](ThemePackFormat.zh-CN.md)

A pack is a self-contained directory of QML, manifest and assets. It does not import Shell
modules: input comes through the stable host object below. Built-ins under
`shared/qml/wallpapers/themes/<id>/` use the same runtime contract, with IDs registered in source
instead of a manifest. Packs are side-loaded code; this is not a sandboxed public marketplace.

## Layout and discovery

Install under `~/.local/share/kos/wallpaper-themes/<id>/`; `KOS_WALLPAPER_PACKS` overrides the scan
root for development. `ThemePackService` rescans every 30 seconds or on explicit `rescan()`.
The directory contains `manifest.json`, `main.qml`, optional `preview.png`, shaders and assets.
Relative shader/assets URLs resolve from the entry QML. Preserve shader/Qt version compatibility.

```json
{
  "id": "forest",
  "name": "Forest",
  "detail": "Layered trees and fireflies",
  "accent": "#B5CE75",
  "version": 1,
  "entry": "main.qml",
  "preview": "preview.png"
}
```

All manifest fields are optional after a valid manifest is parsed: ID falls back to directory
name and must match `[A-Za-z0-9_-]+`; name falls back to ID, detail to empty text; accent uses the Shell fallback;
version defaults to 1; entry defaults to `main.qml`; preview may be absent. Entry/preview are file
names without `/` or `..`; an invalid preview is cleared. Invalid manifests are skipped without breaking other packs.
An installed ID overrides the same built-in ID; unavailable scenes fall back to Starfield.

## Root contract

```qml
import QtQuick
Item {
    id: root
    property var host: null
    signal frameReady()
    Rectangle {
        anchors.fill: parent
        color: root.host && root.host.economical ? "#101820" : "#182638"
    }
    Component.onCompleted: Qt.callLater(() => root.frameReady())
}
```

The Shell injects the stable `host` after creation. Emit first-frame readiness asynchronously
so the signal is not lost before the host connects. Background scenes report readiness; foreground
scenes may omit it. Read all input through host:

| Field | Type / meaning |
| --- | --- |
| `themeId` | string; scene ID |
| `phase` | real; shared animation time in seconds |
| `foreground` | bool; foreground pass above windows vs background |
| `economical`, `particleCount` | bool/int; resource policy and requested particle count |
| `widgetRects` | list of up to 8 surface-coordinate x/y/width/height rectangles |
| `pointer` | vector4d: x/y UV, inside, 0 |
| `clickPulse` | vector4d: x/y UV, click phase, 0 |
| `weatherCode` | int WMO code; 0 when unavailable; also check availability |
| `windStrength`, `windDirection` | real, normalized 0–1 / degrees |
| `isDay`, `weatherAvailable` | bool |
| `temperature`, `city` | display strings |

Switching themes destroys the old instance; do not depend on retained internal state.
Hidden/offscreen/locked scenes retain their frame while phase is paused. Normal desktop animation
waits for idle policy, so render a first frame without requiring a ticking clock. See
[wallpaper ownership](WallpaperArchitecture.md) for preview and playback policy.
Arbitrary pack QML requires trusted side-loading; public distribution would need review or a more
restricted declarative format. Old `.qsb` files may need rebuilding for another Qt version.
