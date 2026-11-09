# 输入法集成与应用兼容性指南

[English](InputMethodIntegration.md)

NextKde 为桌面环境提供基于 Fcitx5 与 Kimpanel 协议的原生液态玻璃输入法浮窗（包含候选词面板与语言切换指示）。在 Wayland 会话下，桌面外壳统一负责渲染输入法界面。由于 Linux 生态中不同 GUI 工具包与独立打包应用对 Wayland 文本输入协议（`text-input-v3`）的支持程度参差不齐，本文档说明 NextKde 输入法架构、环境要求以及常见应用的兼容性适配方案。

---

## 一、核心架构与环境约定

1. **D-Bus 通信链路**：
   - `kos-platform` (`KimpanelBridge`) 在初始化时注册 `org.kde.impanel` 服务，通知 Fcitx5 激活其内置的 `kimpanel` 扩展，并自动禁用 `classicui` 传统浮窗。
   - Fcitx5 将候选词列表、预编辑文本（Preedit）与光标位置通过 `org.kde.kimpanel.inputmethod` D-Bus 接口广播给桌面外壳。
   - `kos-shell` (`InputMethodPopup.qml`) 接管候选词渲染，呈现带弹性物理动效、背景模糊与材质高光的液态玻璃卡片。

2. **环境变量规范（禁止全局设置客户端 IM 模块）**：
   - **关键原则**：在 Wayland 会话中，系统环境应**保持 `GTK_IM_MODULE` 与 `QT_IM_MODULE` 为空**，仅保留 `XMODIFIERS=@im=fcitx`。
   - **原因**：若全局设置 `QT_IM_MODULE=fcitx` 或 `GTK_IM_MODULE=fcitx`，客户端应用会加载本地输入法插件并向 Fcitx5 声明 `CapabilityFlag::ClientSideInputPanel`（客户端自绘）。这会导致 Fcitx5 停止向 Kimpanel 派发事件，改为由应用在窗口内自绘传统矩形小方框，从而绕过 NextKde 的液态玻璃渲染。
   - **无全局环境污染原则**：NextKde 不会在后台静默改写或注入用户 systemd / D-Bus 会话环境变量，完全尊重用户原生配置；该功能默认保持关闭，用户可在设置中心（「系统状态与疑难排错」卡片）中手动启用「使用 NextKde 输入法候选框（实验性）」。关闭或 Shell 退出时会自动释放接管并还原 Fcitx5 原始扩展配置。

---

## 二、应用兼容性矩阵与排障指引

### 1. 原生现代应用（标准 Qt 6 / GTK 3 / GTK 4）
- **典型软件**：Dolphin、Kate、Konsole、Firefox、GNOME 原生应用、KDE 核心组件。
- **支持状态**：**原生完美支持**。
- **机制与注意**：
  - 应用在模块变量为空时，自动握手 Wayland 原生 `text-input-v3` 协议。
  - **排障**：若候选框显示为经典带尖角的白色方框而非液态玻璃，说明该应用进程继承了旧的 `GTK_IM_MODULE=fcitx` 或 `QT_IM_MODULE=fcitx`。请检查 `~/.bashrc`、`~/.xprofile` 或 `~/.config/environment.d/` 并移除强制赋值，重启应用即可。

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
- **支持状态**：**需针对性配置专属启动变量**。
- **根因分析**：
  此类软件通常静态内联或在私有目录隔离加载了魔改 Qt 动态库，不使用系统 Qt6。当全局 `QT_IM_MODULE` 为空时，私有运行时往往不会自动回退到 Wayland 协议，导致“完全无法调出中文输入法”；而若直接填 `QT_IM_MODULE=fcitx`，又会触发客户端自绘白方框。
- **适配方案**：
  - **官方微信（WeChat 4.x+ 原生版）**：
    微信内部静态编译了 `WaylandTextInputV3ContextPlugin`，其注册的插件工厂键名为 `text-input-unstable-v3`。通过为其注入该参数，可完美兼顾中文输入与 NextKde 液态玻璃浮窗：
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
    若应用内置的 Qt 过于老旧（缺乏 Wayland text-input 支持），作为基本可用性降级方案，仅为该应用单独设置 `QT_IM_MODULE=fcitx`，此时会显示传统候选框，但不影响系统其他应用的液态玻璃效果。

### 4. XWayland 传统应用与游戏
- **典型软件**：Wine / Proton 模拟运行的游戏、老旧 X11 工具、未迁移到 Wayland 的 Java/AWT 程序。
- **支持状态**：**兼容支持（走 XIM / XWayland 桥接）**。
- **机制**：由系统全局的 `XMODIFIERS=@im=fcitx` 提供基础 XIM 服务。

---

## 三、快速排障清单

| 现象 | 排查定位 | 推荐处置方案 |
| :--- | :--- | :--- |
| **候选框呈现为旧式白色带角方框** | 应用被注入了 `QT_IM_MODULE=fcitx` 或 `GTK_IM_MODULE=fcitx`，启用了 `ClientSideInputPanel` | 检查并置空该应用的 `QT_IM_MODULE` 与 `GTK_IM_MODULE`，使之走系统 Wayland 协议 |
| **按键直接英文上屏，无候选框** | 属于自带私有 Qt 的闭源应用（如微信），模块变量为空时未自动协商 Wayland 输入 | 针对该应用单独设置 `QT_IM_MODULE=text-input-unstable-v3`（微信）或排查对应 IME 启动参数 |
| **Chromium/VSCode 无法打字或弹软键盘** | Chromium 缺失 Wayland IME 命令行特性开关 | 桌面项追加 `--enable-wayland-ime --wayland-text-input-version=3` |
| **KWin 弹出全屏软键盘遮挡** | `kwinrc` 中误将虚拟键盘设为了鼠标触发模式（Mode 2） | 终端执行 `kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardMode 0` 并刷新 KWin |
