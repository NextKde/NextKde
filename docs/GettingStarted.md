# Installation & everyday use

[← NextKDE](../README.md) · [中文](../README.zh-CN.md)

Run the commands in this guide from the repository root unless stated otherwise.

## Get started

### 1. Install requirements

Use a KDE Plasma 6 **Wayland** session (KWin 6.6 or newer), Quickshell 0.3.x,
Qt 6.6 or newer, and the complete KF6 and KWin development dependencies. The
default installation builds the platform service, Settings, KWin effects, and
the window decoration.

On Arch:

```sh
sudo pacman -S --needed \
  git quickshell cmake ninja gcc qt6-base qt6-declarative \
  qt6-tools qt6-translations qt6-quick3d qt6-svg qt6-imageformats qt6-5compat qt6-wayland \
  go curl extra-cmake-modules wayland kwindowsystem kiconthemes kglobalaccel \
  kio patchelf kwin kconfig ki18n kguiaddons kcmutils \
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

### Debian 13 (trixie)

`kosctl` installs missing build packages automatically on Debian too, through
`apt-get`: `./tools/kosctl doctor` reports every gap and
`./tools/kosctl install` fills it in.

Going from a clean machine to a running desktop — **including the clone** — takes a single
script, which walks through the environment check, sudo setup, proxy detection, Quickshell
and dependency installation, cloning, building, installing and verification:

```sh
bash tools/install-debian13.sh --check         # check only, changes nothing (no sudo)
bash tools/install-debian13.sh                 # install
bash tools/install-debian13.sh --all --start   # also install the standalone apps and lock screen, then apply
```

Run it as your **logged-in desktop user**, never through `sudo`: the shell configuration
lands in `~/.config/quickshell/kos`, the services are systemd *user* units, and the desktop
takeover edits `~/.config/plasma-*-appletsrc` — all of them belong to your own `HOME`. So
`KOS_PREFIX` defaults to `$HOME/.local`, and the script refuses a prefix outside `HOME`.

During the build, `kosctl` fetches a pinned ONNX Runtime SDK from GitHub with curl
when spatial support is enabled and OpenCV is available (or spatial support is forced).
`KOS_BUILD_SPATIAL=OFF` skips it. On networks that cannot reach GitHub directly, the script
detects a local proxy and hands it to git and the build only — apt stays direct, which is
faster against a domestic mirror.

Where Debian differs from Arch — and where a Debian build usually gets stuck:

- Debian's `kwin-dev` does **not** bring the libdrm and libgbm development
  files the way Arch's `kwin` package does. `libdrm-dev` and `libgbm-dev` must
  be named explicitly, or CMake stops with `Could NOT find Libdrm`.
- The xcb extension headers KWin exports (composite, randr, res, shm, sync, ...)
  are not pulled in by `kwin-dev` either.
- glib finished its time_t transition in trixie (`libglib2.0-0` became
  `libglib2.0-0t64`). `kosctl` picks whichever name the archive actually has;
  install the `t64` name by hand.
- The glass effect builds with `-DGLASS_X11=OFF` and looks for X11 with
  `QUIET`, so the X11 Xlib headers are not a build requirement.
- **Quickshell 0.3.x is not in the trixie main archive**, but
  `trixie-backports` ships 0.3.0 — the only route that needs no third-party
  source: `sudo apt install -t trixie-backports quickshell`. Otherwise build it
  from source following the
  [Quickshell documentation](https://quickshell.org/docs/), temporarily enable
  a sid source, or use the Ubuntu PPA shown below. `doctor` prints a hint when
  it is missing.

Manual install, equivalent to what the script does:

```sh
sudo apt install \
  git cmake ninja-build g++ golang-go curl patchelf \
  pkg-config extra-cmake-modules libwayland-dev wayland-protocols libxkbcommon-dev qt6-base-dev qt6-declarative-dev \
  qt6-tools-dev qt6-l10n-tools qt6-translations-l10n qt6-quick3d-dev qt6-svg-dev qt6-wayland-dev qt6-image-formats-plugins \
  qt6-5compat-dev libqt6svg6 qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs qml6-module-qtquick-window \
  qml6-module-qtquick-effects qml6-module-qtqml-models qml6-module-qtqml-workerscript qml6-module-qt5compat-graphicaleffects libkf6windowsystem-dev libkf6iconthemes-dev libkf6globalaccel-dev \
  libkf6kio-dev libkf6calendarcore-dev kwin-dev libdrm-dev libgbm-dev libepoxy-dev libxkbcommon-x11-dev \
  libkf6config-dev libkf6i18n-dev libkf6guiaddons-dev libkf6kcmutils-dev libkf6coreaddons-dev libkdecorations3-dev libplasma-dev \
  gettext libvulkan-dev zlib1g-dev libxcb1-dev libxcb-composite0-dev libxcb-randr0-dev libxcb-res0-dev \
  libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-damage0-dev libxcb-render0-dev libxcb-shape0-dev libxcb-cursor-dev \
  libxcb-keysyms1-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-util-dev
