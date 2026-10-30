# Window animations

[简体中文](WindowAnimations.zh-CN.md)

In KOS Settings → Windows and animations → Hide and restore, open the dropdown
and choose **None**, **Scale**, or **Genie**. Choices appear in a popup; they are
not separate desktop controls. Closing-window effects have their own dropdown.

Genie uses KWin's official open-source **Magic Lamp** (`magiclamp`). It belongs
to the [KWin repository](https://invent.kde.org/plasma/kwin/-/tree/master/src/plugins/magiclamp),
not a separately downloaded KOS plugin. Standard Plasma/KWin packages normally
include it, but KWin does not enable it by default. KOS enables it when you choose
Genie and publishes Dock icon targets for minimize and restore.

If the native effect is missing, unsupported, or fails to load, KOS automatically
uses its own Scale animation and displays the fallback reason. The selected Genie
preference is retained; the next startup checks again and can recover the native
effect. Old water-drop configurations migrate automatically. None preserves or
restores the previous KDE minimize-effect selection.

You normally need no manual installation or KDE configuration. If fallback occurs:

1. Open KDE System Settings → Desktop Effects. Search **Magic Lamp** (in Chinese,
   **神灯** or **最小化**). Its Chinese name is “最小化过渡动画 (神灯)”. Use the
   effect's configure button to change its duration if desired.
2. If it is absent, use the distribution's software manager to repair/update the
   matching Plasma/KWin packages. Fedora's `kwin`, Arch's `kwin`, Debian/Ubuntu's
   `kwin-wayland`, and NixOS's selected `kdePackages.kwin` are the relevant package
   families; exact packaging depends on distribution/version. Keep the KWin and
   Plasma packages from the same supported distribution release.
3. After package or graphics changes, log out/in and select Genie again. Until
   native support returns, Scale remains the automatic fallback.

Compiling another copy from the upstream repository is unnecessary for a standard
installation and can mismatch the running compositor's ABI. KOS does not disable
KWin permission checks or install system packages from the settings menu.

Pulling a commit changes source files only. Rebuild and install the changed
Settings/platform components with the project's normal installer, then restart
the user services. Updated KWin plugin binaries take effect after logout/login;
do not hot-replace them. See [Getting started](GettingStarted.md).
