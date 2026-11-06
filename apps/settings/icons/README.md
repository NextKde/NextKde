# Icon sources

The application list uses the applications' own artwork, copied without edits:

- `calendar.svg`, `calculator.svg`, `weather.svg`: `NextKde/kos-apps`, revision
  `98aadc63ea1079eeade823b9ac35c974509a907f`,
  `apps/org.nextks.<app>/data/kos-<app>.svg`.
- `listenfree.png`: `NextKde/ListenFree`, revision
  `69cb4cb77f28c03348efa5da2bf38ea2228e6fc6`,
  `music_player_desktop/assets/icons/app.png`. The upstream `app.svg` wraps
  this PNG; using the PNG directly avoids a relative image dependency.

These assets remain upstream artwork under their respective project licenses.
The existing `kmusic.svg` and `spatial-wallpaper.svg` are retained.

`kde-symbolic.svg` and `kde-symbolic-dark.svg` are copies of the
KDE mark from the installed Breeze Icons 6.31.0 package:

- `/usr/share/icons/breeze/apps/22/kde-symbolic.svg`
- `/usr/share/icons/breeze-dark/apps/22/kde-symbolic.svg`

The light asset only normalizes trailing whitespace; icon geometry is unchanged.

The package identifies its upstream as KDE Frameworks and declares
LGPL-3.0-or-later / LGPL-2.1-only licenses. These assets remain upstream artwork.
The KDE mark identifies the toolbar action that opens KDE System Settings.