```

Optional runtime integrations:

```sh
sudo apt install \
  network-manager wireplumber bluez brightnessctl \
  wl-clipboard cliphist xdg-utils kde-spectacle \
  libglib2.0-0t64 qml6-module-qtquick-dialogs libqt6sql6-sqlite
```

### Ubuntu 26.04 (resolute)

`kosctl` installs missing build packages automatically on Arch, Debian-family
systems (Ubuntu included) and NixOS. The list below mirrors what the script
installs, for manual cross-checking; it has been verified with a full default
build on 26.04.

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
  git cmake ninja-build g++ golang-go curl patchelf \
  pkg-config extra-cmake-modules libwayland-dev wayland-protocols libxkbcommon-dev qt6-base-dev qt6-declarative-dev \
  qt6-tools-dev qt6-l10n-tools qt6-translations-l10n qt6-quick3d-dev qt6-svg-dev qt6-wayland-dev qt6-image-formats-plugins \
  qt6-5compat-dev libqt6svg6 qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs qml6-module-qtquick-window \
  qml6-module-qtquick-effects qml6-module-qtqml-models qml6-module-qtqml-workerscript qml6-module-qt5compat-graphicaleffects libkf6windowsystem-dev libkf6iconthemes-dev libkf6globalaccel-dev \
  libkf6kio-dev libkf6calendarcore-dev kwin-dev libdrm-dev libgbm-dev libepoxy-dev libxkbcommon-x11-dev \
  libkf6config-dev libkf6i18n-dev libkf6guiaddons-dev libkf6kcmutils-dev libkf6coreaddons-dev libkdecorations3-dev libplasma-dev \
  gettext libvulkan-dev zlib1g-dev libxcb1-dev libxcb-composite0-dev libxcb-randr0-dev libxcb-res0-dev \
  libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev libxcb-damage0-dev libxcb-render0-dev libxcb-shape0-dev libxcb-cursor-dev \
  libxcb-keysyms1-dev libxcb-icccm4-dev libxcb-image0-dev libxcb-util-dev
```

Optional runtime integrations (mirroring the Arch list above):

```sh
sudo apt install \
  network-manager wireplumber bluez brightnessctl \
  wl-clipboard cliphist xdg-utils kde-spectacle \
  libglib2.0-0t64 qml6-module-qtquick-dialogs libqt6sql6-sqlite
```

Key naming differences versus Arch: `kdecoration` is `libkdecorations3-dev`,
`vulkan-headers` is `libvulkan-dev`, `spectacle` is `kde-spectacle`, and
`glib2` is `libglib2.0-0t64` (the canonical name after the time_t transition;
`libglib2.0-0` may still exist in some releases as a transitional package,
but install the `t64` name).
Also note: `libplasma-dev` provides `Plasma/plasma_version.h` used by the
glass effect; `libkf6kio-dev` and `libkf6calendarcore-dev` are direct CMake
dependencies of the platform service and Settings (on Arch they arrive
through the dependency chain); the xcb extension headers required by KWin's
exported headers (composite, randr, res, shm, sync) are not pulled in by
`kwin-dev` and must be installed explicitly; `qml6-module-qtquick-dialogs`
and `libqt6sql6-sqlite` are runtime dependencies of QuickDialogs2 and the
data service.

### Fedora 44 (community-contributed)

