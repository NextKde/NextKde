# KOS Desktop Shell

[中文](README.md)

KOS is a Quickshell desktop shell for KDE Plasma 6 on Wayland. It adds a top
bar, dock, launcher, search, notifications, and settings UI while keeping KDE,
KWin, NetworkManager, and other system components in place.

## Get started

### 1. Install requirements

Use a KDE Plasma 6 **Wayland** session (KWin 6.4 or newer), Quickshell 0.3.x,
Qt 6.6 or newer, and the complete KF6 and KWin development dependencies. The
default installation builds the platform service, Settings, KWin effects, and
the window decoration.

On Arch:

```sh
sudo pacman -S --needed \
  git quickshell cmake ninja gcc go qt6-base qt6-declarative \
  kwindowsystem kiconthemes kglobalaccel \
  extra-cmake-modules kwin kconfig ki18n kguiaddons kcmutils \
  kcoreaddons kdecoration gettext libxcb vulkan-headers
```

These runtime integration packages are recommended:

```sh
sudo pacman -S --needed \
  networkmanager wireplumber bluez-utils brightnessctl \
  wl-clipboard cliphist glib2 xdg-utils spectacle
```

The first group is required by the default build. The second group is optional
per feature and provides networking, audio, Bluetooth, brightness, clipboard
history, trash/file operations, and screenshots. Set
`KOS_BUILD_KWIN_PLUGINS=OFF` to build only the platform service and Settings
without the KWin plugin development packages.

`extra-cmake-modules` is a direct CMake dependency of the KWin plugins.
`vulkan-headers` supplies the `Vulkan::Vulkan` compile interface exported by
KWin; Arch's `kwin` package does not currently pull it in automatically, so it
must be listed explicitly. KWin also exports Wayland, libdrm, and libepoxy
development interfaces, but those are hard dependencies of Arch's `kwin`
package and do not need to be repeated here.

### Ubuntu 26.04 (resolute)

`kosctl` installs missing build packages automatically on Arch and NixOS only.
On Ubuntu, install them manually. The list below has been verified with a full
default build on 26.04.

