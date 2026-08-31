# Packaging

Packaging contains files that are copied or rendered by `tools/kosctl`:

- `systemd/kos-platform.service` and `systemd/kos-data.service` are user units
  installed to `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/`.
- `desktop/kos-settings.desktop.in` is rendered with the selected install
  prefix and installed to `~/.local/share/applications/`.

The installer keeps all products user-owned and does not require `sudo`.
System-wide KWin effect installation is intentionally outside this directory
and depends on the host distribution.
