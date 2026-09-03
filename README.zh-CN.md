# KOS Desktop Shell

**[English](README.md) | [中文](README.zh-CN.md)**

一个 iPadOS 风格的桌面环境，运行于 **KDE Plasma 6 (Wayland)**，基于
[Quickshell](https://quickshell.org) 构建。KOS 不是发行版，也不是某个桌面
环境的 fork——它是一套完整的 Quickshell 配置，加上少量原生帮助程序和
KWin 特效，共同替换 Plasma 的 Shell 体验：顶部状态栏、悬浮 Dock、桌面
组件、应用启动器、通知系统、工作区概览，以及独立的设置应用。

> 状态：个人日用项目，活跃开发中。接口与配置 schema 均有版本号和迁移
> 逻辑，但功能会持续快速演进。

---

## 特性

### Shell 界面

- **顶部状态栏**——系统托盘、带实时速率的网络状态、蓝牙、音量、电池、
  CPU 温度、时钟与控制中心入口。可独立存在，也可融入 Dock。
- **Dock**——iPadOS 风格的固定应用 + 运行窗口、悬停放大、拖拽排序、
  右键菜单、实时窗口预览、带封面取色的 MPRIS 音乐播放器、天气、带角标的
  回收站。支持三个位置（底部/左/右）、三种显示模式（`始终显示` /
  `智能隐藏`（窗口碰撞驱动）/ `持续隐藏`，配 iOS 风格小白条唤醒），以及
  图标外观模式（`彩色` / `黑白` / `染色`）。
- **Bar ⇄ Dock 融合**——可选择把状态栏并入底部 Dock：时钟加入
  音乐/天气/温度信息轮播，系统状态区成为右侧附件；侧边 Dock 则使用反向
  旋转、文字保持正立的单行轮播。
- **DeskCenter 桌面层**——背景层桌面组件（时钟、天气、日历、带历史
  环图的系统监控、活动记录、正在播放）与真实的桌面文件表面：排序、
  框选、重命名、回收站、长按投放文件夹、多选拖动、新建文件/文件夹、
  外部 URL 拖入，以及与 Dolphin 互通的剪切/复制语义。
- **应用启动器**——iPadOS 风格全屏网格，拖入创建文件夹，支持自定义
  名称/图标与隐藏应用。
- **快速搜索**——增量应用/文件搜索、剪贴板历史（cliphist，含图片），
  以及带 KWin 实时缩略图的 MRU 窗口切换。
- **通知**——按应用分组叠加/展开、操作按钮、内联回复、紧急级别样式、
  勿扰模式，以及控制中心内按应用分组的历史中心。
- **工作区概览**——Stage Manager 风格的全屏遮罩：虚拟桌面条 + 实时
  窗口缩略图（`Meta+Tab`）。
- **控制中心**——Wi-Fi 连接/断开/忘记（含 802.1X：PEAP / TTLS）、蓝牙、
  音量、经 logind 的真实背光亮度、勿扰、截图、注销与通知历史。

### 外观系统

- 三种 Shell 形态——**Windows 12**、**macOS**、**Material**——由带版本
  的语义 Token 层（`AppearanceTokens`）驱动，热切换不重建任何界面。
- 全局**模糊强度**与**液态玻璃强度**滑块，同时作用于 QML 玻璃材质与
  KWin 玻璃特效。
- 独立的**设置应用**（`kos-settings`）运行于自有进程，只通过带版本的
  IPC 契约（`appearance-settings`）与 Shell 通信。

### 图形与特效

- **KWin 玻璃特效**（`integrations/kwin-effects-glass`）：Plasma 6 模糊
  的 fork，含 Dual Kawase 模糊、Snell 折射、按表面的高光方向，以及双向
  染色（深色背景提亮、亮色背景压暗）。
- **Dock 窗口动画特效**（`integrations/kwin-dock-window-animation`）：
  iPadOS 风格的 `scale` / `genie` 开关窗动画；Shell 发布精确的屏幕图标
  矩形，使窗口准确落回图标。
- **右键菜单输入特效**（`integrations/kwin-context-menu-input`）：在合成
  器层面实现菜单的外部点击关闭。
- 客户端 SDF 圆角、折射、噪声与辉光 shader，使用 `qsb` 编译。

### 平台服务

- **`shell-data-service`（Go）**——持久与历史数据的唯一所有者：
  CPU/内存/磁盘/频率/温度采样与历史、开机与按应用的活动账本、桌面目录
  监听与原子快照，以及由其监督的 Qt 剪贴板帮助程序（同时发布 URI、KDE
  与 GNOME 三种格式，区分复制/剪切）。
- **KWin 窗口桥**（`helpers/kwin-window-bridge`）——C++ D-Bus 桥 + KWin
  脚本，提供窗口枚举、几何、激活、最小化、缩略图与虚拟桌面数据；KWin
  本身不实现 `zwlr-foreign-toplevel-management-v1`。
- **全局快捷键**——注册为 KDE 原生 Command Shortcut，安装时检测冲突；
  可在「系统设置 → 快捷键」中改键。

### 独立应用

- **KOS 日历**——本地月历，支持重复规则、提醒和 iCalendar 导入导出。
- **KOS 待办**——本地清单与任务，支持截止时间、优先级、重复、提醒和备注。
- **KOS 天气**——读取共享服务的当前、逐小时和七日预报，支持收藏地点、
  单位切换与离线缓存。
- **KOS 音乐**——基于 GStreamer/TagLib/SQLite 的本地音乐库播放器，包含
  播放列表、持久队列、音频转换和完整 MPRIS 服务。

它们是四个独立的 CMake 模块和普通 Qt Quick 进程，不会把应用界面加载进
Quickshell。

---

## 环境要求

| 组件 | 要求 |
| --- | --- |
| 会话 | KDE Plasma 6 + Wayland（开发环境为 Plasma/KWin 6.7） |
| Shell 运行时 | [Quickshell](https://quickshell.org) 0.3.0（`qs`） |
| 构建工具 | Go、CMake、C++ 编译器、Qt 6 Gui 开发文件、`socat` |
| 独立应用 | Qt 6 Quick/Controls/D-Bus/SQL；日历/待办需要 KF6CalendarCore；天气需要 Go；音乐需要 GStreamer 与 TagLib |
| 运行时集成 | NetworkManager（`nmcli`）、systemd 用户会话、logind |
| 可选 | `cliphist`（剪贴板历史）、`qdbus6`/`kwriteconfig6`（特效同步） |

Arch 系发行版的构建依赖通常是 `go cmake gcc qt6-base`；Debian/Ubuntu 为
`golang cmake g++ qt6-base-dev`。编译 KWin 特效还需要 KWin 开发包
（`kwin-dev` / `kwin-devel`）与 KF6 开发头文件。

## 安装

克隆仓库后，按需安装各组件。除 KWin 特效外，所有内容都安装到用户目录
或 `/usr/local`，可以干净卸载。

### 1. 运行 Shell

```sh
quickshell --path /path/to/quickshell
# 或者，如果你的 quickshell 二进制叫 qs：
qs -p /path/to/quickshell
```

入口是 `shell.qml`，它只负责实例化 `desktop/DesktopEnvironment.qml`。

### 2. 数据服务（推荐）

构建 Go 服务与 Qt 剪贴板帮助程序，安装到 `~/.local/lib/quickshell` 并
启用 systemd 用户单元：

```sh
./tools/install-shell-data-service.sh
```

没有它，系统指标、活动账本、桌面文件以及跨应用的文件复制/剪切不可用。

### 3. KWin 窗口桥（Plasma 下必需）

```sh
cmake -S helpers/kwin-window-bridge -B .build/kwin-window-bridge
cmake --build .build/kwin-window-bridge
sudo install -m 0755 .build/kwin-window-bridge/quickshell-kwin-window-bridge \
    /usr/local/libexec/quickshell-kwin-window-bridge
```

Shell 运行时由 `WindowService` 自动启动桥接并加载 KWin 脚本；在实现了
foreign-toplevel-management 的合成器上桥接保持闲置。

### 4. KWin 玻璃特效（推荐）

`integrations/kwin-effects-glass` 内 vendored 的 fork 是权威源码；发行版
打包与手动编译方法见其 [README](integrations/kwin-effects-glass/README.md)。
安装后在「系统设置 → 桌面特效」中启用（插件 ID 为 `blurplus`）。之后模糊
与折射强度由 Shell 的外观设置实时驱动。

### 5. 可选的内置 KWin 特效

```sh
for effect in kwin-dock-window-animation kwin-context-menu-input; do
    cmake -S "integrations/$effect" -B ".build/$effect"
    cmake --build ".build/$effect"
    sudo cmake --install ".build/$effect"
done
```

在「系统设置 → 桌面特效」中启用。Dock 窗口动画风格（`scale` / `genie`）
跟随 Shell 的外观配置。

### 6. 设置应用

```sh
cmake -S apps/settings -B .build/apps/settings
cmake --build .build/apps/settings
```

桌面入口模板见 `packaging/desktop/kos-settings.desktop.in`。

### 7. 日历、待办、天气与音乐

将四个独立应用注册为持久的用户应用：

```sh
./tools/install-apps.sh
```

安装器会完成 Release 构建和测试，把桌面入口、hicolor 图标与 AppStream
元数据安装到 `~/.local`，启用 PIM 和共享数据用户服务，并刷新 Plasma 应用
缓存。脚本可重复执行，也是开发机的升级入口。

如果只具备一组依赖，可改用 `calendar-dev`、`todo-dev`、`weather-dev` 或
`music-dev`。日历/待办会安装可由 D-Bus 激活的本地 PIM 服务；天气会构建、
安装共享 Go 数据服务并在需要时自动启动；音乐使用系统 GStreamer 插件并发布
MPRIS。每个应用目录内都有中英文使用说明。请像上例一样在配置阶段指定安装
前缀，因为生成的 D-Bus 激活文件会记录服务可执行文件的最终路径。PIM 提醒和
共享天气/指标服务通过 systemd 用户单元绑定到图形会话；若日历或待办在服务
启动前打开，D-Bus 激活仍会作为后备路径启动 PIM 服务。

### 8. 全局快捷键

```sh
python3 helpers/global-shortcuts/install.py
```

注册带冲突检测的 KDE Command Shortcut 并写入默认绑定。修改
`helpers/global-shortcuts/shortcuts.json` 后需重跑；之后改键请在
「系统设置 → 快捷键」中进行。

### 9. 通知接管

Quickshell 的通知服务只有在 Plasma 通知组件让位后才能拿到 D-Bus 名称：
在托盘设置中移除通知组件，并重启一次 plasmashell
（`systemctl --user restart plasma-plasmashell`）。

### 默认快捷键

| 快捷键 | 功能 |
| --- | --- |
| `Meta+Space` | 应用启动器 |
| `Meta+Shift+Space` | 窗口切换器（MRU） |
| `Meta+B` | 控制中心 |
| `Meta+Tab` | 工作区概览 |

## 项目结构

```text
shell.qml       稳定的 Quickshell 入口
desktop/        桌面环境本体（bar、dock、deskcenter、启动器……）
apps/           独立 Qt Quick 应用（settings、calendar、todo、weather、music）
shared/         纯 Qt Quick 的跨进程公共 QML 与契约
services/       常驻后台服务（shell-data-service，Go）
helpers/        按需启动的原生帮助程序（KWin 桥、快捷键、剪贴板）
integrations/   KWin 特效等合成器集成
tools/          安装、构建与诊断脚本
docs/           架构文档
```

## 文档

- [功能架构](docs/FunctionalArchitecture.md)——系统全景、功能子系统与跨进程数据流
- [项目架构](docs/ProjectArchitecture.md)——运行时边界与依赖方向
- [Dock 架构](docs/DockArchitecture.md)——身份、窗口模型、持久化与显示模式
- [外观架构](docs/AppearanceArchitecture.md)——schema、IPC 契约与语义 Token
- [网络架构](docs/NetworkArchitecture.md)——NetworkManager 适配层边界
- [数据服务](docs/ShellDataService.md)——Go 数据层的职责与协议
- [本地 PIM 架构](docs/PimArchitecture.md)——日历/待办存储、D-Bus 契约、
  重复规则与提醒
- [天气架构](docs/WeatherArchitecture.md)——数据提供方、缓存与 App/Shell
  消费边界
- [音乐架构](docs/MusicArchitecture.md)——音乐库、GStreamer、转换、MPRIS、
  开源调研与第一版边界
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md)——浓缩的工程上下文与关键技术决策

## 后续开发计划

按大致优先级排列：

- **多显示器每屏布局**——DeskCenter 组件、桌面图标布局、Dock 位置/显示
  规则与壁纸取色按显示器持久化。
- **DeskCenter 主题接入**——让桌面卡片消费外观 Token 层（最后一个未
  接入的 surface）。
- **设置覆盖面**——`kos-settings` 增加快捷键与 DeskCenter 设置页。
- **独立应用后续能力**——在本地优先的 v1 边界稳定后，补充日历周/日视图、
  待办子任务与排序界面、天气雷达/预警、音乐无缝播放/ReplayGain 和云端
  提供方适配。
- **可访问性与键盘导航**——焦点顺序、减少动画、高对比度与全键盘操作。
- **天气图标集**——用完整 SVG 图标集替换目前 Unicode 字符、Canvas 绘制
  与部分 SVG 混用的方案。

已搁置：跨文件管理器的拖拽移动（受 Wayland DnD action 协商限制），目前
仅由剪贴板桥接覆盖复制/剪切。

## 开发

```sh
qmllint <改动的 QML 文件>
node desktop/modules/dock/test_adaptive.mjs
node desktop/modules/dock/test_autohide.mjs
git diff --check
```

运行时验证会启动独立的 Quickshell 实例并检查日志，流程见
`.agents/skills/verify/SKILL.md`。提交格式为 `feat(scope): description`。
