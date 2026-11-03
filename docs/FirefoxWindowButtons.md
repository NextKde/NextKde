# Firefox native traffic-light buttons

[简体中文](FirefoxWindowButtons.zh-CN.md)

Firefox uses GTK platform integration on Linux, but draws its browser-chrome controls itself. This adapter styles those existing controls and preserves native close, minimize and maximize/restore actions. It adds no replacement widgets, overlay or background panel.

## Usage

Register existing profiles once as the desktop user:

```sh
./tools/kosctl firefox-buttons install
./tools/kosctl firefox-buttons install --profile /absolute/path/to/profile
```

Discovery reads existing profiles from `~/.mozilla/firefox/profiles.ini` and `$XDG_CONFIG_HOME/mozilla/firefox/profiles.ini`. Repeat `--profile` for custom locations. Registered profiles follow the common **KOS window appearance** and **Window button icons** preferences. Settings embeds the synchronization resources. Disabling appearance restores original Firefox controls while retaining the exclusion from the legacy overlay.

Restart Firefox to read changed CSS. Log out/in after installing the updated KWin plugin. The installer only writes configuration; it does not launch Firefox or reload the desktop. Button order and visibility remain controlled by Firefox/GTK and the existing theme.

Managed blocks are appended to `chrome/userChrome.css` and `user.js`; recovery records live in `$XDG_CONFIG_HOME/kos/firefox-buttons-state.json`. Existing imports and unrelated preferences are retained. A theme-owned `user.js` symlink is left untouched if it already enables `toolkit.legacyUserProfileCustomizations.stylesheets`. Symlinks requiring modification are rejected.

Quit Firefox before uninstalling:

```sh
./tools/kosctl firefox-buttons uninstall
```

Uninstall removes managed blocks and the owned KWin rule, restores the managed loader preference and preserves unrelated later edits.

## Scope and verification

The qualification matches normal `firefox` windows only. Server-decorated windows retain KOS controls. Other browsers, dialogs and unqualified applications retain existing handling. Automatic Snap/Flatpak profile discovery, sandbox integration and custom app IDs are outside this adapter's scope.

All automated validation runs in a VM; see [acceptance instructions](../tests/firefox-buttons/README.md). Coverage includes built-in light/dark and Firefox-GNOME themes, common preferences, native actions and an overlay positive control. VM results do not substitute for manual testing of another installed Firefox version.
