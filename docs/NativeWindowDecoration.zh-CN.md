# KOS 原生窗口装饰器按钮

[English](NativeWindowDecoration.md)

Konsole 等使用服务端窗口装饰的应用，由 `kos_decoration` 通过 KDecoration 原生按钮负责绘制和点击。绿色最大化/还原、黄色最小化、红色关闭；不使用 Bridge 浮层，不需要背景取色，也不进入浮层的右键位置调整。

按钮位置和顺序遵循 KDE 窗口装饰设置中的左右按钮布局。标题为两侧按钮预留空间并自动省略；KDE 的可选窗口菜单、置顶、置底等按钮保留原生操作。三色按钮使用左键，绿色不进入全屏。

总开关仍是 kos-settings 的 **KOS 窗口外观**；图标使用同一份 **始终显示/悬停显示** 偏好。旧 `window-buttons.json` 中的浮层位置、尺寸、背景、`showButtons` 或强制绘制规则不再控制原生装饰器按钮；这些规则保留供旧浮层应用使用。

Bridge 根据装饰器的 `_kos_native_decoration_controls` 能力标记退出按钮绘制和输入拦截，并清理旧取色缓存。未升级的装饰器没有该标记，仍可使用旧浮层，避免混合版本升级时丢失唯一的按钮。安装时同时更新 `kos_decoration` 和 `kos_bridge`，下次登录加载；不热替换正在运行的 KWin 插件。

日历、天气、kos-settings 继续使用[协作式按钮](CooperativeWindowControls.zh-CN.md)，无需装饰器；Firefox 使用[浏览器自身按钮](FirefoxWindowButtons.zh-CN.md)；其他未适配的自绘标题栏应用保留浮层回退。

自动验证只在虚拟机进行，见[原生装饰器验收](../tests/native-decoration/README.md)。

Forma/Mayonnaise 应用使用 OpenGL 自绘三色按钮并处理点击。Bridge 对已确认的
Mayonnaise 应用 ID（Calculator、Finder、Music、Photos、Settings、TaskManager、
Terminal、TextEditor、VideoPlayer）和 Forma 应用 ID（AppStore、Mail、PolkitAgent、
Screenshot）的客户端装饰窗口保留这些按钮。识别精确匹配 Wayland 应用 ID 或
X11 的 class 字段，不按标题、可执行文件名或命名空间前缀猜测。旧浮层尺寸或
强制绘制规则不能覆盖该归属；Bridge 会清理旧点击区域、调整会话和取色缓存，
这些窗口不再承担浮层取样开销。服务端装饰窗口继续保留装饰器按钮；窗口显式
协商的协作式按钮仍优先于应用级策略。
