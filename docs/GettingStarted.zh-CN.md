# 安装与日常使用

[English](GettingStarted.md)

使用 KDE Plasma 6 **Wayland**、KWin 6.6+、Quickshell 0.3.x、Qt 6.6+，开发包需匹配 KF6/KWin，原生插件匹配合成器 ABI。
[发布说明](releases/v0.1.1.zh-CN.md)列出实际实测环境；以下包配方不代表所有系统端到端通过。
贡献者验证只在 VM/CI。以已登录桌面用户操作，不 `sudo ./tools/kosctl`；命令位于仓库根目录。

## 1. 安装依赖

选源码需要 Git、Python 3.9+，核心构建需要 CMake、Ninja、C++20、Go、Qt/KF6、Wayland、KWin 开发依赖。
`doctor` 报告缺项，Arch/Debian 系 `install` 可装构建包；Fedora 手工安装。
Quickshell 0.3.x 从合适发行源或[上游说明](https://quickshell.org/docs/)安装，包可用性随发行版变化。

### Arch Linux

```sh
sudo pacman -S --needed \
  git quickshell cmake ninja gcc qt6-base qt6-declarative \
  qt6-tools qt6-translations qt6-quick3d qt6-svg qt6-imageformats qt6-5compat qt6-wayland \
  go curl extra-cmake-modules wayland kwindowsystem kiconthemes kglobalaccel \
  kio patchelf kwin kconfig ki18n kguiaddons kcmutils \
  kcoreaddons kdecoration gettext libxcb vulkan-headers
```

### Debian 13（trixie）

包装脚本可检查并选 stable/精确版本：

```sh
bash tools/install-debian13.sh --check
bash tools/install-debian13.sh --version v0.1.0 --start
```

示例为已存在历史 Tag，实际选最新正式版。省略 `--version` 为 Latest，开发才用 `--version main`。
Ubuntu 跑通包装脚本不代表 Debian 原生验收，发行版 SDK 不足仍可能构建失败。包装脚本以桌面用户运行，前缀位于 HOME。
Debian 系手工依赖参考：

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

### Ubuntu 26.04（resolute）

用上方 Debian 系包参考及 `kosctl doctor`，最终发行实测采用 Kubuntu/Ubuntu 26.10，并非所有 Ubuntu。
先确认 SDK/运行库匹配及 Quickshell 可用。

### Fedora 44（社区提供）

kosctl 没有自动 dnf 分支，手工装依赖。此社区配方不代表官方 Fedora 运行验收：

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

Qt 私有头独立打包，缺 QuickPrivate 时补 `qt6-qtdeclarative-private-devel`；Fedora 的 `libxcb-devel` 不同于 Debian 拆分包。

### openSUSE Tumbleweed（社区提供）

Tumbleweed 默认软件源目前不提供
Quickshell 0.3.x；先添加带签名的 DankLinux OBS 仓库，再将 Quickshell 与构建依赖一起安装：

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

当前 Tumbleweed 将 libxkbcommon 头文件安装在 `/usr/include/libxkbcommon`，构建前导出该路径。
Tumbleweed 升级 Qt 后，还需确保 Quickshell 与当前 Qt 匹配。

```sh
export CPATH="/usr/include/libxkbcommon${CPATH:+:$CPATH}"
git clone --depth 1 https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/kosctl update main
./tools/kosctl doctor
./tools/kosctl install
./tools/kosctl start
```

安装后注销并重新登录，使 KWin 加载新的特效和窗口装饰。

## 可选集成与空间壁纸

NetworkManager、WirePlumber/PipeWire、BlueZ、brightnessctl、wl-clipboard/cliphist、xdg-utils、Spectacle 提供各功能接入，包名依系统而异。
`KOS_BUILD_KWIN_PLUGINS=OFF` 供有限开发构建跳过特效/装饰器。

空间默认 `AUTO`：直接 CMake 在已有 OpenCV/ONNX 时构建；Arch/Debian 的 kosctl 会装 OpenCV 并尽可能准备固定 ONNX SDK。
AUTO 准备失败可跳过；ON 要求成功；OFF 跳过发现及准备：

```sh
KOS_BUILD_SPATIAL=OFF ./tools/kosctl install
```

若要以后保持同样选择，持续设置该环境变量。x86_64 可用缓存 SDK，其他架构需已安装 ONNX 开发库。
模型在 Settings 启用时另下载，worker 构建不等于完整下载/推理验收。

## 2. 选择版本并安装

```sh
git clone --depth 1 https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/kosctl update &&
./tools/kosctl doctor &&
./tools/kosctl install &&
./tools/kosctl start
```

默认 update 选择 GitHub Latest 正式版，开发需显式 `update main`。脏源码、获取/API 错误即停止。
选源码、install 部署、start 启动分开；`version` 区分 Installed/Source。
KWin 插件及桌面接管需注销登录/重启。浅版本切换不下载旧过程资源，已有完整克隆仍保留历史。

## 可选独立应用

```sh
./tools/kosctl install apps
```

默认 `~/.local` 安装日历、计算器、待办和天气，需 Qt 6.5+、兼容 KF6、Go 1.26+，检查所选依赖但不 sudo 装包。
不构建 ListenFree/SDK、不迁移音频关联；旧 ON 缓存也重置 OFF。应用安装不改核心 Settings/QML，未装核心也可用。

```sh
./tools/kosctl install apps --with-listenfree
```

显式音频需 Qt 6.10+ 及[ListenFree 依赖](../apps/listenfree/packaging/linux/README.md)，准备 SDK、注册并迁移旧 Music。
选音频时可用 `KOS_LISTENFREE_SDK` 指定现有 SDK。`apps-dev`/`apps-release` 只选标准四个。
旧 Music 不再构建，普通升级保留已安装的播放器、曲库和音频关联。
计算器汇率为注明日期离线参考，不是实时。详见[应用](../apps/README.md)。

## 桌面接管与可选锁屏

核心安装 `org.kos.desktop`，保存旧 ShellPackage，再选只绘壁纸的 Plasma 桌面；DeskCenter 负责文件，避免面板/文件视图重复。
下次登录生效，卸载恢复旧 Shell。其他通知守护可能抢占 D-Bus 名称，通知为空检查所报告的持有者。

```sh
./tools/kosctl install lockscreen
./tools/kosctl uninstall lockscreen
```

锁屏可选且与核心分开，核心卸载也会清 KOS skin。SDDM 主题暂无支持的安装入口；旧系统主题残留按打印恢复说明手工处理。
重启显示管理器会终止会话，操作前考虑当前会话。

## 日常使用

```sh
./tools/kosctl update &&
./tools/kosctl install &&
./tools/kosctl start
./tools/kosctl version
systemctl --user status kos-platform.service kos-data.service kos-shell.service
journalctl --user -u kos-platform.service -u kos-data.service -u kos-shell.service -f
```

升级前备份个人数据。管理的运行树/配置备份在 `${XDG_STATE_HOME:-$HOME/.local/state}/kos/install-backups/`，
不含所有插件、依赖、应用数据，部署不是事务。[回退限制](Releasing.zh-CN.md#备份与回退)说明兼容旧 Tag 重装及停服务恢复配置。

```sh
./tools/kosctl uninstall
```

核心卸载停止/删除管理文件和 unit、恢复旧 ShellPackage，保留个人状态，注销登录或重启恢复会话。
独立应用另管。NixOS 用[声明式 flake](nixos-quickstart.zh-CN.md)，不在 store 切源码。
