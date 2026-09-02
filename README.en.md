# KOS Desktop Shell

[中文](README.md)

KOS is a Quickshell-based desktop shell for KDE Plasma 6 on Wayland. It adds a
top bar, floating dock, desktop widgets and files, launcher, search,
notifications, workspace overview, and a standalone settings app. KOS does
not replace Plasma, KWin, NetworkManager, PipeWire, or systemd; it runs beside
them and only takes over the surfaces you choose to hide.

## 🚀 New here? Start with this

| Goal | Command | What to expect |
| --- | --- | --- |
| ✏️ Apply QML edits | `./tools/kosctl sync` | Copies only the `shell/` QML tree into the installed config (takes seconds). The installed shell does not hot-reload (its file watcher is disabled); run `./tools/kosctl start` afterwards. No builds. For QML-only changes. |
| ✅ First install / update | `./tools/kosctl install` | Installs files and registers autostart only — it does not touch the running session: no service restarts, no KWin effect hot-reload. The new revision takes effect at the next login or after `./tools/kosctl start`. KWin plugin installation may request `sudo`. |
| ⚡ Apply immediately | `./tools/kosctl start` | Restarts the three user services to apply the latest installed revision (the UI briefly switches). KWin effects are only persisted to kwinrc and load on the next KWin/session start. Takes over a manually started `qs -c kos` instance under systemd. Use after C++/Go/KWin changes. |
| 🔬 Full-stack source debugging | `./tools/kosctl dev` | Runs platform, data service, and shell straight from the source tree and build outputs, on dedicated sockets isolated from the installed services. Note: the KWin bridge registration is global, so the installed shell stops receiving window events while the dev stack runs. |
| 🧪 Preview workspace changes | `./tools/kosctl run` | Starts an isolated preview from the checkout. It neither starts services nor replaces the installed `kos-shell`; IPC features use data from services that are already running. |
| 🏠 Daily installed Shell | `qs -c kos` | Starts the installed configuration. Run this only after `kosctl install`; `kos-shell.service` can also start it with your user session. |

Every launch mode shares one state directory (`~/.local/state/quickshell/kos`,
pinned by the `StateDir` pragma in `shell/shell.qml`): dock pins, launcher
custom icons, appearance, weather cache, and other user data stay consistent
between the installed shell and source previews/debugging. When changing a
config format, keep it backward compatible or add migration logic so the
installed instance's data survives.

Check the services when a feature reports a platform/data socket error:

```sh
systemctl --user status kos-platform.service kos-data.service kos-shell.service
```

## UI preview only

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
- The default installation builds the two KOS KWin plugins and the vendored
  `kwin-effects-glass`, so matching KWin/KF6 development files are required.
  On Arch/CachyOS, the installer obtains missing KF6 build dependencies with
  `sudo pacman`.

`kosctl build` downloads Go modules through `https://goproxy.cn,direct` by
default. Set `GOPROXY` before building if you need a different mirror or an
offline module cache, for example `GOPROXY=off ./tools/kosctl build`.

On Arch, the usual base packages are `quickshell cmake ninja gcc qt6-base go`.
On Debian/Ubuntu, install the equivalent `quickshell cmake ninja-build g++
qt6-base-dev golang` packages from your distribution or the Quickshell
release channel.

## Complete user installation

`apps/settings` is currently a core companion of the Shell and is installed
with `kosctl`; it owns the standalone settings UI. Future applications under
`apps/` remain optional: they must not be built, installed, or started by the
default Shell path, and each must provide its own documented entry point.

Run the single entry point from the repository root:

```sh
./tools/kosctl doctor
./tools/kosctl install
```

`kosctl install` builds and installs:

- `kos-platform` to `~/.local/libexec/` (one resident C++/Qt platform process);
- `kos-data-service` to `~/.local/libexec/` (the resident Go metrics/history
  process);
- `kos-settings` to `~/.local/bin/`;
- the Quickshell tree to `~/.config/quickshell/kos`;
- `kos-platform.service`, `kos-data.service`, and `kos-shell.service` as
  systemd user units. The shell requires the platform service and starts only
  after it is ready.
- KOS Dock Animation, Quickshell Context Menu Input, and Glass into KWin's
  system plugin directories.

The installer only installs files and enables the three user units (registering
autostart); it does not restart anything that is running, and KWin effects are
only written to kwinrc, not hot-reloaded. The new revision takes effect at the
next login, or immediately via `./tools/kosctl start` (restarts services and
hot-reloads effects; the UI briefly switches). User
files remain under `~/.local`; system KWin files and missing Arch/CachyOS build
dependencies are installed with `sudo`, whose password prompt remains in the
calling terminal. Glass conflicts with stock Blur, so the installer remembers
and disables Blur. `./tools/kosctl uninstall` removes all three effects and
restores the previous Blur state.

To build and install only the user-level components, opt out explicitly:

```sh
KOS_BUILD_KWIN_PLUGINS=OFF ./tools/kosctl install
```

Open KDE's Desktop Effects page to inspect or configure Glass with:

```sh
./tools/kosctl glass-settings
```

Start the installed shell with:

```sh
qs -c kos
```

After editing QML, use `./tools/kosctl run`, which loads the checkout with
`qs -p shell`. It is an isolated preview and never starts or restarts services.
To make the revision the daily Shell, run `./tools/kosctl install` (non-disruptive)
and then `./tools/kosctl start` to apply it immediately, or let the next login
pick it up.

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

## Roadmap

Planned next, in rough priority order:

- **Per-monitor layouts** — persist DeskCenter widgets, desktop-icon layout,
  Dock position/visibility, and wallpaper sampling per display.
- **DeskCenter theming** — let desktop cards consume the appearance token layer
  (the last surface not yet token-driven).
- **Settings coverage** — keyboard-shortcut and DeskCenter pages in
  `kos-settings`.
- **Standalone apps** — fill in the `calendar`, `todo`, and `weather`
  placeholders under `apps/`, while keeping every application independently
  buildable and optional for Shell-only users.
- **Accessibility & keyboard navigation** — focus order, reduced motion,
  high contrast, full keyboard operation.
- **Weather icon set** — a complete SVG icon set replacing the current mix of
  Unicode glyphs, Canvas drawing, and partial SVGs.

Shelved: cross-file-manager drag-move beyond the clipboard bridge (Wayland DnD
action negotiation limits).

## Useful commands

```sh
./tools/kosctl doctor
./tools/kosctl build
./tools/kosctl sync
./tools/kosctl run
./tools/kosctl dev
./tools/kosctl install
./tools/kosctl start
./tools/kosctl uninstall
systemctl --user status kos-platform.service kos-data.service
journalctl --user -u kos-platform.service -u kos-data.service -f
```

`install` only installs files and registers autostart; it never restarts a
running session (no screen blanking, no closed apps). `start` is the command
that restarts services and hot-reloads the KWin effects. `uninstall` stops the
services, removes installed binaries, units, and the
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
network/proxy error; retry with another mirror by setting `GOPROXY`.

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
tools/kosctl               build/install/start/run/doctor/uninstall entry point
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
