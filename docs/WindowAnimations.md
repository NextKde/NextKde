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

Genie uses the NextKde preset for both minimize and restore, with no tuning required.
If it is temporarily unavailable, Scale is used automatically. Previous native
effect settings and duration are restored when leaving the Genie preset.

Pulling a commit changes source files only. Rebuild and install the changed
Settings/platform components with the project's normal installer, then restart
the user services. Updated KWin plugin binaries take effect after logout/login;
do not hot-replace them. See [Getting started](GettingStarted.md).
