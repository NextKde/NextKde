# Quickshell 项目上下文

> 本文件提炼项目开发上下文，供 AI 助手快速恢复开发上下文。
> 架构详情见 `docs/` 下各文档（索引在文末）。

## 项目概述

基于 Quickshell 框架的 Linux 桌面 Shell，运行于 KDE Plasma (Wayland)，使用 QML/JavaScript 开发。目标是构建 iPadOS 风格的完整桌面体验。

## 技术栈

- **框架**: Quickshell v0.3.0 + Qt 6
- **桌面环境**: KDE Plasma (Wayland)，此前用 Hyprland
- **数据服务**: Go (`services/shell-data-service`，systemd --user 服务)
- **KWin 扩展**: C++ D-Bus bridge + KWin JavaScript 脚本 (`helpers/kwin-window-bridge/`)
- **KWin 玻璃特效**: C++ effect + GLSL 折射 shader (`integrations/kwin-effects-glass/`，Dual Kawase 模糊 + Snell 折射)
- **客户端 shader**: Qt Shader Binary (`desktop/shaders/liquid.frag` + `compile.sh`，用 `qsb` 编译)
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
   - **KWin effect**: `integrations/kwin-effects-glass/` 是 Plasma 6 blur 的 fork，含 Dual Kawase 模糊 + Snell 折射 shader（`snells-glass.glsl`），已编译安装。客户端 `desktop/shaders/liquid.frag` 也含 SDF 圆角 + 径向折射 + 噪声 + glow。