Quickshell 0.3.x is not in the Ubuntu archive yet; use the PPA recommended by
the [Quickshell documentation](https://quickshell.org/docs/), which provides a
`resolute` series:

```sh
sudo add-apt-repository ppa:avengemedia/danklinux
sudo apt update
sudo apt install quickshell
```

Core and KWin plugin build dependencies:

```sh
sudo apt install \
  git cmake ninja-build g++ golang-go \
  qt6-base-dev qt6-declarative-dev \
  libkf6windowsystem-dev libkf6iconthemes-dev libkf6globalaccel-dev \
  extra-cmake-modules kwin-dev libkf6config-dev libkf6i18n-dev \
  libkf6guiaddons-dev libkf6kcmutils-dev libkf6coreaddons-dev \
  libkdecorations3-dev gettext libvulkan-dev libplasma-dev \
  libkf6kio-dev libkf6calendarcore-dev \
  libxcb1-dev libxcb-composite0-dev libxcb-randr0-dev libxcb-res0-dev \
  libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-damage0-dev \
  libxcb-render0-dev libxcb-shape0-dev libxcb-cursor-dev \
  libxcb-keysyms1-dev libxcb-icccm4-dev libxcb-image0-dev \
  libxcb-util-dev libxkbcommon-x11-dev
```

Optional runtime integrations (mirroring the Arch list above):

```sh
sudo apt install \
  network-manager wireplumber bluez brightnessctl \
  wl-clipboard cliphist xdg-utils kde-spectacle \
  libglib2.0-0 qml6-module-qtquick-dialogs libqt6sql6-sqlite
```

Key naming differences versus Arch: `kdecoration` is `libkdecorations3-dev`,
`vulkan-headers` is `libvulkan-dev`, and `spectacle` is `kde-spectacle`.
Also note: `libplasma-dev` provides `Plasma/plasma_version.h` used by the
glass effect; `libkf6kio-dev` and `libkf6calendarcore-dev` are direct CMake
dependencies of the platform service and Settings (on Arch they arrive
through the dependency chain); the xcb extension headers required by KWin's
exported headers (composite, randr, res, shm, sync) are not pulled in by
`kwin-dev` and must be installed explicitly; `qml6-module-qtquick-dialogs`
and `libqt6sql6-sqlite` are runtime dependencies of QuickDialogs2 and the
data service.

Calendar, Todo, Weather, and Music are separate optional applications and are
not built by `kosctl install`. They have additional Qt/KF6, GStreamer, TagLib,
or Go dependencies; read [apps/README.md](apps/README.md) and each app's own
documentation before running `./tools/install-apps.sh`.

Install equivalent packages on other distributions. See the
[Quickshell documentation](https://quickshell.org/docs/) for Quickshell.

### 2. Clone the repository

```sh
git clone git@https://github.com/SuceV587/NextKde.git
cd NextKde
```

### 3. Check and install

```sh
./tools/kosctl doctor
./tools/kosctl install
./tools/kosctl start
```

`doctor` checks commands, Arch packages, and optional runtime integrations. On
Arch, `install` offers to install missing required build packages before it
builds KOS; the
first KWin-plugin installation may ask for your sudo password. `start` applies
the new version immediately and briefly refreshes the desktop UI.

KOS starts automatically after later logins.

### 4. First setup

KOS provides notifications. Remove Plasma's **Notifications** widget from the
panel or system tray first, otherwise Plasma owns the notification service.
KOS does not change your existing panel layout automatically.

## Screenshots

Full desktop with DeskCenter, the floating dock, and system status.

![KOS full desktop](docs/images/full-desktop.png)

Fullscreen launcher for app search and grid launch.

![KOS fullscreen launcher](docs/images/fullscreen-launcher.png)

Control center for networking, Bluetooth, brightness, volume, and notifications.

![KOS control center](docs/images/control-center.png)

Settings center for display, theme, bar, dock, launcher, shortcuts, and
integration status.

![KOS settings center](docs/images/settings-center.png)

## Daily use

### Update

```sh
git pull
./tools/kosctl install
./tools/kosctl start
```

### Check service status

If a feature such as brightness or networking stops updating, run:

```sh
systemctl --user status kos-platform.service kos-data.service kos-shell.service
```

Follow service logs with:

```sh
journalctl --user -u kos-platform.service -u kos-data.service -f
```

### Uninstall

```sh
./tools/kosctl uninstall
```

This removes KOS services and installed files. Personal state such as dock pins
and appearance preferences remains available for a later reinstall.

## Main features

| Area                      | What it does                                                                                                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Desktop widgets           | Shows a clock, weather forecast, calendar, CPU/memory/temperature, uptime, app usage, and media playback information.                                                                       |
| Floating dock and top bar | Shows pinned and running apps with window previews, launch animation, auto-hide, system tray, network, battery, and temperature status. The top-bar status can be integrated into the dock. |
| Launcher and search       | Provides a fullscreen app grid, application search, window search, and quick access to frequent apps.                                                                                       |
| Control center            | Manages Wi-Fi, Bluetooth, brightness, volume, media playback, dark mode, Do Not Disturb, screenshots, lock, suspend, logout, restart, and power off.                                        |
| Desktop files             | Shows desktop files and folders with open, rename, delete, copy, cut, and Open With actions.                                                                                                |
| Appearance and motion     | Offers liquid glass, background blur, theme colors, dock position, icon style, and display mode. KWin plugins power dock and window animation.                                              |
| Settings and shortcuts    | A standalone settings center configures appearance, the dock, bar, and launcher; global shortcuts can be installed and changed in KDE System Settings.                                      |

### Optional standalone applications

The repository also includes independent Qt Quick applications for Calendar,
Todo, Weather, and local Music. They are not built with the Shell by default.
Use `apps-dev` or `apps-release` to build all four, or the `calendar-dev`,
`todo-dev`, `weather-dev`, and `music-dev` presets for one application:

```sh
cmake --preset apps-dev
cmake --build --preset apps-dev
ctest --preset apps-dev
```

Run `./tools/install-apps.sh` for a per-user install and service registration.
See [apps/README.md](apps/README.md) for dependencies and module details. Weather
shares the `kos-data-service` Open-Meteo cache with the Shell; Calendar and Todo
share the on-demand PIM service.

KOS does not replace KDE Plasma. It reuses KWin, NetworkManager, PipeWire,
BlueZ, and systemd, then presents those system capabilities in its own UI.

## Architecture at a glance

```text
Quickshell Shell ──► kos-platform ──► KWin / network / audio / Bluetooth
                 └─► kos-data-service ──► system metrics and desktop data
```

- `shell/`: UI code.
- `platform/`: system adapters for KWin, networking, audio, and brightness.
- `services/data-service/`: system metrics, history, desktop data, and weather cache.
- `integrations/kwin/`: KWin plugins; `vendor/`: third-party Glass source.

See [docs/ProjectArchitecture.md](docs/ProjectArchitecture.md) for details.

## Next steps

- Better per-screen layouts and settings for multi-monitor setups.
- Complete the DeskCenter theme integration.
- Expand settings, shortcuts, and standalone apps.
- Improve keyboard navigation, accessibility, and high-contrast support.

## Development and debugging

Preview the UI without installing it (reuses installed services):

```sh
qs -p "$PWD/shell"
```

To debug source QML, run this in one terminal and leave it running; press
`Ctrl+C` to stop it:

```sh
./tools/kosctl dev
```

It starts only the source QML and reuses systemd's `kos-platform.service` and
`kos-data.service`. It does not build, deploy, restart services, or create a
second socket pair.

Settings opened from the source Shell's gear automatically targets that same
source session. You can also launch it manually from a second terminal:

```sh
KOS_SHELL_DIR="$PWD/shell" kos-settings
```

Do not combine `qs -c` and `qs -p`: they are mutually exclusive. A Settings
app opened separately from the desktop menu still targets the installed Shell;
use the source Shell's gear or the command above while debugging.

Apply QML-only changes to an installed copy:

```sh
./tools/kosctl sync
./tools/kosctl start
```

After changing C++, Go, or KWin plugins:

```sh
./tools/kosctl install
./tools/kosctl start
```

`start` applies Shell, platform-service, and data-service updates immediately.
Updated KWin effect binaries load after the next logout/login or reboot; this
avoids hot-replacing plugins inside the running compositor.

Useful commands:

```sh
./tools/kosctl doctor
./tools/kosctl run
./tools/kosctl dev
./tools/kosctl shortcuts install
./tools/kosctl glass-settings
```

Architecture and test documentation lives in [docs/](docs/). Before
contributing, at minimum run:

```sh
git diff --check
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
```

## License

This project uses the license declared by its repository. The bundled Glass
effect is licensed at [vendor/kwin-effects-glass/LICENSE](vendor/kwin-effects-glass/LICENSE).
