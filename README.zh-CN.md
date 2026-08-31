# KOS Desktop Shell

[English](README.md)

KOS 是运行在 KDE Plasma 6 Wayland 上的 Quickshell 桌面 Shell，提供顶部栏、
悬浮 Dock、桌面组件和文件、启动器、搜索、通知、工作区概览及独立设置应用。
它不会替换 Plasma、KWin、NetworkManager、PipeWire 或 systemd，只接管你选择
隐藏的界面。

## 五分钟预览

预览不会安装任何文件，也不需要 root：

```sh
git clone <repository-url> NextKde
cd NextKde
./tools/kosctl doctor       # 检查 Quickshell、CMake、Go 和图形会话
qs -p "$PWD/shell"          # 等价于 quickshell --path "$PWD/shell"
```

按 `Ctrl+C` 退出。未安装两个常驻服务前，指标、窗口和桌面文件可能为空；
Plasma 原有面板和通知仍会运行，出现重叠是正常的。

## 环境要求

- KDE Plasma 6 Wayland 会话（KWin 负责窗口列表）。
- Quickshell 0.3.x（`qs` 或 `quickshell`），安装方法见
  [Quickshell 官方文档](https://quickshell.org/docs/)。
- CMake 3.21+、Ninja、C++20 编译器、Qt 6 开发包和 Go。
- 正常 Plasma 会话提供 NetworkManager（`nmcli`）、PipeWire/WirePlumber
  （`wpctl`）、BlueZ（`bluetoothctl`）、`loginctl` 和 `systemctl --user`。
- 可选剪贴板历史依赖：`wl-clipboard`（`wl-copy`/`wl-paste`）和 `cliphist`。
  即使未安装它们，桌面文件复制/粘贴仍可使用。
- 只有编译可选 KWin 插件时才需要 KWin/KF6 开发头文件。

`kosctl build` 默认通过 `https://goproxy.cn,direct` 下载 Go 模块。如果需要
使用其他镜像或离线模块缓存，可以在构建前设置 `GOPROXY`，例如
`GOPROXY=off ./tools/kosctl build`。

Arch 常用基础包为 `quickshell cmake ninja gcc qt6-base go`；Debian/Ubuntu
安装发行版对应的 `quickshell cmake ninja-build g++ qt6-base-dev golang`。

## 完整安装

在仓库根目录执行唯一入口：

```sh
./tools/kosctl doctor
KOS_BUILD_KWIN_PLUGINS=OFF ./tools/kosctl install
```

该命令会构建并安装：

- `kos-platform` → `~/.local/libexec/`（唯一的 C++/Qt 平台常驻进程）；
- `kos-data-service` → `~/.local/libexec/`（Go 指标/历史数据常驻进程）；
- `kos-settings` → `~/.local/bin/`；
- Quickshell 配置 → `~/.config/quickshell/kos`；
- `kos-platform.service` 与 `kos-data.service` → systemd 用户单元。

安装器会立即启用两个用户服务，不使用 `sudo`。如果系统有匹配的 KWin 开发
头文件，可用 `KOS_BUILD_KWIN_PLUGINS=ON` 构建插件；系统范围安装插件可能需要
管理员权限。

启动已安装的 Shell：

```sh
qs -c kos
```

开发时使用 `./tools/kosctl run`，它通过 `qs -p shell` 加载当前检出目录。

### 首次 Plasma 设置

KOS 提供自己的通知服务。日常使用前请从 Plasma 面板/系统托盘移除通知组件，
否则 Plasma 会占用通知 D-Bus 名称。恢复 Plasma 时再加回该组件。KOS 不会自动
修改你的面板布局。

### 全局快捷键

默认快捷键由原生平台程序安装，不再依赖 Python：

```sh
./tools/kosctl shortcuts install
```

定义位于 `shared/contracts/shortcuts.v1.json`，之后可在「系统设置 → 快捷键」
中修改。只删除 KOS 的绑定：

```sh
./tools/kosctl shortcuts uninstall
```

## 架构概览

```text
qs -c kos ──► shell/shell.qml ──► shell/desktop/       Quickshell 进程
                    │ JSONL Unix socket
                    ├──────────────► kos-platform       C++/Qt 适配器
                    └──────────────► kos-data.sock      Go 持久数据服务

apps/settings/       独立 Qt Quick 进程，只通过 Shell IPC 通信
integrations/kwin/   两个 KWin 插件 .so（KWin 加载模型要求）
vendor/              第三方 kwin-effects-glass 源码
shared/contracts/    带版本的 IPC 与快捷键契约
```

平台 socket 为 `$XDG_RUNTIME_DIR/kos-platform.sock`，数据 socket 为
`$XDG_RUNTIME_DIR/kos-data.sock`，权限均为 `0600`。所有消息都是带版本和
`requestId` 的 JSON Lines，并使用统一结果/错误模型，详见
[PlatformArchitecture.md](docs/PlatformArchitecture.md) 与
[platform.v1.md](shared/contracts/platform.v1.md)。

`kos-platform` 负责 KWin 窗口命令、Wayland 文件剪贴板、文件操作/Open-With、
网络/音频/蓝牙/亮度/会话/主题适配、截图选择和快捷键安装。
`kos-data-service` 负责采样、历史、活动归属和桌面目录快照。两个 KWin 特效仍
是独立共享库，因为 KWin 要求每个插件有独立 ID。

## 常用命令

```sh
./tools/kosctl doctor
./tools/kosctl build
./tools/kosctl run
./tools/kosctl install
./tools/kosctl uninstall
systemctl --user status kos-platform.service kos-data.service
journalctl --user -u kos-platform.service -u kos-data.service -f
```

`uninstall` 会停止服务并移除安装的二进制、单元和 Shell 配置，但保留
`$XDG_STATE_HOME/quickshell/...` 中的用户状态，方便恢复。

## 开发与验证

```sh
cmake --preset debug
cmake --build --preset debug
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
node shell/desktop/modules/dock/test_adaptive.mjs
node shell/desktop/modules/dock/test_autohide.mjs
git diff --check
```

请先用 `./tools/kosctl run` 启动独立 Quickshell 实例并检查日志，再替换日常
Shell。安全运行流程见 [.agents/skills/verify/SKILL.md](.agents/skills/verify/SKILL.md)。
如果 Go 依赖下载失败，`kosctl build` 会显示代理/网络错误，可以设置 `GOPROXY`
切换到其他镜像后重试。

## 仓库结构

```text
shell/                     唯一 Quickshell 配置根目录
apps/settings/             独立设置应用
shared/qml/                可移植控件
shared/contracts/          JSONL 与快捷键契约
services/data-service/     Go 数据服务
platform/                  一个 kos-platform CMake 工程和可执行文件
integrations/kwin/         两个本项目 KWin 插件
vendor/kwin-effects-glass/ 第三方特效
packaging/                 systemd 与 desktop 文件
tools/kosctl               构建/安装/运行/检查/卸载入口
docs/                      架构和运维文档
```

架构边界见 [ProjectArchitecture.md](docs/ProjectArchitecture.md)，数据层见
[ShellDataService.md](docs/ShellDataService.md)，平台操作、权限和错误模型见
[PlatformArchitecture.md](docs/PlatformArchitecture.md)。

## 许可证

KOS 使用 GPL-3.0-or-later，见 [LICENSE](LICENSE)。vendored 玻璃特效保留其
兼容许可证：`vendor/kwin-effects-glass/LICENSE`。
