# GTK 原生三色窗口按钮

GTK 与 Qt 共用设置中的 **KOS window appearance（KOS 窗口外观）** 总开关，
以及 **Window button icons（窗口按钮图标）** 的“始终显示 / 悬停显示”选项。
无需单独安装或启用 GTK 样式。

- 开启窗口外观：同步 GTK 3/4 原生三色按钮样式，按钮默认位于右侧。已有的右侧布局、菜单位置和按钮顺序保持原样。
- 关闭窗口外观：恢复原 GTK 样式和布局，保留已记录的应用适配规则，重新开启时继续使用。
- 修改图标模式：GTK 原生按钮与 Qt/KWin 按钮采用相同配置。悬停模式只隐藏符号，保留三色圆点。
- 安装、升级执行窗口默认配置时同步 GTK；保留已经关闭总开关或改用其他装饰的用户选择。

绿色按钮使用 GTK 自带的最大化/还原，不进入全屏。GTK 应用需重启后读取更新的样式；
重新登录会同时应用原有 Qt 装饰切换与 GTK 样式。仅窗口控制按钮被修改，工具栏保持原主题。

适配规则与开关分工不同：规则决定哪些窗口已有可用原生控件，总开关决定是否启用 NextKde 外观。
已适配的标准 GTK CSD 窗口停止浮层绘制和鼠标拦截；未适配应用、对话框仍保留浮层。
使用 KWin 服务端装饰的窗口仍保留 KOS 控件，避免丢失唯一的窗口按钮。
不会仅凭“使用 GTK”就关闭浮层，自绘标题栏、libadwaita 变体和 Flatpak 仍需单独确认兼容性。

`WindowSettings` 使用内置资源同步 GTK，不依赖源码目录。用户原有 CSS、其他 GTK 设置及
GSettings 布局会备份并在关闭时恢复；升级会从原始备份恢复先前被强制移到左侧的右侧布局，
没有可用右侧配置时采用 `:minimize,maximize,close`。Chrome/Chromium 继续使用右侧覆盖式按钮，
不因这项布局修正禁用浮层。用户后续更改的无关配置会保留。不能写入配置时向设置页
报告错误，不把失败当作启用成功。受声明式管理的符号链接不会被覆盖。

兼容性维护工具仍可用于添加或移除精确 app ID / WM_CLASS 规则：

```sh
./tools/kosctl gtk-buttons adapt org.example.Application
./tools/kosctl gtk-buttons fallback org.example.Application
```

这不是另一套用户开关。安装/卸载低层样式命令仅供开发验证，不作为日常启用步骤。
所有项目安装、运行和验证只在虚拟机执行。测试入口与边界见[英文说明](GtkWindowButtons.md#vm-acceptance)。

Firefox 的标题栏需要单独的[原生适配](FirefoxWindowButtons.zh-CN.md)，登记后共用上述开关。
