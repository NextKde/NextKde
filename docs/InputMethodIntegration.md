# Input Method Integration and Application Compatibility Guide

[简体中文](InputMethodIntegration.zh-CN.md)

NextKde provides a native liquid glass input method popup (including candidate table and language switch indicator) powered by Fcitx5 and the Kimpanel protocol. In a Wayland session, the desktop shell is responsible for rendering the input method UI. Because different GUI toolkits and packaged third-party applications have varying degrees of support for the Wayland text input protocol (`text-input-v3`), this guide explains NextKde's input method architecture, session requirements, and application compatibility workarounds.

---

## 1. Core Architecture and Session Contracts

1. **D-Bus Communication Pipeline**:
   - `kos-platform` (`KimpanelBridge`) registers the `org.kde.impanel` service on initialization, notifying Fcitx5 to enable its built-in `kimpanel` addon and disable `classicui`.
   - Fcitx5 broadcasts lookup tables, preedit strings, and cursor positions over the `org.kde.kimpanel.inputmethod` D-Bus interface.
   - `kos-shell` (`InputMethodPopup.qml`) renders the liquid glass candidate cards featuring physics-based transitions, background blur, and adaptive lighting.

2. **Session Environment Standards (Avoid Global IM Modules)**:
   - **Key Contract**: In Wayland sessions, `GTK_IM_MODULE` and `QT_IM_MODULE` should remain **empty** in the system environment; only `XMODIFIERS=@im=fcitx` is retained for XWayland/X11 compatibility.
   - **Reason**: Setting `QT_IM_MODULE=fcitx` or `GTK_IM_MODULE=fcitx` forces applications to load client-side toolkit plugins that declare `CapabilityFlag::ClientSideInputPanel`. When this capability flag is active, Fcitx5 stops broadcasting candidate events to Kimpanel and delegates candidate rendering to the application window, falling back to a legacy rectangular popup and bypassing NextKde's liquid glass interface.
   - **Zero Global Session Pollution**: NextKde does not mutate user systemd or D-Bus environment variables at runtime, preserving user system defaults. The feature is experimental and disabled by default; users can enable "Enable NextKde Input Method Popups (Experimental)" in the Settings app under System Services & Integration. When disabled or upon Shell termination, NextKde automatically releases the Kimpanel takeover and cleanly restores the original Fcitx5 addon state.

---

## 2. Application Compatibility Matrix & Workarounds

### 1. Native Modern Applications (Standard Qt 6 / GTK 3 / GTK 4)
- **Examples**: Dolphin, Kate, Konsole, Firefox, GNOME applications, KDE core utilities.
- **Support Status**: **Native out-of-the-box support**.
- **Mechanisms & Notes**:
  - When module environment variables are empty, these applications automatically negotiate Wayland `text-input-v3` with the compositor.
  - **Troubleshooting**: If a classic white/grey rectangular candidate box appears instead of the liquid glass popup, the process likely inherited stale `GTK_IM_MODULE=fcitx` or `QT_IM_MODULE=fcitx` exports. Check `~/.bashrc`, `~/.xprofile`, or `~/.config/environment.d/`, remove the overrides, and restart the application.

### 2. Chromium and Electron Applications
- **Examples**: Google Chrome, Chromium, VS Code, Obsidian, Discord, Slack, Linux QQ.
- **Support Status**: **Fully supported (Wayland IME flags required)**.
- **Startup Flags**:
  The Chromium engine under native Wayland requires explicit command-line flags to communicate with compositor text-input interfaces.
  If input focus fails or triggers the full-screen virtual keyboard unexpectedly, add the following flags to the application launcher:
  ```bash
  --ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=3
  ```
  *(Or `--ozone-platform-hint=auto --enable-wayland-ime`)*

### 3. Bundled and Proprietary Qt Applications (Monolithic Packages / RPM / Isolated Runtimes)
- **Examples**: Official WeChat Linux (RPM/DEB 4.x+), Calibre (standalone), WPS Office, Baidu Netdisk.
- **Support Status**: **Targeted environment overrides required**.
- **Root Cause**:
  These applications bundle private or statically compiled Qt runtimes isolated from system Qt libraries. When `QT_IM_MODULE` is empty, their internal Qt runtimes often fail to default to Wayland text input, causing Chinese input methods to be completely unreachable. Setting `QT_IM_MODULE=fcitx` restores input but activates `ClientSideInputPanel`, reverting to classic square popups.
- **Workarounds**:
  - **Official WeChat (WeChat Linux 4.x+)**:
    WeChat embeds `WaylandTextInputV3ContextPlugin` registered under the explicit factory key `text-input-unstable-v3`. Injecting this key provides native Chinese input while retaining NextKde's liquid glass popup:
    ```bash
    # WeChat dedicated wrapper
    export QT_IM_MODULE=text-input-unstable-v3
    export GTK_IM_MODULE=
    export XMODIFIERS="@im=fcitx"
    exec /opt/wechat/wechat "$@"
    ```
  - **Calibre Standalone**:
    Calibre's standalone bundle omits `fcitx5-qt` but includes its own IBus Qt plugin. Route through Fcitx5's IBus compatibility frontend:
    ```bash
    export QT_IM_MODULE=ibus
    exec /opt/calibre/calibre "$@"
    ```
  - **Other Legacy Bundled Qt Applications**:
    For legacy applications lacking Wayland text-input support entirely, export `QT_IM_MODULE=fcitx` specifically for that application as a fallback to guarantee basic typing capabilities.

### 4. Legacy XWayland Applications & Games
- **Examples**: Wine / Proton games, legacy X11 utilities, unmigrated Java/AWT programs.
- **Support Status**: **Compatible (via XIM / XWayland bridging)**.
- **Mechanism**: Handled via session-wide `XMODIFIERS=@im=fcitx`.

---

## 3. Quick Troubleshooting Checklist

| Symptom | Probable Cause | Action |
| :--- | :--- | :--- |
| **Classic rectangular popup appears instead of liquid glass** | Application received `QT_IM_MODULE=fcitx` or `GTK_IM_MODULE=fcitx`, enabling `ClientSideInputPanel` | Unset `QT_IM_MODULE` and `GTK_IM_MODULE` for the application to restore native Wayland routing |
| **Keystrokes committed directly as English with no candidate box** | Bundled proprietary Qt runtime did not automatically bind Wayland input | Target the app with `QT_IM_MODULE=text-input-unstable-v3` (e.g., WeChat) or relevant toolkit flags |
| **Chromium/VSCode cannot trigger IME or invokes virtual keyboard** | Missing Chromium Wayland IME command-line switches | Append `--enable-wayland-ime --wayland-text-input-version=3` to desktop entry |
| **KWin full-screen virtual keyboard blocks the screen** | `VirtualKeyboardMode` in `kwinrc` set to mouse-triggered mode (Mode 2) | Run `kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardMode 0` and reconfigure KWin |
