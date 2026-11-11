# 安装与日常使用

[English](GettingStarted.md)

使用 KDE Plasma 6 **Wayland**、KWin 6.6+、Quickshell 0.3.x、Qt 6.6+，开发包需匹配 KF6/KWin，原生插件匹配合成器 ABI。
[发布说明](releases/v0.1.1.zh-CN.md)列出实际实测环境；以下包配方不代表所有系统端到端通过。
贡献者验证只在 VM/CI。以已登录桌面用户操作，不 `sudo ./tools/kosctl`；命令位于仓库根目录。

## 1. 安装依赖

选源码需要 Git、Python 3.9+，核心构建需要 CMake、Ninja、C++20、Go、Qt/KF6、Wayland、KWin 开发依赖。
`doctor` 报告缺项，Arch/Debian 系与 Fedora 上 `install` 可装构建包。
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

`kosctl doctor` 检查依赖，`install` 通过 dnf 安装缺失的构建包；下列清单适用于手工安装核心及 KWin 依赖。默认空间 AUTO 模式还会安装 `opencv-devel`，可用 `KOS_BUILD_SPATIAL=OFF` 跳过。此社区配方不代表官方 Fedora 运行验收：

```sh
sudo dnf install \
  git python3 cmake ninja-build gcc-c++ golang curl patchelf pkgconf-pkg-config gettext \
  quickshell extra-cmake-modules \
  wayland-devel wayland-protocols-devel libxkbcommon-devel \
  qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qttools-devel qt6-qttranslations qt6-qtquick3d-devel \
  qt6-qtsvg-devel qt6-qtwayland-devel qt6-qtimageformats qt6-qt5compat-devel \
  qt6-qtbase-private-devel \
  kf6-kwindowsystem-devel kf6-kiconthemes-devel kf6-kglobalaccel-devel \
  kf6-kio-devel kf6-kcalendarcore-devel kf6-kconfig-devel kf6-ki18n-devel \
  kf6-kguiaddons-devel kf6-kcmutils-devel kf6-kcoreaddons-devel \
  libplasma-devel kdecoration-devel \
  kwin-devel libdrm-devel mesa-libgbm-devel libepoxy-devel \
  vulkan-headers vulkan-loader-devel zlib-devel libxcb-devel
```

Qt base/QPA 私有头在 `qt6-qtbase-private-devel` 中，QuickPrivate 在 `qt6-qtdeclarative-devel` 中；Fedora 的 `libxcb-devel` 不同于 Debian 拆分包。剪贴板历史另需 `wl-clipboard` 与 `cliphist`（`sudo dnf install wl-clipboard cliphist`），缺失时 `doctor` 会警告。

Fedora 包可用不代表 Quickshell 已达到 0.3.x。请检查 `kosctl doctor` 报告的版本；仓库版本较旧时，按上文从合适来源安装兼容的 0.3.x。此依赖助手不会升级源码安装的 Quickshell，也不代表桌面运行兼容性验收。

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

空间默认 `AUTO`：直接 CMake 在已有 OpenCV/ONNX 时构建；Arch/Debian/Fedora 的 kosctl 会装 OpenCV 并尽可能准备固定 ONNX SDK。
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

用 `kosctl install` 安装的源码 checkout 也可以在 Settings → 关于 中检查更新，并提供两个通道：
**Stable** 跟随 GitHub 最新正式 Release tag，**Canary** 跟随 `origin/main`。选择按安装保存
（`~/.config/kos/update-channel`）。它会拒绝脏工作区或未完成的 Git 操作，增量编译，并在修改
KWin 插件前请求管理员授权。构建和用户文件始终属于当前用户，只有原有的系统插件拷贝使用 sudo。
升级到带此功能的版本后，需要先在 checkout 里运行一次 `./tools/kosctl install`，让版本记录写入
源码路径。切换通道会 checkout 对应版本（detached），本地提交仍保留在原分支。Stable 需要
GitHub `origin` 上存在正式 Release。KWin 插件更新仍需注销登录或重启合成器。

## 可选独立应用

日历、计算器、天气合用独立 `NextKde/kos-apps` 仓库／版本／Release，各自仍是
`org.nextks.<app>` 独立包，目录为 `apps/org.nextks.<app>`；ListenFree 保持独立。
源码已公开；实际安装包可用性请查看对应正式 Release。旧 Flatpak ID 不自动改名、卸载或迁移数据。

```sh
./tools/kosctl install apps
./tools/kosctl install apps --app calendar
./tools/kosctl install apps --with-listenfree
./tools/kosctl install apps check-update --app weather
```

分发入口默认经 `kos-apps` 使用与 Settings 相同的用户级 Flatpak 后端。
默认选择日历（含待办）、计算器和天气；ListenFree 必须显式选择。修改操作要求终端确认或 `--yes`。
应用包通过 GitHub Releases 发布，由签名目录提供列表。SHA-256 必须校验；目录配置 publisher 时才要求开发者签名。
明确安装／更新时可为缺失依赖准备已批准的 Flathub runtime 源，应用本身仍来自 GitHub，不必上架 Flathub。
安装需要真实兼容的正式 Release，不会静默回退源码构建。普通卸载保留数据。libflatpak 可能建立无在线 URL
的本地 bundle origin，取消安装后已准备的运行库源也可能保留。

Settings → 应用与服务可以管理第三方目录来源、手动检查、自动检查与更新提示。后台只检查元数据，不自动安装。
不承诺 Discover 发现这些 GitHub 包更新。详见[目录与更新机制](app-store/SignedCatalog.zh-CN.md)及
[上架、Qt runtime 打包指南](https://github.com/NextKde/appCatalog/blob/main/README.zh-CN.md)。

显式 `--backend=source` 保留历史兼容／开发用源码 Release 本地构建；这些不是 Discover 管理的软件包。
开发依赖及自定义 SDK/视频构建见各独立仓库，包含 [ListenFree](https://github.com/NextKde/ListenFree)。
根应用 preset 和 ON 构建开关不再支持；两种后端均不自动迁移旧播放器或个人数据。
`update`、`status`、`check-update`、`uninstall` 使用同一应用分发入口。
计算器汇率为注明日期的离线参考，不是实时。详见[应用指南](../apps/README.zh-CN.md)。


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

Settings → 关于 会原地更新源码 checkout：进度和完整日志写在
`${XDG_STATE_HOME:-$HOME/.local/state}/kos/update/`，关闭设置窗口后仍会继续；在点“重启 KOS”
之前不会动正在运行的 Shell。如果授权或构建失败，源码可能已经更新；请查看日志并重试，确认前不要注销。

```sh
./tools/kosctl uninstall
```

核心卸载停止/删除管理文件和 unit、恢复旧 ShellPackage，保留个人状态，注销登录或重启恢复会话。
独立应用另管。NixOS 用[声明式 flake](nixos-quickstart.zh-CN.md)，不在 store 切源码。
