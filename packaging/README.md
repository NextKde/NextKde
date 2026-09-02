# Packaging

Packaging contains files that are copied or rendered by `tools/kosctl`:

- `systemd/kos-platform.service`, `systemd/kos-data.service`, and
  `systemd/kos-shell.service.in` are user units installed to
  `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/`. The shell unit requires
  the platform unit and starts after it.
- `desktop/kos-settings.desktop.in` and `desktop/org.kos.Platform.desktop.in` are
  rendered with the selected install prefix and installed to
  `~/.local/share/applications/`. The hidden platform entry declares KWin's
  restricted ScreenShot2 interface so Dock window thumbnails are authorized.

User services and shell files remain user-owned. The default installer stages
the two KOS KWin effects and vendored Glass effect, then uses `sudo` to copy
only the staged manifest into KWin's system plugin paths. The same manifest is
used for exact removal by `kosctl uninstall`.