4. **AppLauncher 揭示动画**: 已移除展开动画（KWin backdrop blur 无法与 QML 逐帧动画同步会留白卡），改为**静态模糊区域 + 前景 fade**。关闭是原子的，不留空玻璃卡。
5. **KWin 窗口管理**: 以标准 Wayland `ToplevelManager`（`Quickshell.Wayland._ToplevelManagement`，Hyprland/KDE 通用）为主；KWin 不实现 `zwlr-foreign-toplevel-management-v1`，故用 KWin Script + C++ D-Bus bridge 作为**回退**（foreign toplevel 为空时启用）。
6. **图标解析**: bridge 中用 `KIconLoader` + `kdeglobals` 读取主题；裸路径须转 `file:///`。
7. **通知**: 用 Quickshell 原生 `NotificationServer`（`keepOnReload: false`，不跨重载持久化），需从 Plasma 托盘移除通知小部件并重启 plasmashell 才能接管 D-Bus。DND 时通知仍接受但立即 untrack。
8. **Dock 窗口模型**: 默认不聚合（KDE 风格），所有窗口各自显示；固定应用有窗口时从固定区隐藏（`pinnedVisible = pinned && windows.length === 0`）。
9. **Dock 自适应**: 唯一自变量 `iconSize`，高度/间距/圆角全部按比例推导。`dockHeight = Math.round(iconSize × (1 + 2×vpad))`，默认 `vpad=0.20` 即 **`iconSize × 1.40`**；最小图标 24px，最大 dock 高 60px。核心文件 `AdaptiveMath.mjs`。Dock 的 folder 功能已移除（legacy folder 在加载时被摊平为 app）。
10. **桌面文件**: `DesktopFilesService.qml` 不自己扫盘，消费 `shell-data-service` 的 `snapshot.json` + socket 通知；视图只负责呈现与交互。支持排序（名称/类型/修改时间）、框选、重命名、回收站、文件夹投放（hold-to-drop 520ms 进度条）、多选拖动、新建文件/文件夹、外部 URL 拖入、cut/copy 语义。
11. **系统指标收口**: CPU/内存/磁盘/频率/温度的采样、历史（10s 采样，360 条）与传感器枚举全部在 Go 服务（`shell-data-service`）完成，QML 经 `common/MetricsService.qml` 单例每 10s 读 `snapshot.json`；活动账本（在线时长 + 按应用时长）由 Go 服务从 journald 播种并每秒 settle，`ActivityUsageService.qml` 只负责把前台窗口经 socket 上报 `active_app` 事件。Bar 的 `CpuTemperature` 与 DeskCenter 系统卡读同一快照，数值永不漂移。`SystemMetricsService`/`activity-usage.json` 已移除。
12. **全局快捷键**: KDE **Command Shortcut** 机制（`.desktop` + `X-KDE-GlobalAccel-CommandShortcut=true` + `qs ipc call`），与用户已有的 `net.local.qs.desktop` 同款。快捷键表在 `helpers/global-shortcuts/shortcuts.json`，`install.py`/`uninstall.py` 生成 desktop 文件、写 `kglobalshortcutsrc` 默认绑定、冲突检测（同键已被他方占用则跳过并提示）。触发链路：kglobalaccel 按键 → 运行 `qs ipc call <target> <action>` → 各模块 `IpcHandler`（applauncher/quicksearch 已有，`control-center` 在 `bar/Bar.qml` 新增，转发 `ControlCenterService.toggleRequested`，由 `BarWindow` 打开面板）。改键在 KDE 系统设置 → 快捷键里改，比脚本直改安全。
13. **Alt+Tab 切换（QuickSearch 窗口模式）**: 窗口结果按 MRU 排序（`WindowService._mruOrder`，新窗口置前、当前激活窗口置末尾），打开即选中最近使用的窗口；列表行有 KWin 实时缩略图（`requestThumbnail`，app 图标兜底，2s 慢轮询补抓）。Alt+Tab 已由 Command Shortcut 绑定到 `quicksearch toggle window`。
14. **控制中心亮度**: 优先走 **KDE Plasma 6 `org.kde.Solid.PowerManagement.Actions.BrightnessControl` 与 `org.kde.ScreenBrightness`**（支持内建屏幕及外接 DDC/CI 显示器，如 DisplayPort/HDMI 屏幕）；降级回退 `/sys/class/backlight/*` 读 + logind `SetBrightness` 写。面板拖拽条 + `%` 显示，无亮度设备时显示「无亮度设备」并禁用拖拽。状态在 `ControlCenterService`（`brightnessAvailable`/`brightnessPercent`/`setBrightness`），与音量同模式。
15. **控制中心液态按钮**: 合成器 blur 是窗口级的，单个控件读不到窗口背后像素。`common/LiquidGlassControl.qml` 用 `ShaderEffectSource`（捕获窗口内层）→ `FastBlur` → `OpacityMask`（圆形裁剪）→ 玻璃高光/描边，实现控件级磨砂；`sourceItem` 为空时降级纯玻璃圆。媒体卡播放按钮模糊一层淡壁纸色调底（`WallpaperPaletteService` 主/次色 16%/7% 渐变，兼作卡片液态底），呈"吸收环境色调的磨砂透镜"。勿用封面作按钮模糊源（会透出封面碎块感）。
16. **通知历史中心**: 会话内历史（不跨重启）。dismiss/expire 前快照（`NotificationGroupService._pushHistory`），**DND 期间 untrack 的通知也立即快照**（否则永不触发 dismiss 直接丢失）。`ControlCenterService.notificationHistory`（ListModel，上限 50）+ `historyGroups`（按 app 分组 JS 数组，随模型变化重建）。控制中心 Card 9：分组头（图标+应用名）+ 每条通知行 + 单条 × 删除 + 全部清空。action 执行仍缺失（快照只存文本）。
17. **工作区概览 / Stage Manager**: `desktop/modules/overview/`（概览全屏遮罩：顶栏虚拟桌面条 + 当前桌面窗口缩略图网格）。数据层：KWin 脚本快照加 `desktops`/`onAllDesktops` 字段（`window.desktops` 的 id 列表）+ `publishDesktops()` 事件（desktopAdded/Removed/NameChanged/currentDesktopChanged 均触发）；bridge 命令新增 `desktops`（查询列表）、`switch-desktop`、`move-to-desktop`（KWin script 处理，走 `workspace.currentDesktop`/`window.desktops`）；`WindowService` 透传 `desktops` 列表/`currentDesktopId` + 三个命令函数。快捷键 `Meta+Tab`（`overview toggle`）。点击桌面切换、点窗口激活并关闭概览、Esc 关闭、←→ 选桌面、回车切到选中桌面。
18. **全局外观形态**: `common/AppearanceConfigService.qml` 持久化 schema 4（玻璃强度、`windows12|macos|material`、`barIntegratedWithDock`、`dockWindowAnimationStyle: scale|genie`），`AppearanceTokens.qml` v4 导出语义 Token。生产 Dock 已消费几何、状态背景、指示器和动效；Bar 保持统一视觉。底部 Dock 开启融合后，时间作为 `DockInfoCarousel` 的音乐/天气/时钟页面，`BarStatusArea` 成为右侧附件；侧边 Dock 用 `DockSideInfoCarousel`（内容反向旋转保持正立）并自动回退顶部 Bar。DeskCenter 尚未接入。完整规则见 `docs/AppearanceArchitecture.md`。

