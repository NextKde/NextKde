# Wallpaper architecture

[简体中文](WallpaperArchitecture.zh-CN.md)

For AI contributors. Keep wallpaper failure independent of Shell/Dock startup.
[DepthEngine](DepthEngine.md) owns model/worker details; [ThemePackFormat](ThemePackFormat.md)
owns the theme host contract. This document owns runtime orchestration.

## Ownership

- `WallpaperService.qml` owns original image, mode, transitions, recent images, slideshow and takeover.
  `WallpaperImageLayer.qml` draws normal images per output, with bounded transition textures and
  deferred cleanup. Do not force a global Qt render loop to hide a local animation issue.
- `WallpaperPreviewService.qml` owns a cancellable draft across outputs: Enter confirms; Escape/close
  cancels. Keep confirmed state separate from preview playlists, colors and frequency.
- `SpatialWallpaperService.qml` requests prepared assets; `DepthWallpaperLayer.qml` renders them.
  Preparation failure leaves the ordinary wallpaper usable.
- `WallpaperColorSource.qml` extracts the original palette; `PlasmaWallpaperAdapter` owns Plasma
  integration and accent metadata. Settings uses `wallpaper-settings` IPC, then platform operations
  `wallpaper.plasma.*` and `wallpaper.preview.desktop`. QML never calls Plasma D-Bus or inference directly.

## Takeover and capability checks

Takeover is explicit. After every output image and palette are ready, platform backs up per-output
original paths to `~/.local/share/kos/plasma-wallpaper-backup.json` and installs a small black/white
placeholder wallpaper. Disabling restores originals. Failure retains Plasma wallpaper and reports
an error. Resolve the active ShellPackage configuration, not a fixed appletsrc. Restore the original
KWin show-desktop state when ending preview.

`platform.ping` capabilities gate preview/takeover and spatial resources. A connected but old daemon
must show an upgrade/unavailable state rather than receive unknown operations. Platform reconnect
preserves previous window/workspace snapshots and re-subscribes; wallpaper never rebuilds Dock models.
Currently normal images are shared across screens, without panoramic stitching.

## Async preparation and resource ownership

Settings' service/components page initializes pinned, SHA256-verified ONNX models through an isolated
worker. Persist enabled state after successful initialization. Models are not downloaded by core
installation. Ordinary wallpaper, color and slideshow remain usable without models.
`spatial.status` exposes byte progress for downloads and indeterminate processing stages.
`spatial.cancel` terminates pending work and partial downloads; generation IDs reject late replies.
Cancellation is not a crash/cooldown event. Verified complete models remain reusable.

The generated asset cache is bounded to 2 GiB. Internal `spatial.clear` accepts only fixed scopes
`generated`/`models`/`all`, stops worker/rendering first and refreshes status. Removing models disables
the service; clearing generated assets preserves them. Model URLs/hashes live in `ModelManager.h`,
not an assumed future release repository. Full inference is distinct from worker protocol tests.

Use matching built native modules and services in VM development. `kosctl dev settings` prints its
actual paths. Both Qt import path variables must include current modules. Prepared assets alone do
not prove 3D rendering: inspect `renderer=3D mesh` / `meshRenderer: true`; fallback shaders remain a
separate path. Foreground/background depth geometry, masks and cache-contract changes must stay in sync.

## Modes and themes

Image, color, slideshow and theme modes share the catalog in `shared/qml/foundation/WallpaperCatalog.js`.
Colors are internal cached images, not user gallery entries. Preview uses thumbnails but applies
original paths. Serialize requests so late replies cannot overwrite newer choices. Slideshows have
at most 2000 entries, pause during preview and stop below two images; outputs share the random seed.

Themes retain the original image for restoration/lockscreen, stop slideshow and depth mode, and
need no AI model. `ThemeWallpaperScene` and the foreground layers use the shared host contract.
Normal playback waits for desktop idle with no visible windows; preview plays immediately, while
lock/offscreen/reduced-motion policies still apply. Weather uses the shared service cache.
Do not claim independent foreground/background windows are frame-synchronized under load.
Preserve [vendor provenance](../shared/qml/wallpapers/vendor/README.md) and shader Qt compatibility.

## VM review

Test ordinary image/takeover/restore without AI models; decode failures, missing daemon/capabilities,
rapid change/cancel, multi-output readiness, preview apply/cancel and retained confirmed state.
Test spatial download/checksum/cancel/inference/render paths separately if claiming full spatial
support. Measure theme GPU costs instead of copying historical demo impressions.
Run changed tests and the live Shell only in VM/CI per [Development](Development.md).
