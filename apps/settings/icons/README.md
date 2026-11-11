# Settings artwork

Application artwork shares the original NextKde icon family documented in
[`NextKde/appCatalog/icons`](https://github.com/NextKde/appCatalog/tree/main/icons).
Calendar, Calculator and Weather SVGs match their canonical `NextKde/kos-apps`
sources. KMusic matches `NextKde/NkMusic/data/kmusic.svg`; ListenFree's PNG is
exported from `NextKde/ListenFree/music_player_desktop/assets/icons/app.svg`.
The signed catalog supplies the other application icons. Existing upstream
licenses and license copies remain applicable.

`navigation/*.svg` and `spatial-wallpaper.svg` are original NextKde artwork with
the same continuous rounded tile, soft colors, ivory symbols and restrained
depth. See `navigation/sources.json` for the category mapping. SVG shapes avoid
clipping paths so Qt SVG preserves the transparent corners. Material navigation
retains monochrome semantic glyphs. All PNG/ICO exports and rendering checks
were performed in the dedicated VM; no application was run on the host.

`nextkde-logo.svg` and `nextkde-logo-dark.svg` mirror the copies in
`docs/images/` for the About page header; the installed Settings app has no
checkout, so it cannot read `docs/` at runtime.

`kde-symbolic.svg` and `kde-symbolic-dark.svg` retain the KDE mark from Breeze
Icons 6.31.0, under its LGPL-3.0-or-later / LGPL-2.1-only terms. These identify the
toolbar action opening KDE System Settings and retain the upstream geometry.
Wallpaper action glyphs retain their existing semantic shapes.

The bundled bootstrap is a sequence-4 core-distribution seed, generated in the VM
from appCatalog commit `d574270b6f6fb5d0f4c0204e3017029b24cae519`. Its icon
URLs and SHA-256 values identify the uploaded artwork. It is not a remotely
published signed catalog. Existing clients with a verified catalog cache receive
new artwork after the maintainer publishes the next signed catalog; existing
application bundles receive their desktop icons in a subsequent app release.