## 开发规范

- **验证**: 用 `.agents/skills/verify/SKILL.md` 中的 verify 流程（启动独立 Quickshell 实例查日志）。
- **静态检查**: `qmllint` + `node desktop/modules/dock/test_adaptive.mjs`（8 项）+ `git diff --check`。
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

### 未完成

- **多席位/会话切换（Switch User）兼容性**：在特定多席位（Multi-Seat，如多 Seat 实例）或非标准 DisplayManager 环境下，由于席位通信权限与 VT 切换隔离，会话切换指令可能受限，待后续引入更底层的 session gateway 进行专有适配。
- **多显示器每屏布局**：DeskCenter 小组件布局、桌面文件图标布局、Dock 位置/显示规则、壁纸与取色尚未按显示器持久化。
- **可访问性与键盘导航**：焦点顺序、高对比度、减少动画与全键盘操作未完善。
- **设置中心覆盖面**：`kos-settings` 已有显示/主题/Dock 页面；快捷键、DeskCenter 等模块设置仍待纳入。

### 待优化

- 天气图标用 Unicode 字符（`☀⛅☁☔❄`）表示状况符号；桌面天气卡片云层用 SVG（`desktop/assets/weather-cloud*.svg`），其余太阳/雨/雪/雾用 `Rectangle`/`Canvas` 绘制。缺完整天气 SVG 图标集。
- DeskCenter 未启用液态玻璃（保证文字可读性）。
- Bar 高 35px，左右各缩进 15px（`margins.left/right: 15`）。
- 隐藏应用无恢复入口。

### 已搁置

- 跨 Dolphin 文件移动（Wayland 剪贴板限制，`tools/desktop-clipboard-helper/` 为空目录占位）。

## Git 历史

近期里程碑提交（完整列表用 `git log --oneline` 查看，当前约 100 个提交）：

```
1fd8ba6 dock的融合模式                                  (2026-08-27)
255affd feat(common): public ContextMenu + MenuItemRow; dock uses it
5f75f7f feat: add TrayNotificationBridge to forward tray attention to notifications
```

早期里程碑（2026-07 至 2026-08 上旬）：Dock 基线、iPadOS 固定模型、KWin window bridge、液态玻璃表面、启动器/搜索/通知统一 surface、玻璃调色板等，见 `git log`。

> 注：历史提交中的 "dock folders" 指早期的 Dock folder 功能，该功能现已移除（加载时摊平为 app）；当前文件夹交互只在 AppLauncher 与 DeskCenter 桌面文件中。

## 配置与状态

- Dock 配置只存在于运行时 `Quickshell.stateDir + "/dock/config.json"`（仓库内无种子模板；首次运行由 `DockConfigService` 用内置默认值生成）。
- 各模块状态文件位于 `Quickshell.stateDir/` 下：`dock/config.json`、`applauncher/config.json`（含 `icons/` 自定义图标缓存）、`bar/usage-history.json`、`weather/current.json`、`appearance/config.json`。
- `shell-data-service` 的快照在 `$XDG_STATE_HOME/quickshell/shell-data-service/`（`state.json` + `snapshot.json`），socket 在 `$XDG_RUNTIME_DIR/shell-data-service.sock`。

## 文档索引

- [FunctionalArchitecture.md](docs/FunctionalArchitecture.md) - 项目全景功能架构与数据流拓扑
- [ProjectArchitecture.md](docs/ProjectArchitecture.md) - 仓库级运行时边界与依赖方向
- [DockArchitecture.md](docs/DockArchitecture.md) - Dock 身份/窗口/持久化/显示模式约定
- [AppearanceArchitecture.md](docs/AppearanceArchitecture.md) - 全局外观 schema、IPC、Token 与接入规范
- [NetworkArchitecture.md](docs/NetworkArchitecture.md) - 网络服务适配层
- [ShellDataService.md](docs/ShellDataService.md) - Go 数据服务边界
