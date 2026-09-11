# KOS Desktop Shell

[English](README.en.md)

KOS 是 KDE Plasma 6 Wayland 上的 Quickshell 桌面 Shell。它提供顶部栏、Dock、
启动器、搜索、通知和设置界面；KDE、KWin、NetworkManager 等系统组件仍然保留。

## 从零开始

### 1. 准备环境

需要 KDE Plasma 6 **Wayland** 会话（KWin 6.4 或更高版本）、Quickshell 0.3.x、
Qt 6.6 或更高版本，以及完整的 KF6 和 KWin 开发依赖。默认安装会同时编译平台
服务、设置应用、KWin 特效和窗口装饰。

Arch 常用基础包：

```sh
sudo pacman -S --needed \
  git quickshell cmake ninja gcc go qt6-base qt6-declarative \
  kwindowsystem kiconthemes kglobalaccel \
  extra-cmake-modules kwin kconfig ki18n kguiaddons kcmutils \
  kcoreaddons kdecoration gettext libxcb vulkan-headers
```

建议同时安装这些运行时集成包：

```sh
sudo pacman -S --needed \
  networkmanager wireplumber bluez-utils brightnessctl \
  wl-clipboard cliphist glib2 xdg-utils spectacle
```

前一组是默认构建的必需依赖；后一组按功能可选，分别提供网络、音频、蓝牙、
亮度、剪贴板历史、回收站/文件操作和截图支持。如只构建平台服务和设置应用、
禁用 KWin 插件，可设置 `KOS_BUILD_KWIN_PLUGINS=OFF`，此时不需要 KWin 插件
开发依赖。

其中 `extra-cmake-modules` 是 KWin 插件 CMake 配置的直接依赖；`vulkan-headers`
是 KWin 导出的 `Vulkan::Vulkan` 编译接口所需依赖。Arch 的 `kwin` 包不会自动安装
`vulkan-headers`，因此这里必须显式列出。KWin 同时需要 Wayland、libdrm 和
libepoxy 的开发文件，但这些已是 Arch `kwin` 包的硬依赖，无需重复安装。

### Ubuntu 26.04 (resolute)

`kosctl` 的自动依赖安装目前仅在 Arch 与 NixOS 上生效；Ubuntu 用户请手动安装
对应软件包（以下清单已在 26.04 上完成全量构建验证）。