> Community-contributed and verified on Fedora 44 (KDE Plasma 6.7.5 / Qt 6.11.2).
> It is **not** part of the official tested matrix (Arch / Debian 13 / Ubuntu 26.04 / NixOS).
> `kosctl doctor` only has Arch, Debian-family and NixOS package checks — there is **no
> `dnf` branch**. On Fedora it verifies that the required *commands* exist but does **not**
> report or install missing `-devel` packages, so you must install the build dependencies by
> hand; a missing package only surfaces later as a CMake `Could NOT find …` error during
> `kosctl install`.

Quickshell 0.3.x is not in the Fedora repositories; enable the community COPR and install it
(the COPR publishes builds for Fedora 44 x86_64):

```sh
sudo dnf copr enable errornointernet/quickshell
sudo dnf install quickshell
```

Core and KWin-plugin build dependencies:

```sh
sudo dnf install \
  git cmake ninja-build gcc-c++ golang curl patchelf pkgconf-pkg-config gettext \
  extra-cmake-modules \
  wayland-devel wayland-protocols-devel libxkbcommon-devel \
  qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qttools-devel qt6-qtquick3d-devel \
  qt6-qtsvg-devel qt6-qtwayland-devel qt6-qtimageformats qt6-qt5compat-devel \
  qt6-qtbase-private-devel \
  kf6-kwindowsystem-devel kf6-kiconthemes-devel kf6-kglobalaccel-devel \
  kf6-kio-devel kf6-kcalendarcore-devel kf6-kconfig-devel kf6-ki18n-devel \
  kf6-kguiaddons-devel kf6-kcmutils-devel kf6-kcoreaddons-devel \
  libplasma-devel kdecoration-devel \
  kwin-devel libdrm-devel mesa-libgbm-devel libepoxy-devel \
  vulkan-headers vulkan-loader-devel zlib-devel libxcb-devel
```

> **Qt private headers are a separate `*-private-devel` package.** NextKde's native KWin
> components (`shell/native/surface-shape`) need `Qt6GuiPrivate`, provided by
> `qt6-qtbase-private-devel`. Without it `kosctl install` aborts at CMake configure with
> `Could NOT find Qt6GuiPrivate ... /usr/lib64/cmake/Qt6GuiPrivate/Qt6GuiPrivateConfig.cmake
> does NOT exist`. If you later see `Failed to find required Qt component "QuickPrivate"`,
> also install `qt6-qtdeclarative-private-devel`. Every `Qt6*Private` component follows this
> `*-private-devel` pattern on Fedora.

Optional runtime integrations:

```sh
sudo dnf install \
  NetworkManager wireplumber bluez brightnessctl \
  wl-clipboard cliphist xdg-utils spectacle
```

Key naming differences versus Arch/Debian:

- KF6 framework `-devel` packages keep the `kf6-` prefix (`kf6-kwindowsystem-devel`,
  `kf6-kiconthemes-devel`, …), **except** `libplasma` → `libplasma-devel` and
  `kdecoration` → `kdecoration-devel` — there is no `kf6-libplasma-devel` or
  `kf6-kdecoration-devel`.
- Fedora ships **no** `libxcb-*-devel` split packages (the Debian `libxcb-*-dev` layout does
  not apply). Every xcb extension header (composite, randr, res, shm, sync, xfixes, …) comes
  from the single `libxcb-devel` package — do not try `libxcb-composite-devel` etc. (`dnf`
  reports `No match`).
- `kwin-devel` pulls in libdrm/libgbm/libepoxy/Wayland development files transitively on
  Fedora, but they are listed above for clarity. `qt6-qtimageformats` and `qt6-qt5compat-devel`
  are the equivalents of Debian's `qt6-image-formats-plugins` / `qt6-5compat-dev`.

Build tips:

- Set `KOS_BUILD_SPATIAL=OFF` (export it, or prefix the install command) to skip the ~1 GB
  ONNX Runtime SDK download and avoid needing `opencv-devel`. The
  `Depth engine skipped: OpenCV or the ONNX Runtime is not installed` line is expected in this
  mode, not an error.
- The repeated `KDEInstallDirs … got its value from CMAKE_INSTALL_*` warnings during configure
  are harmless (a GNUInstallDirs / KDE macro load-order quirk) — ignore them.
- After a successful install the three `kos-*.service` units are enabled and start
  automatically on your next login; verify with
  `systemctl --user status kos-platform.service kos-data.service kos-shell.service`.

### Spatial wallpapers (optional)

