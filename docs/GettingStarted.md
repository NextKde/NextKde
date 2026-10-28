# Installation and everyday use

[简体中文](GettingStarted.zh-CN.md)

Use a KDE Plasma 6 **Wayland** session, KWin 6.6+, Quickshell 0.3.x and Qt 6.6+ with matching
KF6/KWin development packages. Native plugins must match the running compositor ABI.
See [release notes](releases/v0.1.1.md) for actual tested environments; package recipes below
are not proof that every distro has passed end-to-end acceptance. Contributor verification is VM/CI only.
Run as the logged-in desktop user, not `sudo ./tools/kosctl`; commands are from the repository root.

## 1. Install requirements

Source selection needs Git and Python 3.9+. Core builds require CMake, Ninja, C++20, Go, Qt/KF6,
Wayland and KWin development dependencies. `kosctl doctor` reports missing prerequisites;
`install` can install build packages on Arch/Debian-family systems. Fedora packages are manual.
Install Quickshell 0.3.x from an appropriate distribution source or its
[upstream instructions](https://quickshell.org/docs/); package availability varies.

### Arch Linux

```sh
sudo pacman -S --needed \
  git quickshell cmake ninja gcc qt6-base qt6-declarative \
  qt6-tools qt6-translations qt6-quick3d qt6-svg qt6-imageformats qt6-5compat qt6-wayland \
  go curl extra-cmake-modules wayland kwindowsystem kiconthemes kglobalaccel \
  kio patchelf kwin kconfig ki18n kguiaddons kcmutils \
  kcoreaddons kdecoration gettext libxcb vulkan-headers
```

### Debian 13 (trixie)

The wrapper supports checking and selecting stable or an explicit version:

```sh
bash tools/install-debian13.sh --check
bash tools/install-debian13.sh --version v0.1.0 --start
```

The tag above is an existing historical example; choose the current published release.
Omit `--version` for Latest; use `--version main` only for development. Do not infer native
Debian acceptance from the wrapper being tested in Ubuntu. Missing distro SDK versions can still
prevent a build. The wrapper belongs to the logged-in user and keeps its prefix under HOME.
Manual dependency reference for Debian-family systems:

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

### Ubuntu 26.04 (resolute)

Use the Debian-family package reference above and `kosctl doctor`. Actual final release acceptance
has used Kubuntu/Ubuntu 26.10, not every Ubuntu release. Match SDK/runtime versions and check
Quickshell availability before installing.

### Fedora 44 (community-contributed)

There is no automatic dnf dependency branch in kosctl; install prerequisites manually.
This community recipe is not official Fedora runtime acceptance:

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

Qt private headers are separate packages; add `qt6-qtdeclarative-private-devel` if QuickPrivate
is missing. Fedora uses a single `libxcb-devel`, unlike Debian's split extension packages.

### openSUSE Tumbleweed (community-contributed)

Tumbleweed does not currently provide Quickshell 0.3.x in its default repositories. Add the signed
DankLinux OBS repository, then install Quickshell with the build dependencies:

```sh
sudo zypper addrepo --refresh --priority 120 \
  https://download.opensuse.org/repositories/home:/AvengeMedia:/danklinux/openSUSE_Tumbleweed/ \
  danklinux-obs
sudo zypper refresh danklinux-obs

sudo zypper install \
  quickshell \
  git python313 cmake ninja gcc-c++ go curl patchelf \
  pkgconf-pkg-config gettext-tools \
  qt6-base-common-devel qt6-declarative-devel qt6-declarative-imports \
  qt6-tools-devel qt6-linguist-devel qt6-translations \
  qt6-quick3d-devel qt6-quick3d-imports qt6-svg-devel qt6-imageformats \
  qt6-wayland-devel qt6-wayland-imports \
  qt6-qt5compat-devel qt6-qt5compat-imports \
  qt6-base-private-devel qt6-declarative-private-devel \
  kf6-extra-cmake-modules \
  wayland-devel wayland-protocols-devel \
  libxkbcommon-devel libxkbcommon-x11-devel \
  kf6-kwindowsystem-devel kf6-kiconthemes-devel kf6-kglobalaccel-devel \
  kf6-kio-devel kf6-kcalendarcore-devel kf6-kconfig-devel kf6-ki18n-devel \
  kf6-kguiaddons-devel kf6-kcmutils-devel kf6-kcoreaddons-devel \
  kwin6-devel kdecoration6-devel libplasma6-devel \
  libdrm-devel libgbm-devel libepoxy-devel libxcb-devel libX11-devel \
  vulkan-devel zlib-devel
```

Current Tumbleweed installs the libxkbcommon headers below `/usr/include/libxkbcommon`; export that
prefix before building. Quickshell must also match the installed Qt version, including after a
Tumbleweed Qt update.

```sh
export CPATH="/usr/include/libxkbcommon${CPATH:+:$CPATH}"
git clone --depth 1 https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/kosctl update main
./tools/kosctl doctor
./tools/kosctl install
./tools/kosctl start
```

Log out and back in after installation so KWin loads the new effects and decoration.

### Optional integrations and spatial wallpaper

NetworkManager, WirePlumber/PipeWire, BlueZ, brightnessctl, wl-clipboard/cliphist, xdg-utils and
Spectacle supply per-feature integration. Package names differ by distro.
`KOS_BUILD_KWIN_PLUGINS=OFF` omits native effects/decoration for limited development builds.

`KOS_BUILD_SPATIAL=AUTO` is default. Direct CMake builds when OpenCV/ONNX are available; kosctl
on Arch/Debian installs OpenCV and prepares a pinned ONNX SDK when possible. AUTO can skip on
SDK preparation failure; ON requires success. OFF skips discovery/preparation:

```sh
KOS_BUILD_SPATIAL=OFF ./tools/kosctl install
```

Keep the environment choice for later reinstalls if desired. x86_64 can use the cached SDK;
other architectures need installed ONNX development libraries. Models download separately when
enabled in Settings. A built worker does not prove full model download/inference acceptance.

## 2. Select and install

```sh
git clone --depth 1 https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/kosctl update &&
./tools/kosctl doctor &&
./tools/kosctl install &&
./tools/kosctl start
```

Default update selects GitHub Latest official Release; `update main` explicitly selects development.
Selection stops on dirty sources or fetch/API errors. It only changes source; install deploys the
checkout and start applies services. `kosctl version` distinguishes Installed and Source.
New KWin plugins and desktop takeover require logout/login or reboot.
Shallow source selection avoids historical process assets; an existing full clone retains its history.

## Optional standalone applications

```sh
./tools/kosctl install apps
```

Installs Calendar, Calculator, Todo and Weather into `~/.local` by default. Requires Qt 6.5+,
compatible KF6 and Go 1.26+; it checks selected dependencies without sudo package installation.
No ListenFree/SDK build or audio association migration occurs. Even an old enabled CMake cache
is reset to OFF. Apps installation leaves core Settings/runtime QML untouched and works without core.

```sh
./tools/kosctl install apps --with-listenfree
```

Explicit audio opt-in adds Qt 6.10+ and the [ListenFree dependencies](../apps/listenfree/packaging/linux/README.md),
prepares its SDK, registers it and migrates legacy Music. `KOS_LISTENFREE_SDK` can select an existing
SDK only when opting in. `apps-dev`/`apps-release` select the standard four. Legacy Music is no
longer built; standard upgrades preserve an existing player, library and audio associations.
Calculator currency conversion uses a dated offline reference, not live rates.
See [apps](../apps/README.md) for per-app details.

## Desktop takeover and optional lockscreen

Core installs `org.kos.desktop` and saves Plasma's previous ShellPackage before selecting the
wallpaper-only desktop. DeskCenter owns files; Plasma no longer duplicates panels/folder view.
Changes apply next login; uninstall restores the prior shell. KOS's notification owner can be
blocked by another notification daemon, so inspect the reported D-Bus owner if notifications are empty.

```sh
./tools/kosctl install lockscreen
./tools/kosctl uninstall lockscreen
```

Lockscreen is optional and separate from core. Core uninstall also removes an installed KOS skin.
The SDDM theme has no supported installer; old system theme leftovers require the printed manual
recovery instructions. Do not restart a display manager during an active user session without
accounting for session termination.

## Daily use

```sh
./tools/kosctl update &&
./tools/kosctl install &&
./tools/kosctl start
./tools/kosctl version
systemctl --user status kos-platform.service kos-data.service kos-shell.service
journalctl --user -u kos-platform.service -u kos-data.service -u kos-shell.service -f
```

Before upgrading, back up personal data. Managed runtime/config backups live in
`${XDG_STATE_HOME:-$HOME/.local/state}/kos/install-backups/`; they do not cover all system plugins,
dependencies or application data. Deployment is not atomic. See [rollback constraints](Releasing.md#backups-and-rollback)
for reinstalling a compatible old tag and restoring configuration with services stopped.

```sh
./tools/kosctl uninstall
```

Core uninstall stops/removes managed files/units and restores Plasma's previous ShellPackage.
Personal state is retained; logout/login or reboot to restore the session. Optional standalone apps
are separate. NixOS uses [declarative flake installation](nixos-quickstart.md), not source updates in store.
