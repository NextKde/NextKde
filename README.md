# KOS Desktop Shell

[English](README.en.md)

KOS 是运行在 KDE Plasma 6 Wayland 上的 Quickshell 桌面 Shell，提供顶部栏、
悬浮 Dock、桌面组件和文件、启动器、搜索、通知、工作区概览及独立设置应用。
它不会替换 Plasma、KWin、NetworkManager、PipeWire 或 systemd，只接管你选择
隐藏的界面。

## 🚀 新手先看这里

| 目标 | 命令 | 说明 |
| --- | --- | --- |
| ✏️ 改 QML 后应用 | `./tools/kosctl sync` | 只把 `shell/` QML 拷到已安装配置（秒级）。安装态的 shell 不热重载（已关闭文件监听），随后执行 `./tools/kosctl start` 生效。不编译。适用于纯 QML 改动。 |
| ✅ 首次安装／更新 | `./tools/kosctl install` | 只安装文件并注册开机自启，**不打扰当前会话**：不会重启服务、不会热加载 KWin 特效。新版本在下次登录或执行 `./tools/kosctl start` 后生效。安装 KWin 插件时可能要求 `sudo`。 |
| ⚡ 立即生效 | `./tools/kosctl start` | 重启三项用户服务以应用最新安装版本（界面会短暂切换）。KWin 特效只写入 kwinrc，在下次 KWin／会话启动时加载。会收编手动启动的 `qs -c kos` 实例，改由 systemd 管理。C++/Go/KWin 代码改动后用它应用。 |
| 🔬 全栈源码调试 | `./tools/kosctl dev` | 从源码和构建产物直接运行 platform、data-service、shell 三件套，socket 与已安装服务隔离、互不干扰。注意：KWin bridge 是全局注册，调试期间已安装 shell 的窗口事件会暂停。 |
| 🧪 修改后只预览工作区 UI | `./tools/kosctl run` | 通过当前检出目录启动独立预览，不会启动服务，也不会替换已安装的 `kos-shell`。依赖 IPC 的功能仍使用已运行服务所提供的数据。 |
| 🏠 日常运行已安装 Shell | `qs -c kos` | 只适用于已完成 `kosctl install` 的环境；也可由 `kos-shell.service` 随用户会话启动。 |

所有启动方式共享同一个状态目录（`~/.local/state/quickshell/kos`，由
`shell/shell.qml` 的 `StateDir` pragma 固定）：Dock 固定项、启动器自定义图标、
外观、天气缓存等用户数据在安装版与源码预览/调试之间保持一致。改动配置格式时
需要保持向后兼容或写迁移逻辑，避免破坏已安装实例的数据。

如果日志出现 platform/data socket 错误，先检查服务状态：

```sh
systemctl --user status kos-platform.service kos-data.service kos-shell.service
```

## 👀 仅预览界面

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
- 默认安装会编译 KOS 的两个 KWin 插件以及内置的 `kwin-effects-glass`
  源码，因此需要与当前 KWin 匹配的 KWin/KF6 开发头文件。Arch/CachyOS
  缺少的 KF6 构建依赖会由安装器通过 `sudo pacman` 补齐。

`kosctl build` 默认通过 `https://goproxy.cn,direct` 下载 Go 模块。如果需要
使用其他镜像或离线模块缓存，可以在构建前设置 `GOPROXY`，例如
`GOPROXY=off ./tools/kosctl build`。

Arch 常用基础包为 `quickshell cmake ninja gcc qt6-base go`；Debian/Ubuntu
安装发行版对应的 `quickshell cmake ninja-build g++ qt6-base-dev golang`。

## 完整安装

`apps/settings` 当前是 Shell 的核心配套应用，会随 `kosctl` 一同安装，用于提供
独立设置界面。未来 `apps/` 下的其他应用仍为可选能力：默认 Shell 路径不得构建、
安装或启动它们；每个应用必须提供独立、可说明的入口。

在仓库根目录执行唯一入口：

```sh
./tools/kosctl doctor
./tools/kosctl install
```

该命令会构建并安装：

- `kos-platform` → `~/.local/libexec/`（唯一的 C++/Qt 平台常驻进程）；
- `kos-data-service` → `~/.local/libexec/`（Go 指标/历史数据常驻进程）；
- `kos-settings` → `~/.local/bin/`；
- Quickshell 配置 → `~/.config/quickshell/kos`；
- `kos-platform.service`、`kos-data.service` 与 `kos-shell.service` → systemd
  用户单元；Shell 强依赖 platform 服务，并在它之后启动。
- KOS Dock 动画、Quickshell 右键输入插件和 Glass 特效 → 系统 KWin 插件目录。

安装器只安装文件并 enable 三个用户服务（注册自启），不重启任何正在运行的
东西；KWin 特效只写入 kwinrc 配置，不热加载。新版本在下次登录时生效，或
立即执行 `./tools/kosctl start`（重启服务并热加载特效，界面会短暂切换）。
用户文件仍安装到 `~/.local`；安装 KWin 插件及 Arch/CachyOS 缺失的构建依赖时
会调用 `sudo`，密码由当前终端正常接管。Glass 与系统 Blur 冲突，因此安装时会
保存 Blur 状态并停用它；`./tools/kosctl uninstall` 会卸载三项特效并恢复原状态。

只需构建/安装用户态组件时可显式关闭 KWin 插件：

```sh
KOS_BUILD_KWIN_PLUGINS=OFF ./tools/kosctl install
```

查看或配置 Glass 时，可直接打开 KDE 的桌面特效页面：

```sh
./tools/kosctl glass-settings
```

启动已安装的 Shell：

```sh
qs -c kos
```

修改 QML 后使用 `./tools/kosctl run`，它通过 `qs -p shell` 加载当前检出目录。
它是独立预览，不会启动或重启任何服务；需要将本次修改部署为日常 Shell 时，先执行
`./tools/kosctl install`（不打扰当前会话），再执行 `./tools/kosctl start` 立即
生效，或等待下次登录自动生效。

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

## 后续开发计划

按大致优先级排列：

- **多显示器每屏布局**——DeskCenter 组件、桌面图标布局、Dock 位置/显示
  规则与壁纸取色按显示器持久化。
- **DeskCenter 主题接入**——让桌面卡片消费外观 Token 层（最后一个未
  接入的 surface）。
- **设置覆盖面**——`kos-settings` 增加快捷键与 DeskCenter 设置页。
- **独立应用**——填充 `apps/` 下的 `calendar`、`todo`、`weather` 占位，并保持
  每个应用可单独构建；只使用 Shell 的用户无需安装它们的依赖。
- **可访问性与键盘导航**——焦点顺序、减少动画、高对比度与全键盘操作。
- **天气图标集**——用完整 SVG 图标集替换目前 Unicode 字符、Canvas 绘制
  与部分 SVG 混用的方案。

已搁置：跨文件管理器的拖拽移动（受 Wayland DnD action 协商限制），目前
仅由剪贴板桥接覆盖复制/剪切。

## 常用命令

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

`install` 只安装文件并注册自启，不重启运行中的服务（不会黑屏、不会关闭已打开
的应用）；`start` 才会重启服务并热加载 KWin 特效。`uninstall` 会停止服务并移除
安装的二进制、单元和 Shell 配置，但保留 `$XDG_STATE_HOME/quickshell/...` 中的
用户状态，方便恢复。

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
