# Quickshell 项目上下文

> 本文件由 Codex 开发对话历史提炼，供 Trae/AI 助手快速恢复开发上下文。
> 完整对话历史见 `docs/codex-history/`，架构详情见 `docs/` 下各文档。

## 项目概述

基于 Quickshell 框架的 Linux 桌面 Shell，运行于 KDE Plasma (Wayland)，使用 QML/JavaScript 开发。目标是构建 iPadOS 风格的完整桌面体验。

## 技术栈

- **框架**: Quickshell v0.3.0 + Qt 6
- **桌面环境**: KDE Plasma (Wayland)，此前用 Hyprland
- **数据服务**: Go (`tools/shell-data-service`，systemd --user 服务)
- **KWin 扩展**: C++ D-Bus bridge + KWin JavaScript 脚本 (`tools/kwin-window-bridge/`)
- **KWin 玻璃特效**: C++ effect + GLSL 折射 shader (`kwin-effects-glass/`，Dual Kawase 模糊 + Snell 折射)
- **客户端 shader**: Qt Shader Binary (`shaders/liquid.frag` + `compile.sh`，用 `qsb` 编译)
- **图标主题**: KDE 用 `MacTahoe-blue-light`，Qt6ct 用 `Tela-circle-dracula-dark`

## 模块结构

```
shell.qml (ShellRoot)
├── QuickSearch    - 快速搜索 + 剪贴板历史
├── AppLauncher    - 应用启动器（iPadOS 风格网格 + 文件夹）
├── NotificationCenter - Wayland/DBus 通知横幅
├── DeskCenter     - 桌面层组件（时钟/天气/日历/系统信息/活动记录/桌面文件）
├── Bar            - 顶部状态栏（32px，系统指标/网络/蓝牙/音量/控制中心）
└── Dock           - 底部 Dock（iPadOS 风格 pinned + 运行窗口 + MPRIS + 回收站）
```

## 服务分层

```
AppPresentationService ──-> AppLauncher / QuickSearch / shared AppIcon
        ↑
AppIdentityService -> WindowService -> AppGroupService -> Dock / Alt+Tab / Preview
AppActionService ──-> launch / pin / unpin / hide / edit requests
```

- UI 组件只消费 service 模型，不直接调 DesktopEntries/ToplevelManager。
- 跨 Surface、需持久化或有历史聚合的数据放 `shell-data-service`（Go），QML 仅负责呈现。

## 关键技术决策

1. **天气 API**: 用 Open-Meteo（免费无需 Key），非和风天气。每小时刷新，刷新失败时保留上次缓存值（`stale` 标记超过 2 倍刷新周期的数据）。长沙坐标硬编码。
2. **DeskCenter**: 用 `WlrLayer.Background` 层（常驻桌面，非弹出），10 列网格。卡片用纯色 `Rectangle`+`Gradient`，**不启用液态玻璃**（选平静配色而非玻璃面，保证白字可读）。
3. **液态玻璃分层**（重要，按是否依赖 compositor blur 分两路）:
   - **compositor blur 路线**: `BackgroundEffect.blurRegion: RoundedBlurRegion { ... }` 把圆角模糊区域交给 KWin 原生 blur，再叠 `LiquidGlassSurface.qml`（材质：反射/壁纸取色/高光发丝线，不生成 blur region）。圆角区域用 `RoundedBlurRegion.qml` 的「2 矩形 + 4 椭圆」拼合（Wayland Region 只有矩形原语）。**Dock / AppLauncher / QuickSearch / Weather / Notification / DockPreview / DockMusicPopup 走这条路**。
   - **无 compositor blur 路线**: `BackgroundEffect.blurRegion: null` + `EnhancedGlassSurface.qml`（dark base layer `rgba(0.03,0.03,0.05,0.30)` + 复用 `LiquidGlassSurface` 材质）。为 popup 提供自带可读性，不依赖 KWin blur。**ControlCenter / Bluetooth / Network 三个 bar popup 走这条路**。
   - **KWin effect**: `kwin-effects-glass/` 是 Plasma 6 blur 的 fork，含 Dual Kawase 模糊 + Snell 折射 shader（`snells-glass.glsl`），已编译安装。客户端 `shaders/liquid.frag` 也含 SDF 圆角 + 径向折射 + 噪声 + glow。
