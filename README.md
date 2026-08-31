# KOS Desktop Shell

[中文文档](README.zh-CN.md)

KOS is a Quickshell-based desktop shell for KDE Plasma 6 on Wayland. It adds a
top bar, floating dock, desktop widgets and files, launcher, search,
notifications, workspace overview, and a standalone settings app. KOS does
not replace Plasma, KWin, NetworkManager, PipeWire, or systemd; it runs beside
them and only takes over the surfaces you choose to hide.

## Five-minute preview

Previewing the UI does not install anything and does not need root access:

```sh
git clone <repository-url> NextKde
cd NextKde
./tools/kosctl doctor          # check Quickshell, CMake, Go, and the session
qs -p "$PWD/shell"             # equivalent: quickshell --path "$PWD/shell"
```

Close the preview with `Ctrl+C`. The preview can show empty metrics, windows,
and desktop files until the two user services are installed. Existing Plasma
panels and notifications remain active, so overlap is expected.

## Requirements

- KDE Plasma 6 running on Wayland (KWin is required for the window provider).
- Quickshell 0.3.x (`qs` or `quickshell`). Install it from the
  [official Quickshell documentation](https://quickshell.org/docs/).
- CMake 3.21+, Ninja, a C++20 compiler, Qt 6 development packages, and Go.
- Runtime tools supplied by a normal Plasma session: NetworkManager (`nmcli`),
  PipeWire/WirePlumber (`wpctl`), BlueZ (`bluetoothctl`), `loginctl`, and
  `systemctl --user`.
- Optional clipboard history: `wl-clipboard` (`wl-copy`/`wl-paste`) and
  `cliphist`. File copy/paste through the desktop still works without them.
- KWin/KF6 development packages only when building the optional KWin plugins.

On Arch, the usual base packages are `quickshell cmake ninja gcc qt6-base go`.
On Debian/Ubuntu, install the equivalent `quickshell cmake ninja-build g++
qt6-base-dev golang` packages from your distribution or the Quickshell
release channel.

## Complete user installation

Run the single entry point from the repository root:

```sh
./tools/kosctl doctor
KOS_BUILD_KWIN_PLUGINS=OFF ./tools/kosctl install
```

`kosctl install` builds and installs:

- `kos-platform` to `~/.local/libexec/` (one resident C++/Qt platform process);
- `kos-data-service` to `~/.local/libexec/` (the resident Go metrics/history
  process);
- `kos-settings` to `~/.local/bin/`;
- the Quickshell tree to `~/.config/quickshell/kos`;
- `kos-platform.service` and `kos-data.service` as systemd user units.

The installer enables both units immediately. It never uses `sudo`. Build the
KWin plugins separately with `KOS_BUILD_KWIN_PLUGINS=ON` if your system has the
matching KWin development headers; installing a system-wide KWin plugin may
require administrator permission on your distribution.

Start the installed shell with:

```sh
qs -c kos
```

For development, keep using `./tools/kosctl run`, which loads the checkout with
`qs -p shell`.

### First Plasma setup

KOS provides its own notification server. Remove Plasma's notification widget
from the panel/system tray before starting a daily session, otherwise Plasma
will keep the notification D-Bus name. Re-add it when reverting to Plasma's
shell. KOS does not modify your panel layout automatically.

### Global shortcuts

The defaults are installed without Python:

```sh
./tools/kosctl shortcuts install
```

Bindings are stored in `shared/contracts/shortcuts.v1.json` and can be changed
later in *System Settings → Shortcuts*. Remove only KOS bindings with:

```sh
./tools/kosctl shortcuts uninstall
```

## Architecture at a glance

```text
qs -c kos ──► shell/shell.qml ──► shell/desktop/       Quickshell process
                    │ JSONL Unix sockets
                    ├──────────────► kos-platform       C++/Qt adapters
                    └──────────────► kos-data.sock      Go durable data service

apps/settings/       independent Qt Quick process; talks to Shell IPC only
integrations/kwin/   two KWin plugin .so targets (KWin's loading model)
vendor/              third-party kwin-effects-glass source
shared/contracts/    versioned IPC and shortcut contracts
```

The platform socket is `$XDG_RUNTIME_DIR/kos-platform.sock`; the data socket is
`$XDG_RUNTIME_DIR/kos-data.sock`. Both are Unix sockets with mode `0600`.
Shell, platform, and data messages are newline-delimited JSON with a version,
request ID, operation, result, and stable error model. See
[PlatformArchitecture.md](docs/PlatformArchitecture.md) and
[shared/contracts/platform.v1.md](shared/contracts/platform.v1.md).

`kos-platform` owns KWin window commands, Wayland clipboard ownership, file
operations/Open-With, network/audio/Bluetooth/brightness/session/theme adapters,
screenshot selection, and shortcut installation. `kos-data-service` owns
sampling, history, activity attribution, and desktop-directory snapshots. The
two KWin effects remain separate shared libraries because KWin requires a
plugin ID for each effect.

## Useful commands

```sh
./tools/kosctl doctor
./tools/kosctl build
./tools/kosctl run
./tools/kosctl install
./tools/kosctl uninstall
systemctl --user status kos-platform.service kos-data.service
journalctl --user -u kos-platform.service -u kos-data.service -f
```

`uninstall` stops the services, removes installed binaries, units, and the
Quickshell config, and deliberately preserves
`$XDG_STATE_HOME/quickshell/...` so user preferences and history are recoverable.

## Development and verification

```sh
cmake --preset debug
cmake --build --preset debug
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
node shell/desktop/modules/dock/test_adaptive.mjs
node shell/desktop/modules/dock/test_autohide.mjs
git diff --check
```

Run the checkout in a separate Quickshell instance (`./tools/kosctl run`) and
inspect its log before changing your daily shell. The repository's
[verify skill](.agents/skills/verify/SKILL.md) describes the safe runtime
workflow. If Go dependencies cannot be downloaded, `kosctl build` reports the
network/proxy error; retry with your distribution's Go module mirror.

## Repository layout

```text
shell/                    only Quickshell configuration root
apps/settings/            independent settings application
shared/qml/               portable controls
shared/contracts/          JSONL and shortcut contracts
services/data-service/     Go resident data service
platform/                 one kos-platform CMake project and executable
integrations/kwin/        two project-owned KWin plugins
vendor/kwin-effects-glass/ third-party effect
packaging/                systemd and desktop files
tools/kosctl               build/install/run/doctor/uninstall entry point
docs/                     architecture and operational documentation
```

See [ProjectArchitecture.md](docs/ProjectArchitecture.md) for dependency
direction, [ShellDataService.md](docs/ShellDataService.md) for the data layer,
and [PlatformArchitecture.md](docs/PlatformArchitecture.md) for operations,
permissions, and error handling.

## License

KOS is GPL-3.0-or-later; see [LICENSE](LICENSE). The vendored glass effect
retains its own compatible license in
`vendor/kwin-effects-glass/LICENSE`.
