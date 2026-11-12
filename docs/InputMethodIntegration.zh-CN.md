# 输入法集成与应用兼容性指南

[English](InputMethodIntegration.md)

NextKde 为桌面环境提供基于 Fcitx5 与 Kimpanel 协议的原生液态玻璃输入法浮窗（包含候选词面板与语言切换指示）。在 Wayland 会话下，桌面外壳统一负责渲染输入法界面。由于 Linux 生态中不同 GUI 工具包与独立打包应用对 Wayland 文本输入协议（`text-input-v3`）的支持程度参差不齐，本文档说明 NextKde 输入法架构、环境要求以及常见应用的兼容性适配方案。

---

## 一、核心架构与环境约定

1. **D-Bus 通信链路**：
   - `kos-platform` (`KimpanelBridge`) 仅为已启用且连接中的前端注册 `org.kde.impanel`。Fcitx 按界面可用性选择 Kimpanel，接管期间暂停 Classic UI。
   - Fcitx5 将候选词列表、预编辑文本（Preedit）与光标位置通过 `org.kde.kimpanel.inputmethod` D-Bus 接口广播给桌面外壳。
   - 统一面板扩展直接发布输入上下文的候选内容。Fcitx 的 Kimpanel 在 KDE 下会把 Wayland/XWayland 委托给 Classic UI，因此扩展不调用其候选更新入口；选词、翻页直接交给扩展当前显示的输入上下文。
   - `kos-shell` (`InputMethodPopup.qml`) 接管候选词渲染，呈现带弹性物理动效、背景模糊与材质高光的液态玻璃卡片。

2. **按需接管与恢复**：
   - 功能默认关闭，仅在用户启用且 Shell 前端连接时接管。开关不再改写 Fcitx 扩展配置。旧版本留下的 `~/.config/kos/inputmethod-recovery.json` 只向已运行的 Fcitx 恢复一次，成功后删除。
   - 切换不再重启 Fcitx 或修改 KWin 输入法命令。释放面板租约后，Fcitx 通过界面可用性机制恢复原生面板，保留合成器输入连接。设置页显示实际启用状态和错误。
   - 保留正常工作的 Qt/XCB、GTK、XIM 输入配置。NextKde 不改写全局 `GTK_IM_MODULE` 或 `QT_IM_MODULE`；下方的兼容性调整仅用于尚未接通输入法的应用。
   - Shell 入口通过 Quickshell 仅作用于当前进程的 `Env` 指令，将 `QT_IM_MODULE` 和 `QT_IM_MODULES` 指定为 `wayland`。启动台搜索等 Shell 输入框由此使用合成器输入链路，避免 Fcitx Qt 模块自行绘制候选框；安装版、源码和开发模式均生效，也不改变所启动应用的环境。更新这类启动指令后需要重启 Shell，QML 热重载不能替换已经创建的 Qt 输入上下文。
   - 绝对光标坐标按配置的 XWayland 根坐标缩放换算为逻辑坐标。坐标不落入任何输出时，回退到活动窗口所在屏幕，避免所有候选框同时隐藏。

---

## 扩展安装

常规 `kosctl install` 包含 Fcitx5 开发依赖，自动将动态库安装到
`$KOS_PREFIX/lib/fcitx5`（默认 `~/.local/lib/fcitx5`），并将带绝对库路径的扩展描述
写入 `$FCITX_DATA_HOME/addon` 或 `$XDG_DATA_HOME/fcitx5/addon`。不改全局模块变量，
不改变输入方案、词库或快捷键。CMake 系统安装使用标准 `lib/fcitx5` 和
`share/fcitx5/addon`；NixOS 模块将扩展加入 Fcitx5 addons。

安装或更新扩展后需要注销并重新登录，让 Fcitx 加载新动态库；此后的功能开关只获取或释放
面板租约。接管要求 Kimpanel 和原生 Classic UI 均可用，扩展确认后才报告启用。
租约丢失时，扩展立即恢复各输入上下文原有的候选面板回调。旧版扩展配置迁移不自动
启动 Fcitx；若当前会话启动时 Classic UI 被旧版禁用，需要重新登录才能加载。

## 候选框呈现偏好

设置 → 接入状态 → 候选框外观提供液态/磨砂材质、12–24 号字号、跟随输入法/横向/纵向/自动布局、
注释显隐、不透明高对比度和减少动画。自动布局在横向放不下时切换为纵向，长列表
可滚动，并跟随输入法选中的候选项；界面不会重排候选词或改变选词索引。

候选框材质可独立切换，默认保持液态玻璃。磨砂模式使用均匀模糊，不带透镜折射，
即使桌面液态预设的模糊强度为零也能生效；切换不会改动桌面全局材质。高对比度
模式优先使用不透明背景，关闭后恢复所选材质。

默认保留展开与收起动效，候选框尺寸连续过渡，选中底板平滑跟随，长列表自动滚动。
连续输入不会重播入场动画，选词也不必等待动画完成。“减少动画”是可选的无障碍
偏好，关闭它即可使用完整动效。

这些偏好仅保存到 `$XDG_STATE_HOME/quickshell/kos/inputmethod/presentation.json`
（通常位于 `~/.local/state`）。调整它们不会调用 Fcitx 配置接口、重启 Fcitx，也不
改变输入方案、词库或快捷键。既有实验接管开关是独立功能，仍保留上文所述的插件
备份及恢复行为。

## 二、应用兼容性矩阵与排障指引

