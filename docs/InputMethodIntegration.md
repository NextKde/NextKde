# Input Method Integration and Application Compatibility Guide

[简体中文](InputMethodIntegration.zh-CN.md)

NextKde provides a native liquid glass input method popup (including candidate table and language switch indicator) powered by Fcitx5 and the Kimpanel protocol. In a Wayland session, the desktop shell is responsible for rendering the input method UI. Because different GUI toolkits and packaged third-party applications have varying degrees of support for the Wayland text input protocol (`text-input-v3`), this guide explains NextKde's input method architecture, session requirements, and application compatibility workarounds.

---

## 1. Core Architecture and Session Contracts

1. **D-Bus Communication Pipeline**:
   - `kos-platform` (`KimpanelBridge`) registers `org.kde.impanel` only for an enabled, connected frontend. Fcitx selects Kimpanel by availability and suspends Classic UI while the panel is owned.
   - Fcitx5 broadcasts lookup tables, preedit strings, and cursor positions over the `org.kde.kimpanel.inputmethod` D-Bus interface.
   - The unified panel extension publishes input-context content directly. Kimpanel delegates Wayland/XWayland panels to Classic UI on KDE, so the extension bypasses that candidate-update entry point. Selection and paging target the context displayed by the extension.
   - `kos-shell` (`InputMethodPopup.qml`) renders the liquid glass candidate cards featuring physics-based transitions, background blur, and adaptive lighting.

2. **Opt-in takeover and recovery**:
   - The feature defaults to off. Only an enabled, connected Shell frontend acquires Kimpanel. The switch leaves Fcitx addon settings unchanged. Recovery records from older releases are migrated once using the existing Fcitx process; successful restoration removes the record.
   - Switching the frontend never restarts Fcitx or changes KWin’s input-method command. Releasing the panel lease restores native UI through Fcitx’s availability mechanism, preserving the compositor input connection. The Settings page reports the actual active/error state.
   - Toolkit input modules do not all require the same environment. Keep working Qt/XCB, GTK and XIM configurations. NextKde never rewrites global `GTK_IM_MODULE` or `QT_IM_MODULE`; workarounds below apply only to applications that cannot yet connect to input methods.
   - The Shell entrypoint pins `QT_IM_MODULE` and `QT_IM_MODULES` to `wayland` using Quickshell's process-only `Env` pragmas. This keeps launcher search and other Shell text fields on the compositor input path instead of the Fcitx Qt module's client-side candidate panel. The override applies to installed and source/dev launches without changing the environment of launched applications. Restart the Shell after updating these startup pragmas; QML hot reload cannot replace an already-created Qt input context.
   - Kimpanel absolute spots are converted from the configured XWayland root scale to logical screen coordinates. If an anchor is outside all outputs, the panel falls back to the active window's output instead of disappearing.

---

## Extension installation

Normal `kosctl install` provisions Fcitx5 development dependencies and installs
the library under `$KOS_PREFIX/lib/fcitx5` (default `~/.local/lib/fcitx5`). Its
addon description uses an absolute library path and is installed in
`$FCITX_DATA_HOME/addon` or `$XDG_DATA_HOME/fcitx5/addon`. No global input-module
environment, engines, dictionaries or shortcuts are changed. CMake system
installation uses `lib/fcitx5` and `share/fcitx5/addon`; the NixOS module adds
the extension to Fcitx5 addons.

After installing or updating the extension, log out and back in so Fcitx loads
the new library. Subsequent feature switches only acquire or release the panel
lease. Both Kimpanel and native Classic UI must be available; the adapter confirms
this before takeover is reported. Losing the lease restores each input context’s
original panel callback. Legacy addon configuration is restored without
auto-starting Fcitx; a legacy session that started with Classic UI disabled needs
a new login to load it.

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
- **Support Status**: Unified takeover for working Fcitx5 Qt/GTK modules and native Wayland input, without changing module environment variables.
- **Mechanisms & Notes**:
  - GTK 3/4 use Wayland `text-input-v3`. Qt uses the Wayland text-input protocol supported by its runtime and KWin; it should not universally be described as `text-input-v3`.
  - Keep working `GTK_IM_MODULE`, `QT_IM_MODULE` and `XMODIFIERS` settings. The extension uses Fcitx5's custom panel API to override client-side candidate rendering while client preedit still reaches the application.
  - Install NextKde and enable its popup switch once. `kosctl install` builds and deploys the extension automatically. The extension is inactive unless NextKde holds its lease and Kimpanel is available.
  - Activation checks the extension version, process owner and active state. A missing, disabled or unloadable extension triggers rollback with a visible error while preserving the original input configuration.
  - VM acceptance covers Kate with Fcitx/Wayland input, GTK 3 with Fcitx on Wayland/X11, and GTK 4 with Fcitx on Wayland. Applications that do not connect to Fcitx5 still need a working input path first.

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
- **Support Status**: Existing working Fcitx input is supported; applications with no input connection may still require a toolkit-specific module.
- **Root Cause**:
  These applications bundle private or statically compiled Qt runtimes isolated from system Qt libraries. Some do not automatically select a working input module. If a bundled Fcitx Qt module already connects to Fcitx5, keep it: the extension handles its candidates. Only applications with no input connection need the workarounds below.
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
    For legacy applications lacking Wayland text-input support, a compatible Fcitx Qt plugin can connect them to the same Fcitx5 process and unified candidate panel. A missing toolkit plugin still needs to be installed or supplied by the application.

### 4. Legacy XWayland Applications & Games
- **Examples**: Wine / Proton games, legacy X11 utilities, unmigrated Java/AWT programs.
- **Support Status**: **Compatible (via XIM / XWayland bridging)**.
- **Mechanism**: Handled via session-wide `XMODIFIERS=@im=fcitx`.

---

## 3. Quick Troubleshooting Checklist

| Symptom | Probable Cause | Action |
| :--- | :--- | :--- |
| **Classic rectangular popup appears instead of liquid glass** | Takeover inactive or extension not updated | Check Settings; log out and back in after installing the extension |
| **Keystrokes committed directly as English with no candidate box** | Bundled proprietary Qt runtime did not automatically bind Wayland input | Target the app with `QT_IM_MODULE=text-input-unstable-v3` (e.g., WeChat) or relevant toolkit flags |
| **Chromium/VSCode cannot trigger IME or invokes virtual keyboard** | Missing Chromium Wayland IME command-line switches | Append `--enable-wayland-ime --wayland-text-input-version=3` to desktop entry |
| **KWin full-screen virtual keyboard blocks the screen** | `VirtualKeyboardMode` in `kwinrc` set to mouse-triggered mode (Mode 2) | Run `kwriteconfig6 --file kwinrc --group Wayland --key VirtualKeyboardMode 0` and reconfigure KWin |