Quickshell 0.3.x 尚未进入 Ubuntu 官方仓库，可使用
[Quickshell 官方文档](https://quickshell.org/docs/)推荐的 PPA（已提供
resolute 软件源）：

```sh
sudo add-apt-repository ppa:avengemedia/danklinux
sudo apt update
sudo apt install quickshell
```

基础与 KWin 插件构建依赖：

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

运行时集成（可选，与上文 Arch 清单对应）：

```sh
sudo apt install \
  network-manager wireplumber bluez brightnessctl \
  wl-clipboard cliphist xdg-utils kde-spectacle \
  libglib2.0-0 qml6-module-qtquick-dialogs libqt6sql6-sqlite
```

与 Arch 包名的主要差异：`kdecoration` 对应 `libkdecorations3-dev`，
`vulkan-headers` 对应 `libvulkan-dev`，`spectacle` 对应 `kde-spectacle`。
另外需要注意：`libplasma-dev` 提供 glass 特效引用的 `Plasma/plasma_version.h`；
`libkf6kio-dev`、`libkf6calendarcore-dev` 是平台服务与设置应用 CMake 的直接
依赖（Arch 上由依赖链自动带入）；KWin 导出所需的 xcb 扩展开发头文件
（composite、randr、res、shm、sync）不会被 `kwin-dev` 自动带入，需显式安装；
`qml6-module-qtquick-dialogs` 与 `libqt6sql6-sqlite` 是 QuickDialogs2 和
数据服务的运行时依赖。

Calendar、Todo、Weather 和 Music 是独立的可选应用，不由 `kosctl install` 构建；
它们需要额外的 Qt/KF6、GStreamer、TagLib 或 Go 依赖。安装前请阅读
[apps/README.zh-CN.md](apps/README.zh-CN.md) 及各应用目录的说明，再运行
`./tools/install-apps.sh`。

其他发行版请安装对应软件包。Quickshell 的安装方式见
[官方文档](https://quickshell.org/docs/)。

### 2. 下载代码

```sh
git clone https://github.com/SuceV587/NextKde.git
cd NextKde
```

### 3. 检查并安装

```sh
./tools/kosctl doctor
./tools/kosctl install
./tools/kosctl start
```

`doctor` 会检查命令、Arch 软件包及可选运行时集成。`install` 在 Arch 上会提示并
安装缺少的必需构建包，然后编译安装 KOS；首次安装 KWin 插件时
可能要求输入 sudo 密码。`start` 立即重启 KOS 服务，桌面界面会短暂刷新。

安装完成后，KOS 会在之后登录时自动启动。

### 4. 首次设置

KOS 自己处理通知。请从 Plasma 面板或系统托盘移除“通知”组件，否则 Plasma 会占用
通知服务。KOS 不会自动更改你现有的面板布局。

## 界面预览

完整桌面：DeskCenter、悬浮 Dock 与系统状态区。

![KOS 完整桌面](docs/images/full-desktop.png)

全屏启动台：应用搜索与网格启动。

![KOS 全屏启动台](docs/images/fullscreen-launcher.png)

控制中心：网络、蓝牙、亮度、音量和通知。

![KOS 控制中心](docs/images/control-center.png)

设置中心：调整显示、主题、顶栏、Dock、启动台与快捷键，并查看接入状态。

![KOS 设置中心](docs/images/settings-center.png)

## 日常使用

### 更新到新版本

```sh
git pull
./tools/kosctl install
./tools/kosctl start
```

### 查看服务状态

功能无响应、亮度/网络等状态不更新时，先运行：

```sh
systemctl --user status kos-platform.service kos-data.service kos-shell.service
```

持续查看日志：

```sh
journalctl --user -u kos-platform.service -u kos-data.service -f
```

### 卸载

```sh
./tools/kosctl uninstall
```

这会停止并移除 KOS 文件与服务；你的 Dock 固定项、外观等个人状态会保留。

#### 对于NixOS，我们更推荐使用基于 Flake 的安装方法

以下是针对 NixOS 的安装步骤：

1. 在当前系统配置的 Flake.nix 下添加 kos 的输入源

```Nix
nextkde = {
         # github 源：KOS Desktop Shell
         url = "git+https://github.com/SuceV587/NextKde.git"
         inputs.nixpkgs.follows = "nixpkgs";
};
```

2. 更新 kos 的 Flake 输入

```Nix
nix flake update nextkde
```

3. 重新构建

```Nix
sudo nixos-rebuild switch --flake .#hosts
```

4. 使用方法

```Nix
    services.kos = {
        enable = true;
        # 如需禁用直接改为 `enable = false;` 即可
        weather.enable = true;
        # kos 内置的天气服务
    };

```

## 主要功能

| 模块               | 能做什么                                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| 桌面组件           | 显示时钟、天气预报、日历、CPU/内存/温度、开机时长、应用使用情况和媒体播放信息。                                           |
| 悬浮 Dock 与顶部栏 | 显示已固定和正在运行的应用，支持窗口预览、启动动画、自动隐藏、系统托盘、网络、电池与温度状态；可将顶部栏状态整合到 Dock。 |
| 启动器与搜索       | 提供全屏应用网格、应用搜索、窗口搜索和常用应用入口。                                                                      |
| 控制中心           | 管理 Wi‑Fi、蓝牙、亮度、音量、媒体播放、深色模式、勿扰、截图、锁屏、睡眠、注销、重启和关机。                              |
| 桌面文件           | 在桌面展示文件和文件夹，并提供打开、重命名、删除、复制、剪切和“打开方式”等常用操作。                                      |
| 外观与动效         | 提供液态玻璃、背景模糊、主题色、Dock 位置、图标风格和显示方式；Dock 与窗口动画由 KWin 插件提供。                          |
| 设置与快捷键       | 独立设置中心可调整外观、Dock、Bar 和启动台；可安装并在 KDE 系统设置中修改全局快捷键。                                     |

### 可选独立应用

仓库还提供日历、待办、天气和本地音乐四个独立 Qt Quick 应用。它们默认不随 Shell
构建；使用 `apps-dev` / `apps-release` 预设可统一构建，也可使用
`calendar-dev`、`todo-dev`、`weather-dev` 或 `music-dev` 单独构建：

```sh
cmake --preset apps-dev
cmake --build --preset apps-dev
ctest --preset apps-dev
```

用户级安装与服务注册可运行 `./tools/install-apps.sh`。依赖和模块说明见
[apps/README.md](apps/README.md)。天气应用与 Shell 共用 `kos-data-service` 的缓存和
Open-Meteo 数据；日历与待办共用按需启动的 PIM 服务。

KOS 不替代 KDE Plasma：它复用 KWin、NetworkManager、PipeWire、BlueZ 和 systemd，
只把这些系统能力整合到自己的界面中。

## 架构概览

```text
Quickshell Shell ──► kos-platform ──► KWin / 网络 / 音频 / 蓝牙
                 └─► kos-data-service ──► 系统指标与桌面数据
```

- `shell/`：界面代码。
- `platform/`：KWin、网络、音频、亮度等系统接口。
- `services/data-service/`：系统指标、历史、桌面数据与共享天气缓存。
- `integrations/kwin/`：KWin 插件；`vendor/`：第三方 Glass 特效源码。

更详细的说明见 [docs/ProjectArchitecture.md](docs/ProjectArchitecture.md)。

## 下一步计划

- 更完善的多显示器布局与每屏独立设置。
- 让 DeskCenter 完整接入主题系统。
- 扩展设置项、快捷键和独立应用。
- 改善键盘操作、无障碍和高对比度支持。

## 开发与调试

只想预览界面、不安装到系统（复用已安装的服务）：

```sh
qs -p "$PWD/shell"
```

调试源码 QML（保持运行，`Ctrl+C` 结束）：

```sh
./tools/kosctl dev
```

它只启动源码 QML，直接复用 systemd 的 `kos-platform.service` 和 `kos-data.service`；不会编译、部署、重启服务，也不会创建第二套 socket。

从源码 Shell 的齿轮打开设置中心会自动连接该源码会话。也可以在第二个终端手动启动：

```sh
KOS_SHELL_DIR="$PWD/shell" kos-settings
```

不要把 `-c` 与 `-p` 一起传给 `qs`；两者互斥。应用菜单单独打开的设置中心仍会连接安装版
Shell；调试时请从源码 Shell 的齿轮打开，或使用上面的命令。

修改 QML 后应用到已安装版本：

```sh
./tools/kosctl sync
./tools/kosctl start
```

修改 C++、Go 或 KWin 插件后：

```sh
./tools/kosctl install
./tools/kosctl start
```

`start` 会立即应用 Shell、平台服务和数据服务更新；KWin 特效二进制会在下次注销并
重新登录或重启后载入，避免在运行中的合成器里热替换插件。

常用命令：

```sh
./tools/kosctl doctor       # 检查依赖
./tools/kosctl run          # 从当前源码预览
./tools/kosctl dev          # 全栈源码调试
./tools/kosctl shortcuts install
./tools/kosctl glass-settings
```

测试与架构资料在 [docs/](docs/)；贡献代码前建议至少运行：

```sh
git diff --check
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
```

## 许可证

本项目采用其仓库声明的许可证。第三方 Glass 特效的许可证见
[vendor/kwin-effects-glass/LICENSE](vendor/kwin-effects-glass/LICENSE)。