`KOS_BUILD_SPATIAL` controls the depth engine and Qt Quick 3D wallpaper plugin:

| Mode | Direct CMake configuration | `kosctl install` on Arch / Debian-family systems |
| :--- | :--- | :--- |
| `AUTO` (default) | Builds when OpenCV and ONNX Runtime are available; otherwise skips. | Includes OpenCV in dependency installation and prepares a pinned ONNX SDK when OpenCV is available. SDK preparation failure allows AUTO to skip the depth engine. |
| `ON` | Requires both dependencies; configuration fails if they are missing. | Installs the required OpenCV package and requires ONNX SDK preparation to succeed. |
| `OFF` | Skips dependency discovery and the spatial components. | Omits the spatial dependency packages and SDK preparation. |

On x86_64, `kosctl` downloads and caches the SDK if it is not already cached.
Other architectures require installed ONNX Runtime development headers and libraries.
Nix builds obtain their dependencies from the Nix package definitions.
The depth models are separate: they download to the user cache when spatial
wallpapers are first enabled in Settings, not during the core install.

To install without spatial wallpapers:

```sh
KOS_BUILD_SPATIAL=OFF ./tools/kosctl install
```

Export `KOS_BUILD_SPATIAL=OFF` in your shell configuration to keep that choice
for later installs. Merely removing OpenCV does not keep it out of the default
`kosctl install`, which may install it again.

### Optional standalone applications

Calendar, Todo, Weather, and ListenFree are not built by the core
`kosctl install`. The default application bundle requires Qt 6.10+, compatible
KF6 libraries, Go 1.26+, and the audio dependencies documented in
[apps/README.md](../apps/README.md) and the
[ListenFree Linux build guide](../apps/listenfree/packaging/linux/README.md).

```sh
./tools/kosctl install apps
```

This invokes `tools/install-apps.sh`, checks dependencies, and prepares the
private ListenFree SDK. The legacy local Music app remains available through
`music-dev`; it is disabled in the default application installer.