4. **AppLauncher 揭示动画**: 已移除展开动画（KWin backdrop blur 无法与 QML 逐帧动画同步会留白卡），改为**静态模糊区域 + 前景 fade**。关闭是原子的，不留空玻璃卡。
5. **KWin 窗口管理**: 以标准 Wayland `ToplevelManager`（`Quickshell.Wayland._ToplevelManagement`，Hyprland/KDE 通用）为主；KWin 不实现 `zwlr-foreign-toplevel-management-v1`，故用 KWin Script + C++ D-Bus bridge 作为**回退**（foreign toplevel 为空时启用）。
6. **图标解析**: bridge 中用 `KIconLoader` + `kdeglobals` 读取主题；裸路径须转 `file:///`。
7. **通知**: 用 Quickshell 原生 `NotificationServer`（`keepOnReload: false`，不跨重载持久化），需从 Plasma 托盘移除通知小部件并重启 plasmashell 才能接管 D-Bus。DND 时通知仍接受但立即 untrack。
8. **Dock 窗口模型**: 默认不聚合（KDE 风格），所有窗口各自显示；固定应用有窗口时从固定区隐藏（`pinnedVisible = pinned && windows.length === 0`）。
9. **Dock 自适应**: 唯一自变量 `iconSize`，高度/间距/圆角全部按比例推导。`dockHeight = Math.round(iconSize × (1 + 2×vpad))`，默认 `vpad=0.20` 即 **`iconSize × 1.40`**；最小图标 24px，最大 dock 高 60px。核心文件 `AdaptiveMath.mjs`。Dock 的 folder 功能已移除（legacy folder 在加载时被摊平为 app）。
10. **桌面文件**: `DesktopFilesService.qml` 不自己扫盘，消费 `shell-data-service` 的 `snapshot.json` + socket 通知；视图只负责呈现与交互。支持排序（名称/类型/修改时间）、框选、重命名、回收站、文件夹投放（hold-to-drop 520ms 进度条）、多选拖动、新建文件/文件夹、外部 URL 拖入、cut/copy 语义。
11. **系统指标收口**: CPU/内存/磁盘/频率/温度的采样、历史（10s 采样，360 条）与传感器枚举全部在 Go 服务（`shell-data-service`）完成，QML 经 `common/MetricsService.qml` 单例每 10s 读 `snapshot.json`；活动账本（在线时长 + 按应用时长）由 Go 服务从 journald 播种并每秒 settle，`ActivityUsageService.qml` 只负责把前台窗口经 socket 上报 `active_app` 事件。Bar 的 `CpuTemperature` 与 DeskCenter 系统卡读同一快照，数值永不漂移。`SystemMetricsService`/`activity-usage.json` 已移除。
12. **全局快捷键**: KDE **Command Shortcut** 机制（`.desktop` + `X-KDE-GlobalAccel-CommandShortcut=true` + `qs ipc call`），与用户已有的 `net.local.qs.desktop` 同款。快捷键表在 `tools/global-shortcuts/shortcuts.json`，`install.py`/`uninstall.py` 生成 desktop 文件、写 `kglobalshortcutsrc` 默认绑定、冲突检测（同键已被他方占用则跳过并提示）。触发链路：kglobalaccel 按键 → 运行 `qs ipc call <target> <action>` → 各模块 `IpcHandler`（applauncher/quicksearch 已有，`control-center` 在 `bar/Bar.qml` 新增，转发 `ControlCenterService.toggleRequested`，由 `BarWindow` 打开面板）。改键在 KDE 系统设置 → 快捷键里改，比脚本直改安全。
13. **Alt+Tab 切换（QuickSearch 窗口模式）**: 窗口结果按 MRU 排序（`WindowService._mruOrder`，新窗口置前、当前激活窗口置末尾），打开即选中最近使用的窗口；列表行有 KWin 实时缩略图（`requestThumbnail`，app 图标兜底，2s 慢轮询补抓）。Alt+Tab 已由 Command Shortcut 绑定到 `quicksearch toggle window`。
14. **控制中心亮度**: 读 `/sys/class/backlight/*`（首设备 current/max），写走 **logind `SetBrightness`**（session owner 无需 /sys 写权限）；面板拖拽条 + `%` 显示，无亮度设备时显示「无亮度设备」并禁用拖拽。状态在 `ControlCenterService`（`brightnessAvailable`/`brightnessPercent`/`setBrightness`），与音量同模式。

## 开发规范

