# KOS Desktop Shell

[English](README.en.md)

KOS 是 KDE Plasma 6 Wayland 上的 Quickshell 桌面 Shell。它提供顶部栏、Dock、
启动器、搜索、通知和设置界面；KDE、KWin、NetworkManager 等系统组件仍然保留。

## 从零开始

### 1. 准备环境

需要 KDE Plasma 6 **Wayland** 会话，以及 Git、CMake、Ninja、C++ 编译器、Qt 6、
Go 和 Quickshell 0.3.x。

Arch 常用基础包：

```sh
sudo pacman -S git quickshell cmake ninja gcc qt6-base go
```

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

`doctor` 会指出缺少的依赖。`install` 会编译并安装 KOS；首次安装 KWin 插件时
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

设置中心：调整 Dock、外观与显示方式。

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

## 主要功能

| 模块 | 能做什么 |
| --- | --- |
| 桌面组件 | 显示时钟、天气预报、日历、CPU/内存/温度、开机时长、应用使用情况和媒体播放信息。 |
| 悬浮 Dock 与顶部栏 | 显示已固定和正在运行的应用，支持窗口预览、启动动画、自动隐藏、系统托盘、网络、电池与温度状态；可将顶部栏状态整合到 Dock。 |
| 启动器与搜索 | 提供全屏应用网格、应用搜索、窗口搜索和常用应用入口。 |
| 控制中心 | 管理 Wi‑Fi、蓝牙、亮度、音量、媒体播放、深色模式、勿扰、截图、锁屏、睡眠、注销、重启和关机。 |
| 桌面文件 | 在桌面展示文件和文件夹，并提供打开、重命名、删除、复制、剪切和“打开方式”等常用操作。 |
| 外观与动效 | 提供液态玻璃、背景模糊、主题色、Dock 位置、图标风格和显示方式；Dock 与窗口动画由 KWin 插件提供。 |
| 设置与快捷键 | 独立设置中心可调整外观、Dock、Bar 和启动台；可安装并在 KDE 系统设置中修改全局快捷键。 |

KOS 不替代 KDE Plasma：它复用 KWin、NetworkManager、PipeWire、BlueZ 和 systemd，
只把这些系统能力整合到自己的界面中。

## 架构概览

```text
Quickshell Shell ──► kos-platform ──► KWin / 网络 / 音频 / 蓝牙
                 └─► kos-data-service ──► 系统指标与桌面数据
```

- `shell/`：界面代码。
- `platform/`：KWin、网络、音频、亮度等系统接口。
- `services/data-service/`：系统指标、历史和桌面数据。
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

需要连同 Platform 和数据服务一起调试时，在第一个终端运行（保持运行，`Ctrl+C`
结束）：

```sh
QSG_RENDER_LOOP=basic ./tools/kosctl dev
```

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
