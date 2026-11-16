# Firefox 原生三色窗口按钮

[English](FirefoxWindowButtons.md)

Firefox 在 Linux 使用 GTK 平台集成，但浏览器标题栏按钮由 Firefox 自己绘制，不能仅靠标准 GTK 按钮 CSS 适配。本集成修改原生按钮的样式，保留原生关闭、最小化、最大化/还原操作。绿色按钮不进入全屏；不添加覆盖按钮或背景面板。

## 使用

在 Firefox 使用的桌面用户下执行一次配置登记：

```sh
./tools/kosctl firefox-buttons install
# 非默认配置目录可明确指定（可以重复传入）：
./tools/kosctl firefox-buttons install --profile /absolute/path/to/profile
```

默认读取 `~/.mozilla/firefox/profiles.ini` 和 `$XDG_CONFIG_HOME/mozilla/firefox/profiles.ini` 中存在的配置目录。登记后共用 kos-settings 的 **KOS 窗口外观** 与 **窗口按钮图标（始终/悬停）**，没有第二个外观开关。设置程序内置同步资源，不依赖源码目录。关闭总开关会移除三色样式，恢复 Firefox 原有按钮；继续禁止该浏览器窗口的旧浮层，避免两套按钮。

**重启 Firefox** 读取样式；安装新的 KWin 插件后**注销并重新登录**。登记工具只写配置，不重启浏览器、不重载桌面。按钮顺序和可见性沿用 Firefox/GTK/已有主题布局。

安装器在 `chrome/userChrome.css`、`user.js` 添加有标记的配置块，备份记录在 `$XDG_CONFIG_HOME/kos/firefox-buttons-state.json`；原有主题导入和其他配置保留。Firefox-GNOME 主题管理的 `user.js` 符号链接若已启用 `toolkit.legacyUserProfileCustomizations.stylesheets`，保持原样。其他需要改写的符号链接会拒绝处理，不覆盖主题所有者的文件。

先退出 Firefox，再撤销登记：

```sh
./tools/kosctl firefox-buttons uninstall
```

卸载移除管理块、恢复所管理的加载偏好并删除本集成的 KWin 适配规则。未变化的文件恢复安装前内容；其他用户追加内容保留。

## 范围与验证

当前规则精确匹配 `firefox` 普通窗口，服务端装饰窗口不受原生 CSD 排除规则影响。其他浏览器、对话框及未登记应用继续走原有路径。Snap/Flatpak 的配置发现、沙箱路径和自定义 app ID 不自动适配；不要手工为未经确认的窗口关闭浮层。

自动验证只在虚拟机执行，入口见 [测试说明](../tests/firefox-buttons/README.md)。覆盖 Firefox 自带浅/深主题、Firefox-GNOME 主题、共用开关与图标模式、原生按钮操作，以及移除/恢复适配规则的浮层对照测试。版本不同仍需本机用户手动确认；不把 VM 结果当作本机运行验证。