### 1. 原生现代应用（标准 Qt 6 / GTK 3 / GTK 4）
- **典型软件**：Dolphin、Kate、Konsole、Firefox、GNOME 原生应用、KDE 核心组件。
- **支持状态**：已连接 Fcitx5 的 Qt、GTK 模块与原生 Wayland 输入统一接管，无需为候选框改环境变量。
- **机制与注意**：
  - GTK 3/4 使用 Wayland `text-input-v3`；Qt 使用其运行时和 KWin 共同支持的 Wayland 文本输入协议，不能一概称为 `text-input-v3`。
  - 保留现有可用的 `GTK_IM_MODULE`、`QT_IM_MODULE` 和 `XMODIFIERS` 设置。扩展通过 Fcitx5 的自定义面板接口绕过客户端候选面板渲染，预编辑文字仍发送给应用。
  - 安装 NextKde 后，在设置中开启一次即可。`kosctl install` 自动构建并部署扩展；扩展只在 NextKde 持有租约且 Kimpanel 可用时接管，平时保持不活动。
  - 开关会确认扩展的版本、进程归属与实际接管状态。扩展未安装、被禁用或加载失败时自动回退并显示错误，保留原有输入配置。
  - 虚拟机已实测 Kate 的 Fcitx/Wayland 路径、GTK 3 的 Fcitx Wayland/X11 路径与 GTK 4 的 Fcitx Wayland 路径。未经过 Fcitx5 的应用仍须先接通输入法，扩展无法为其凭空增加输入支持。

### 2. Chromium 与 Electron 框架应用
- **典型软件**：Google Chrome、Chromium、VS Code、Obsidian、Discord、Slack、Linux QQ。
- **支持状态**：**完全支持（需开启 Wayland IME 特性标志）**。
- **机制与启动参数**：
  Chromium 内核在 Wayland 原生模式下必须开启 Wayland IME 特性开关，才能与合成器的 text-input 协议交互。
  如果出现点击输入框无候选框或误弹全屏虚拟键盘，请在快捷方式或启动命令中补充参数：
  ```bash
  --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3
  ```
  *(或使用 `--ozone-platform-hint=auto --enable-wayland-ime`)*

### 3. 自带私有 Qt 运行时的独立打包应用（封闭二进制 / RPM / 独立目录）
- **典型软件**：官方 Linux 原生微信（RPM/DEB 4.x+）、Calibre 独立版、WPS Office、百度网盘。
- **支持状态**：已有可用 Fcitx 输入链路时统一接管；尚未接通输入法的应用仍可能需要工具包专属模块。
- **根因分析**：
  此类软件通常静态内联或在私有目录隔离加载了魔改 Qt 动态库，不使用系统 Qt6。当全局 `QT_IM_MODULE` 为空时，私有运行时往往不会自动回退到 Wayland 协议，导致“完全无法调出中文输入法”；如果已能通过 Fcitx Qt 插件输入，则统一面板扩展会接管候选框，无需更换输入模块。
- **适配方案**：
  - **官方微信（WeChat 4.x+ 原生版）**：
    微信内部静态编译了 `WaylandTextInputV3ContextPlugin`，其注册的插件工厂键名为 `text-input-unstable-v3`。通过为其注入该参数，可接通其 Wayland 中文输入链路：
    ```bash
    # 微信专用启动环境变量
    export QT_IM_MODULE=text-input-unstable-v3
    export GTK_IM_MODULE=
    export XMODIFIERS="@im=fcitx"
    exec /opt/wechat/wechat "$@"
    ```
  - **Calibre 独立包**：
    Calibre 官方包未附带 `fcitx5-qt` 插件，但自带 IBus 插件。可通过 Fcitx5 的 IBus 兼容前端输入：
    ```bash
    export QT_IM_MODULE=ibus
    exec /opt/calibre/calibre "$@"
    ```
  - **其他未提供 Wayland text-input 插件的老旧 Qt5 应用**：
    若应用内置的 Qt 过于老旧（缺乏 Wayland text-input 支持），作为基本可用性降级方案，仅为该应用单独设置 `QT_IM_MODULE=fcitx`，只要该输入模块连接的是当前 Fcitx5，候选框也由统一扩展接管。

### 4. XWayland 传统应用与游戏
- **典型软件**：Wine / Proton 模拟运行的游戏、老旧 X11 工具、未迁移到 Wayland 的 Java/AWT 程序。
- **支持状态**：**兼容支持（走 XIM / XWayland 桥接）**。
- **机制**：由系统全局的 `XMODIFIERS=@im=fcitx` 提供基础 XIM 服务。

---

## 三、快速排障清单

| 现象 | 排查定位 | 推荐处置方案 |
| :--- | :--- | :--- |
| **候选框呈现为旧式白色带角方框** | 接管未启用或扩展未更新 | 查看设置页状态；安装扩展后注销并重新登录 |
| **按键直接英文上屏，无候选框** | 属于自带私有 Qt 的闭源应用（如微信），模块变量为空时未自动协商 Wayland 输入 | 针对该应用单独设置 `QT_IM_MODULE=text-input-unstable-v3`（微信）或排查对应 IME 启动参数 |
| **Chromium/VSCode 无法打字或弹软键盘** | Chromium 缺失 Wayland IME 命令行特性开关 | 桌面项追加 `--enable-wayland-ime --wayland-text-input-version=3` |
| **KWin 弹出全屏软键盘遮挡** | `kwinrc` 中误将虚拟键盘设为了鼠标触发模式（Mode 2） | 终端执行 `kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardMode 0` 并刷新 KWin |