Install equivalent packages on other distributions. See the
[Quickshell documentation](https://quickshell.org/docs/) for Quickshell.

### 2. Clone the repository

```sh
git clone https://github.com/SuceV587/NextKde.git
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
the new version immediately and briefly refreshes the desktop UI. `install`
installs the KOS decoration together with the KWin plugins and selects KOS on
first installation, saving the previous decoration. In KOS Settings ▸ Window
and animations, turn off KOS window appearance to restore it. Decoration changes
apply at the next login; corner and shadow changes apply immediately. Reinstalling
preserves saved choices. This page includes six corner-radius stops, a shadow
switch, and minimize/restore and close animation choices. Select None to leave
that animation to other enabled KWin effects.
The NixOS module includes the decoration; `kosctl install` applies first-install defaults.

KOS starts automatically after later logins.

### Desktop file takeover (default)

`install` points `plasmashellrc`'s `[Shell] ShellPackage` at the `org.kos.desktop`
shell package that ships with KOS (`~/.local/share/plasma/shells/`): plasmashell
then only draws the wallpaper — the package's `contents/defaults` pins the
desktop containment to the wallpaper-only `org.kde.desktopcontainment`, so
`~/Desktop` is no longer rendered a second time by a folder view, and the Plasma
panel retires as well. Desktop files and interaction belong to DeskCenter
instead of two stacked copies of which one does not respond (issue #90).
**This takes effect at your next login.**

Switching shells makes plasmashell build its own appletsrc (the wallpaper
resets), so `install` migrates the desktop containments from the old appletsrc;
the previous `ShellPackage` value is saved in
`~/.local/share/kos/plasma-shell-state` and written back by `uninstall`.

### Lock screen (optional)

KOS's lock screen is optional and **not installed by default** — optional
components are installed by their own subcommands, and a bare
`install` / `uninstall` only covers the core desktop. The shell package a core
install lays down contains no `contents/lockscreen`, so kscreenlocker keeps
falling back to the default skin: taking over the desktop does not drag the
lock screen in:

```sh
./tools/kosctl install lockscreen   # lock screen (per-user, no root)
./tools/kosctl install apps         # optional standalone apps (= tools/install-apps.sh)

./tools/kosctl uninstall lockscreen # remove only the lock screen
```

The **lock screen** (`apps/lockscreen`, a kscreenlocker skin package) installs
to `~/.local/share/plasma/shells/org.kos.desktop` and
`~/.local/share/plasma/look-and-feel/org.kos.desktop`, and points
`plasmashellrc`'s `[Shell] ShellPackage` at `org.kos.desktop`. Note that the
greeter resolves skin packages from `plasma/shells/` only — `look-and-feel/`
does nothing for it (reasons and a verification script in
[apps/lockscreen/tests/theme-resolution](../apps/lockscreen/tests/theme-resolution));
both directories are populated so `plasma-apply-lookandfeel` and the KDE
settings page can resolve it too. It is pure QML data: after editing QML, run
`./tools/kosctl install lockscreen` to copy it again — a full `install` is not
needed.

While KOS core is still installed, `uninstall lockscreen` only removes the
skin (the greeter falls back to the default lock screen) and leaves the shell
package and the desktop takeover alone; `uninstall` is what removes the shell
package and restores the `ShellPackage` key to its pre-install value.

### SDDM login screen: not available for now

`apps/sddm` is KOS's SDDM login theme, but `kosctl install sddm` has been
**removed for now** because the greeter integration still has problems: there
is no install entry point, and the theme source stays in the repository until
it is fixed.

It used to do two things: copy the theme to `/usr/share/sddm/themes/kos` and
select it in `/etc/sddm.conf.d/kos-theme.conf` (`[Theme] Current=kos`) — both
in the system prefix, hence root. To preview it you have to run it by hand:

```sh
sddm-greeter --test-mode --theme apps/sddm   # if the window renders, consider restoring the install
```

If an older kosctl installed that theme, uninstall no longer cleans it up (that
would need root), but `./tools/kosctl uninstall` prints a message when it finds
the leftovers. If the login screen goes black or refuses your password, switch
to a TTY with Ctrl+Alt+F2 (or F3/F4…) and log in there, then delete the theme
selection file and restart the display manager to get the previous theme back:

```sh
sudo rm /etc/sddm.conf.d/kos-theme.conf
sudo systemctl restart sddm
```

To remove the theme itself: `sudo rm -rf /usr/share/sddm/themes/kos`.

### 4. First setup

Notifications need no configuration. The installer's desktop takeover leaves
plasmashell drawing only the wallpaper, so it no longer creates a notification
service and `org.freedesktop.Notifications` belongs to KOS — Settings shows
the current owner.

The one thing to watch is a third-party daemon (dunst, mako, swaync, …): if it
starts first it holds that name, KOS cannot take it back, and the notification
centre stays empty. `install` warns when such a daemon is installed or already
registered on the bus; disable it as the warning says.

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

This stops and removes KOS files and services; personal state such as dock pins
and appearance preferences is kept. An optionally installed lock screen goes
away with it, and `plasmashellrc`'s `ShellPackage` is restored to its
pre-install value (plasmashell reloads the previous shell at your next login);
the shell package is kept only when that key cannot be written back — a
`ShellPackage` naming a package that is no longer there makes plasmashell
refuse to start (`starting invalid corona`). You can also remove only the lock
screen: `./tools/kosctl uninstall lockscreen`.
If an SDDM theme installed by an older kosctl is detected, uninstall prints the
command to delete it by hand (see "SDDM login screen: not available for now"
above).

### NixOS: declarative installation

1. Add the input under `inputs` in your system `flake.nix`:

```nix
nextkde = {
  url = "git+https://github.com/SuceV587/NextKde.git";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

2. Pass `inputs` to your NixOS modules with
   `specialArgs = { inherit inputs; };` in your `nixpkgs.lib.nixosSystem` call.
   Then import the KOS module and enable it in your NixOS configuration:

```nix
{ inputs, ... }:
{
  imports = [ inputs.nextkde.nixosModules.kos ];
  services.kos = {
    enable = true;
    weather.enable = true; # Optional standalone Weather app
  };
}
```

3. Update the input and rebuild **after** adding the module and options.
   Replace `your-host` with your `nixosConfigurations` attribute:

```sh
nix flake update nextkde
sudo nixos-rebuild switch --flake .#your-host
```

Set `services.kos.enable = false;` and rebuild to disable the declarative
services. See the [NixOS guide](nixos-quickstart.md) for other installation modes.