- **验证**: 用 `.agents/skills/verify/SKILL.md` 中的 verify 流程（启动独立 Quickshell 实例查日志）。
- **静态检查**: `qmllint` + `node modules/dock/test_adaptive.mjs`（8 项）+ `git diff --check`。
- **提交格式**: `feat(scope): description` 或 `feat: description`。
- **尺寸不写死**: 新组件按 `iconSize` 或 `cellSize` 比例缩放。
- **玻璃面选择**: 需 compositor blur 的表面用 `LiquidGlassSurface` + `RoundedBlurRegion`；无 blur 依赖的 popup 用 `EnhancedGlassSurface`（自带 dark base）。不要混用——给 `EnhancedGlassSurface` 再加 `blurRegion` 会双重遮挡。
- **QML 陷阱**:
  - `Rectangle { radius; clip: true }` 的 clip 不按 radius 裁圆角，需 `OpacityMask`。
  - `PopupWindow` 关闭后会覆盖 `visible` 绑定，应直接 `visible = true`。
  - `Region` 不接受动态 `Repeater` 子项。
  - 内联 `anchors { ... }` 对象后不能用分号继续声明属性。
  - KWin backdrop blur 无法与 QML 逐帧动画同步，需动画的玻璃面用静态区域 + 前景 fade。

## 已知问题和未完成工作

### P0（路线图最高优先级）
- **Wi-Fi 文档对齐**: Wi-Fi 连接/断开/忘记/802.1X **已实现**（`NetworkService.qml` 的 `connectWifi`/`disconnectActiveWifi`/`forgetWifiProfile`/`connectEnterpriseWifi`），但 `NetworkService.qml` 内有过期注释声称未实现，需清理并对齐文档。

### 待优化
- 天气图标用 Unicode 字符（`☀⛅☁☔❄`）表示状况符号；桌面天气卡片云层用 SVG（`assets/weather-cloud*.svg`），其余太阳/雨/雪/雾用 `Rectangle`/`Canvas` 绘制。缺完整天气 SVG 图标集。
- DeskCenter 未启用液态玻璃（保证文字可读性）。
- Bar 高 35px，左右各缩进 15px（`margins.left/right: 15`）。
- 隐藏应用无恢复入口。
- 通知历史中心缺失（当前只有即时横幅，DND 通知被 untrack 后不保留）。

### 已搁置
- 跨 Dolphin 文件移动（Wayland 剪贴板限制，`tools/desktop-clipboard-helper/` 为空目录占位）。

## Git 历史

最近提交（`git log --oneline` 查看完整列表）：

```
6d122a8 feat: enhance desktop shell interactions          (2026-08-05)
f4d44d2 feat: refine shell surfaces and glass effects     (2026-08-03)
fcd94e8 feat: add launcher and unified shell surfaces     (2026-07-28)
d3037ed Add adaptive glass palettes                       (2026-07-23)
d95d2f3 Add QML liquid glass surfaces                     (2026-07-22)
d7ab27b feat(dock): add KWin window bridge and themed icons (2026-07-22)
8c18ab9 feat: add dock edit mode interactions             (2026-07-18)
2208235 feat: support drag into dock folders              (2026-07-18)
92bb0f4 feat: add iPadOS-style bar and dock folders       (2026-07-18)
43d2afb feat: adopt iPad-style pinned dock model          (2026-07-18)
4c9d539 chore: create dock baseline                       (2026-07-18)
```

> 注：`2208235` 的 "drag into dock folders" 指早期的 Dock folder 功能，该功能现已移除（加载时摊平为 app）；当前文件夹交互只在 AppLauncher 与 DeskCenter 桌面文件中。

## 配置与状态

- `config/dock/config.json` 是 Dock 的**种子模板**；运行时实际读取 `Quickshell.stateDir + "/dock/config.json"`，修改源文件不影响已运行的实例。
- 各模块状态文件位于 `Quickshell.stateDir/` 下：`dock/config.json`、`applauncher/config.json`、`bar/usage-history.json`、`weather/current.json`、`activity-usage.json`。
- `shell-data-service` 的快照在 `$XDG_STATE_HOME/quickshell/shell-data-service/`（`state.json` + `snapshot.json`），socket 在 `$XDG_RUNTIME_DIR/shell-data-service.sock`。

## 文档索引

- [DockArchitecture.md](docs/DockArchitecture.md) - Dock 身份/窗口/持久化约定
- [NetworkArchitecture.md](docs/NetworkArchitecture.md) - 网络服务适配层
- [ShellDataService.md](docs/ShellDataService.md) - Go 数据服务边界
- [DesktopCompletionRoadmap.md](docs/DesktopCompletionRoadmap.md) - 完整桌面路线图
- [codex-history/index.md](docs/codex-history/index.md) - Codex 开发对话历史（52 个会话）
