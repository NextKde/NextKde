# Input Method Integration and Application Compatibility Guide

[简体中文](InputMethodIntegration.zh-CN.md)

NextKde provides a native liquid glass input method popup (including candidate table and language switch indicator) powered by Fcitx5 and the Kimpanel protocol. In a Wayland session, the desktop shell is responsible for rendering the input method UI. Because different GUI toolkits and packaged third-party applications have varying degrees of support for the Wayland text input protocol (`text-input-v3`), this guide explains NextKde's input method architecture, session requirements, and application compatibility workarounds.

---

## 1. Core Architecture and Session Contracts

1. **D-Bus Communication Pipeline**:
   - `kos-platform` (`KimpanelBridge`) registers `org.kde.impanel` only for an enabled, connected frontend, enabling `kimpanel` and temporarily disabling `classicui`.
   - Fcitx5 broadcasts lookup tables, preedit strings, and cursor positions over the `org.kde.kimpanel.inputmethod` D-Bus interface.
   - `kos-shell` (`InputMethodPopup.qml`) renders the liquid glass candidate cards featuring physics-based transitions, background blur, and adaptive lighting.

2. **Opt-in takeover and recovery**:
   - The feature defaults to off. Only an enabled, connected Shell frontend acquires Kimpanel. Original Fcitx addon states are checked and saved to `~/.config/kos/inputmethod-recovery.json` before modification; successful restoration removes this record.
   - `ReloadConfig` cannot unload an already loaded Classic UI. Switching the frontend asks KWin to recreate its own Fcitx child and private input-method socket. It does not log out, restart KWin, or run `fcitx5 -r`. The Settings page reports the actual active/error state.
   - Toolkit input modules do not all require the same environment. Keep working Qt/XCB, GTK and XIM configurations. NextKde never rewrites global `GTK_IM_MODULE` or `QT_IM_MODULE`; any application workaround below applies only to that application.
   - The Shell entrypoint pins `QT_IM_MODULE` and `QT_IM_MODULES` to `wayland` using Quickshell's process-only `Env` pragmas. This keeps launcher search and other Shell text fields on the compositor input path instead of the Fcitx Qt module's client-side candidate panel. The override applies to installed and source/dev launches without changing the environment of launched applications. Restart the Shell after updating these startup pragmas; QML hot reload cannot replace an already-created Qt input context.
   - Kimpanel absolute spots are converted from the configured XWayland root scale to logical screen coordinates. If an anchor is outside all outputs, the panel falls back to the active window's output instead of disappearing.

---

## Candidate presentation preferences

Settings → Integration status → Candidate appearance offers font sizes from
12 to 24, independent liquid/frosted materials, engine/horizontal/vertical/adaptive layouts, annotation visibility,
an opaque high-contrast mode, and reduced motion. Adaptive layout switches to
a column when a row no longer fits; long lists scroll and track the selected
candidate. Presentation never reorders candidates or changes their selection
indices.

Candidate material defaults to liquid glass. Frosted mode uses an even blur
without lens refraction and remains blurred when the desktop liquid preset
has zero blur. Switching it does not change the global desktop material.
High contrast takes precedence with an opaque background and restores the
selected material when turned off.

Full motion is enabled by default: popups ease in and out, size changes blend
continuously, the selection plate follows the active candidate, and long lists
scroll smoothly. Typing never replays the entrance, and candidate activation
does not wait for animations. Reduced motion remains an optional accessibility
preference; leave it off for the full animation experience.

These preferences are stored only in
`$XDG_STATE_HOME/quickshell/kos/inputmethod/presentation.json` (normally under
`~/.local/state`). Changing them does not call Fcitx configuration APIs,
restart Fcitx, or change engines, dictionaries or shortcuts. The existing
experimental takeover switch is separate and retains its addon backup and
restore behavior described above.

## 2. Application Compatibility Matrix & Workarounds

### 1. Native Modern Applications (Standard Qt 6 / GTK 3 / GTK 4)
- **Examples**: Dolphin, Kate, Konsole, Firefox, GNOME applications, KDE core utilities.
- **Support Status**: Supported through native Wayland input; forcing a Fcitx toolkit module can bypass the desktop candidate panel.
- **Mechanisms & Notes**:
  - GTK 3/4 use Wayland `text-input-v3`. Qt uses the Wayland text-input protocol supported by its runtime and KWin; it should not universally be described as `text-input-v3`.
  - **GTK**: A global `GTK_IM_MODULE=fcitx` takes priority over native Wayland input and can make the application draw a classic candidate panel. First remove that override for native Wayland applications, for example `env -u GTK_IM_MODULE GDK_BACKEND=wayland remmina`. If GTK settings still force Fcitx, use `GTK_IM_MODULE=wayland` for that application only.
  - **Qt**: A global `QT_IM_MODULE=fcitx` can likewise enable a client-side panel. Modern native Qt applications can be launched with process-local `QT_IM_MODULE=wayland QT_IM_MODULES=wayland`.
  - Applications read their environment at startup. Fully exit old instances before relaunching; session environment file changes normally require a new login. Restarting the Shell does not update running applications. Do not globally force `GTK_IM_MODULE=wayland` on GTK 2 or X11 applications, which still need their Fcitx/XIM path.
  - **Takeover status**: If the native input path is already selected but the classic panel remains, check the actual activation status in Settings. A loaded Classic UI can keep drawing even when `CurrentUI` says `kimpanel`.

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
| **Classic rectangular popup appears instead of liquid glass** | Takeover failed or Classic UI is still loaded | Check the actual status/error in Settings; use the feature switch to reload through KWin |
| **Keystrokes committed directly as English with no candidate box** | Bundled proprietary Qt runtime did not automatically bind Wayland input | Target the app with `QT_IM_MODULE=text-input-unstable-v3` (e.g., WeChat) or relevant toolkit flags |
| **Chromium/VSCode cannot trigger IME or invokes virtual keyboard** | Missing Chromium Wayland IME command-line switches | Append `--enable-wayland-ime --wayland-text-input-version=3` to desktop entry |
| **KWin full-screen virtual keyboard blocks the screen** | `VirtualKeyboardMode` in `kwinrc` set to mouse-triggered mode (Mode 2) | Run `kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardMode 0` and reconfigure KWin |
