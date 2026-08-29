# KOS Desktop Shell

**[English](README.md) | [中文](README.zh-CN.md)**

An iPadOS-inspired desktop environment for **KDE Plasma 6 (Wayland)**, built on
[Quickshell](https://quickshell.org). KOS is not a distribution or a fork of a
desktop environment — it is a complete Quickshell configuration plus a small set
of native helpers and KWin effects that together replace the Plasma shell
experience: a top bar, a floating dock, desktop widgets, a launcher, a
notification system, a workspace overview, and a standalone settings
application.

> Status: personal daily-driver project under active development. Interfaces
> and configuration schemas are versioned and migrated, but expect rapid
> evolution.

---

## Features

### Shell surfaces

- **Top Bar** — system tray, network status with live traffic rates, Bluetooth,
  volume, battery, CPU temperature, clock, and the control-center entry. Can
  either stay independent or be fused into the Dock.
- **Dock** — iPadOS-style pinned apps + running windows, magnification,
  drag-to-reorder, right-click context menus, live window previews, MPRIS music
  player with cover-art palette, weather, and a trash applet with badge. Three
  positions (bottom / left / right), three visibility modes (`always` /
  `smart` window-collision auto-hide / `persistent`) with an iOS-style home
  indicator, and icon appearance modes (`color` / `grayscale` / `tint`).
- **Bar ⇄ Dock fusion** — optionally merge the bar into a bottom Dock: the
  clock joins the music/weather/temperature info carousel and the status area
  becomes a trailing accessory. Side docks get a counter-rotated, vertically
  readable carousel instead.
- **DeskCenter** — background-layer desktop widgets (clock, weather, calendar,
  system monitors with history rings, activity ledger, now-playing) and a real
  desktop file surface: sorting, box selection, rename, trash, hold-to-drop
  folder insertion, multi-select drag, new file/folder, external URL drops, and
  cut/copy semantics that interoperate with Dolphin.
- **App Launcher** — iPadOS-style full-screen grid with drag-to-create folders,
  custom names/icons, and hidden apps.
- **Quick Search** — incremental app/file search, clipboard history (cliphist,
  including images), and an MRU window switcher with live KWin thumbnails.
- **Notifications** — per-app grouping with stacked/expanded cards, action
  buttons, inline reply, critical-urgency styling, do-not-disturb, and a
  grouped history center inside the control center.
- **Workspace Overview** — Stage-Manager-style fullscreen overlay with a
  virtual-desktop strip and live window thumbnails (`Meta+Tab`).
- **Control Center** — Wi-Fi connect/disconnect/forget including 802.1X
  (PEAP / TTLS), Bluetooth, volume, real backlight brightness via logind,
  do-not-disturb, screenshot, logout, and notification history.

### Appearance system

- Three shell styles — **Windows 12**, **macOS**, **Material** — driven by a
  versioned semantic-token layer (`AppearanceTokens`), hot-switchable without
  rebuilding any surface.
- Global **blur strength** and **liquid-glass strength** sliders that feed both
  the QML glass materials and the KWin glass effect.
- Standalone **Settings application** (`kos-settings`) running in its own
  process; it talks to the shell exclusively through a versioned IPC contract
  (`appearance-settings`).

### Graphics & effects

- **KWin glass effect** (`integrations/kwin-effects-glass`): a Plasma 6 blur
  fork with Dual Kawase blur, Snell's-law refraction, per-surface highlight
  direction, and bidirectional tint (dark backgrounds lift toward white, bright
  backgrounds darken).
- **Dock window animation effect** (`integrations/kwin-dock-window-animation`):
  iPadOS-style `scale` / `genie` open-close animations; the shell publishes the
  exact on-screen icon rectangles so windows land precisely on their icons.
- **Context-menu input effect** (`integrations/kwin-context-menu-input`):
  compositor-level outside-click dismissal for shell context menus.
- Client-side SDF rounded-corner, refraction, noise and glow shaders compiled
  with `qsb`.

### Platform services

- **`shell-data-service` (Go)** — the single owner of durable and historical
  data: CPU/memory/disk/frequency/temperature sampling with history, boot and
  per-app activity ledger, desktop-directory watching with atomic snapshots,
  and a supervised Qt clipboard helper that publishes copy/cut in URI, KDE, and
  GNOME formats simultaneously.
- **KWin window bridge** (`helpers/kwin-window-bridge`) — a C++ D-Bus bridge
  plus a KWin script that supplies window enumeration, geometry, activation,
  minimization, thumbnails and virtual-desktop data, because KWin does not
  implement `zwlr-foreign-toplevel-management-v1`.
- **Global shortcuts** — registered as native KDE Command Shortcuts with
  install-time conflict detection; rebindable in *System Settings → Shortcuts*.

---

## Requirements

| Component | Requirement |
| --- | --- |
| Session | KDE Plasma 6 on Wayland (developed on Plasma/KWin 6.7) |
| Shell runtime | [Quickshell](https://quickshell.org) 0.3.0 (`qs`) |
| Build tools | Go, CMake, a C++ compiler, Qt 6 Gui development files, `socat` |
| Runtime integration | NetworkManager (`nmcli`), systemd user session, logind |
| Optional | `cliphist` (clipboard history), `qdbus6`/`kwriteconfig6` (effect sync) |

On Arch-based systems the build dependencies are typically
`go cmake gcc qt6-base`; on Debian/Ubuntu `golang cmake g++ qt6-base-dev`.
Building the KWin effects additionally needs the KWin development package
(`kwin-dev` / `kwin-devel`) and KF6 development headers.

## Installation

Clone the repository, then install the components you need. Everything except
the KWin effects installs into user or `/usr/local` locations and can be
removed cleanly.

### 1. Run the shell

```sh
quickshell --path /path/to/quickshell
# or, if `qs` is your quickshell binary:
qs -p /path/to/quickshell
```

The entry point is `shell.qml`; it only instantiates
`desktop/DesktopEnvironment.qml`.

### 2. Data service (recommended)

Builds the Go service plus the Qt clipboard helper, installs them to
`~/.local/lib/quickshell`, and enables the systemd user unit:

```sh
./tools/install-shell-data-service.sh
```

Without it, system metrics, the activity ledger, desktop files, and
cross-application file copy/cut are unavailable.

### 3. KWin window bridge (required on Plasma)

```sh
cmake -S helpers/kwin-window-bridge -B .build/kwin-window-bridge
cmake --build .build/kwin-window-bridge
sudo install -m 0755 .build/kwin-window-bridge/quickshell-kwin-window-bridge \
    /usr/local/libexec/quickshell-kwin-window-bridge
```

`WindowService` starts the bridge and loads its KWin script automatically when
the shell runs; on compositors that implement foreign-toplevel-management the
bridge stays unused.

### 4. KWin glass effect (recommended)

The vendored fork in `integrations/kwin-effects-glass` is the authoritative
source; see its [README](integrations/kwin-effects-glass/README.md) for
distribution packages or manual build instructions. After installing, enable
the effect (plugin ID `blurplus`) in *System Settings → Desktop Effects*. Blur
and refraction strength are then driven live by the shell's appearance
settings.

### 5. Optional internal KWin effects

```sh
for effect in kwin-dock-window-animation kwin-context-menu-input; do
    cmake -S "integrations/$effect" -B ".build/$effect"
    cmake --build ".build/$effect"
    sudo cmake --install ".build/$effect"
done
```

Enable them in *System Settings → Desktop Effects*. The dock animation style
(`scale` / `genie`) follows the shell's appearance configuration.

### 6. Settings application

```sh
cmake -S apps/settings -B .build/apps/settings
cmake --build .build/apps/settings
```

A desktop entry template is provided at
`packaging/desktop/kos-settings.desktop.in`.

### 7. Global shortcuts

```sh
python3 helpers/global-shortcuts/install.py
```

This registers KDE Command Shortcuts with conflict detection and seeds the
default bindings. Re-run it after editing
`helpers/global-shortcuts/shortcuts.json`; change bindings afterwards in
*System Settings → Shortcuts*.

### 8. Notification takeover

Quickshell's notification server can only own the D-Bus name if Plasma's
notification applet is out of the way: remove the notification widget from the
system tray settings and restart plasmashell once
(`systemctl --user restart plasma-plasmashell`).

### Default shortcuts

| Shortcut | Action |
| --- | --- |
| `Meta+Space` | Toggle app launcher |
| `Meta+Shift+Space` | Toggle window switcher (MRU) |
| `Meta+B` | Toggle control center |
| `Meta+Tab` | Toggle workspace overview |

## Project layout

```text
shell.qml       stable Quickshell entry point
desktop/        the desktop environment (bar, dock, deskcenter, launcher, …)
apps/           independent Qt Quick applications (settings, …)
shared/         pure, portable cross-process QML and contracts
services/       resident background services (shell-data-service, Go)
helpers/        on-demand native helpers (KWin bridge, shortcuts, clipboard)
integrations/   KWin effects and other compositor integrations
tools/          install, build, and diagnostic scripts
docs/           architecture documentation
```

## Documentation

- [Project architecture](docs/ProjectArchitecture.md) — runtime boundaries and
  dependency direction
- [Dock architecture](docs/DockArchitecture.md) — identity, window model,
  persistence, and visibility modes
- [Appearance architecture](docs/AppearanceArchitecture.md) — schema, IPC
  contract, and semantic tokens
- [Network architecture](docs/NetworkArchitecture.md) — NetworkManager adapter
  boundary
- [Shell data service](docs/ShellDataService.md) — Go data-layer ownership and
  protocols
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) — condensed engineering context and
  key technical decisions

## Roadmap

Planned next, in rough priority order:

- **Per-monitor layouts** — persist DeskCenter widgets, desktop-icon layout,
  Dock position/visibility, and wallpaper sampling per display.
- **DeskCenter theming** — let desktop cards consume the appearance token layer
  (the last surface not yet token-driven).
- **Settings coverage** — keyboard-shortcut and DeskCenter pages in
  `kos-settings`.
- **Standalone apps** — fill in the `calendar`, `todo`, and `weather`
  placeholders under `apps/`.
- **Accessibility & keyboard navigation** — focus order, reduced motion,
  high contrast, full keyboard operation.
- **Weather icon set** — a complete SVG icon set replacing the current mix of
  Unicode glyphs, Canvas drawing, and partial SVGs.

Shelved: cross-file-manager drag-move beyond the clipboard bridge (Wayland DnD
action negotiation limits).

## Development

```sh
qmllint <changed-qml-files>
node desktop/modules/dock/test_adaptive.mjs
node desktop/modules/dock/test_autohide.mjs
git diff --check
```

Runtime verification launches a separate Quickshell instance and inspects its
log; see `.agents/skills/verify/SKILL.md`. Commits follow
`feat(scope): description`.
