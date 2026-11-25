# 第三方 QML 组件开发指南

**状态：原型 SDK（`sdkVersion: 1`）。** 平台服务扫描统一组件目录并提供只读包索引。桌面图库目前对内置数字时钟调用 `Snapshot.qml.getSnapshot(size)`，并将返回数据交给同一包的 `Widget.qml` 直接绘制预览；预览不是静态示意图。桌面落位的最后一段宿主接线也已针对这一个示例包接通：`DeskCenterWindow.qml` 把它映射到真实的 `Widget.qml` 实例（配 `ClockWidgetDataService.qml` 提供的实时时间数据），落到桌面后会持续走字、随拖拽调整尺寸重新布局；组件自己的 `backgroundSpec` 现在也真的驱动了桌面卡片的底色，不再是旧的按组件 ID 写死的静态渐变。`appearance` 已覆盖浅色/深色主题（`isDark`）、尺寸档位（独立的 `widgetSize` 参数，不在 `appearance` 里）、透明卡片模式（`transparent`）三项，示例时钟对三项都有可见反应（换色、换布局、换描边），不是只声明不用。组件自己的设置面板（可选 `Settings.qml`，见第 6 节）也接通了这一个示例：桌面编辑态下卡片齿轮按钮弹出宿主绘制的浮动面板，编辑结果写回同一个正在运行的实例并持久化。这条接线只覆盖这一个包；普通索引到的第三方包仍隐藏，索引本身不代表可信任或允许执行。通用第三方 QML 隔离渲染、安装与多实例管理尚未实现，见[图库预览计划](WidgetGalleryPreviewPlan.zh-CN.md)的 Review 清单。

## 1. 建立组件包

一个组件一个目录，目录名与组件 ID 相同。示例包有四个文件：

```text
org.nextkde.example.clock/
├── metadata.json  # ID、版本、尺寸
├── Snapshot.qml   # 预览样例数据
├── Widget.qml     # 预览和正式实例共享的内容视图
└── Settings.qml   # 可选：组件自带的设置界面，见第 6 节
```

包内可以附带其他 QML 和资源，用相对路径引用。复制示例开发自己的组件时，改用自己控制的反向域名 ID，并同步修改目录名和元数据。官方与第三方包约定使用同一个安装根：`$XDG_DATA_HOME/kos/widgets/<组件 ID>/`，未设置 `XDG_DATA_HOME` 时以 `$HOME/.local/share` 为准。图库目前只渲染随 Shell 源码提供的数字时钟；其他已索引包暂不执行其 QML，也不会显示为已就绪预览。复制包到该目录可验证索引发现，但不会自动授予预览执行权限。

## 1.1 一个包可以包含多个组件（方向已确认，结构待定）

已确认方向：一个组件包可以声明多个组件，不要求“一个包只能有一个组件”。当前原型仍按一个包一个组件实现——`platform/src/daemon/WidgetPackageIndex.cpp` 的 `readPackage()` 把目录直接当成单个组件读取（单个 `id`、单个 `sizes`，固定各一份的 `Widget.qml`/`Snapshot.qml`），多组件的目录结构、元数据格式和索引改动尚未设计。进度见[图库预览计划](WidgetGalleryPreviewPlan.zh-CN.md)的 Review 清单 R8；该项打勾前，复制本示例包仍按“一个包一个组件”处理。

## 2. 在 `metadata.json` 声明尺寸

| 字段 | 原型约定 |
| --- | --- |
| `id` | 反向域名 ID，与目录名一致。 |
| `name`、`description` | 给用户看的名称和说明。 |
| `version` | 组件自身的版本，如 `0.1.0`。 |
| `sdkVersion` | 组件针对的 SDK 版本，本原型填 `1`。 |
| `sizes` | 非空、无重复的正整数尺寸对，顺序是 `[列, 行]`。 |
| `defaultSize` | 必填，必须是 `sizes` 中的一对；用于默认添加和默认预览。 |

时钟声明 `[[2, 2], [3, 2]]`，默认 `[2, 2]`。只为声明过的档位设计布局，不使用 `small`、`medium` 或 `large`。档位不是像素尺寸：`Widget.qml` 可结合 `widgetSize` 选择布局，再按宿主实际给出的 `width`、`height` 排版。宿主网格上限与屏幕放不下时的处理仍在规划中。

## 3. 写一份视图，接两种数据

`Widget.qml` 的根对象使用 `Item`，声明 `required property var data` 和 `required property var widgetSize`。组件作者定义 `data` 的字段；正式数据适配层与快照入口必须给同一个视图提供同结构的数据。数据变化时，用新对象替换整份 `data`，不要只改普通 JS 对象里的字段，否则 QML 绑定可能不会更新。

`widgetSize` 在组件的生命周期里会变化，不是只在创建时赋值一次：用户把已落位的组件拖拽调整尺寸后，宿主用新的 `[列, 行]` 更新同一个 `Widget.qml` 实例的 `widgetSize`，组件必须响应式重新布局，不能假设落位后尺寸不再变化。宿主只会把尺寸 snap 到 `metadata.json` 的 `sizes` 数组里已声明的那几档，不会传入未声明的中间尺寸。这条宿主→组件的实时传递链路已经在示例时钟包上验证：图库预览切换尺寸卡会重绘同一个 `Widget.qml`；桌面落位实例也是同一条路径——调整桌面卡片尺寸后，`DeskCenterConfigService.spanFor(id)` 的新值直接重新绑定到正式运行的 `Widget.qml` 实例。这条接线目前只给这一个示例包做了宿主侧映射，其余已索引包仍无法落位渲染。

`Snapshot.qml` 的根对象公开同步函数 `getSnapshot(size)`，参数是 `[列, 行]`，返回可 JSON 序列化的普通对象。预览使用固定样例；不读真实时间、用户文件、网络或 Shell IPC。不要从视图另开数据通道，否则图库就不能仅靠这份快照绘制。预览与正式运行的权限由未来运行时执行，遵循这份指南本身不构成沙箱。

这个时钟的数据是 `{ timeText, dateText }`，两个字段均为用于显示的字符串。样例固定为 `09:41` 和 `2026-11-24`；正式数据提供端负责读本地时间并在时间变化后更新绑定。`2×2` 只显示时间，`3×2` 增加日期。示例旁的手动预览器临时扮演数据提供端，不代表已有公开的 KOS 时间服务。

## 4. 组件内容、背景与主题

内容可以用 Qt Quick、Canvas，也可以自己处理内部点击和键盘输入。整卡拖放、落位、占格、切换尺寸和编辑态输入交给 Shell。组件不要创建自己的桌面窗口。

组件可选公开 `readonly property var backgroundSpec`，其值为普通数据对象；本原型支持 `startColor` 和 `endColor` 两个颜色字段，宿主负责绘制并随绑定更新。缺省或无效描述不绘制组件背景。作者应把需要整卡透明时消失的底色放进此接口，不要在内容树或全幅 Canvas 中重复绘制整卡底色；图表、图标和局部色块仍由组件内容绘制。这条链路桌面落位和图库预览都已接通：`DeskCenterWindow.qml` 把正式运行实例的 `backgroundSpec` 转交给 `DeskWidgetCard` 的 `startColor`/`endColor`，不再读取旧的按组件 ID 写死的静态渐变。

宿主通过必需的 `appearance` 属性提供只读上下文：`isDark` 表示当前生效的浅色/深色主题，`foreground` 是宿主建议的前景色，`transparent` 表示这个实例当前是否处于透明卡片模式（本 Shell 里即用户把卡片样式切到「玻璃」）。组件可绑定这三个值来适配背景与内容对比度，不应直接依赖 Shell 私有单例。当前示例的背景随 `appearance.isDark` 切换，文字使用 `appearance.foreground`；`appearance.transparent` 为真时，示例时钟给文字加一层描边（`Text.style: Text.Outline`），因为透明模式下宿主不再绘制任何底色，文字需要自己保证在任意壁纸上可读——这是 `backgroundSpec` 抑制之外，组件主动使用 `transparent` 的例子，不是只传不用。

用户选择玻璃卡片时，宿主隐藏组件的 `backgroundSpec`，保留组件内容，并把 `appearance.transparent` 置为真；宿主外罩材质仍由 Shell 管理。该预览原型目前只有彩色卡片与玻璃两种设置，没有独立的透明玻璃选项，因此玻璃模式即透明模式。未来若增加其他透明外观，也应沿用此抑制规则。

人工核对方式：`qml examples/widgets/ClockPreview.qml` 的工具栏有一个「透明模式」勾选框，背后换成一块醒目的渐变背景；勾上后示例卡片本身变透明，文字描边随之出现，确认即便没有任何卡片底色也能看清时间。

## 5. 人工查看时钟原型

如果本机装有 Qt 6 的 `qml` 工具，在仓库根目录打开独立预览器：`qml examples/widgets/ClockPreview.qml`。预览器不启动 Quickshell、不访问 KOS 数据，也不是组件包的一部分。

- 切换 `2×2` 和 `3×2`，确认宽档多一行日期，窄档只显示时间。
- 在两个档位分别切换「样例」和「实时」，确认样例保持 `09:41`，实时与本机时钟一致并随分钟更新。两个模式使用同一个 `Widget.qml`。
- 底部工具栏的开关来自同一个包的 `Settings.qml`（见第 6 节）：切换「24-hour time」，确认「实时」模式的时间立刻在 24 小时制和 12 小时制 AM/PM 之间切换，「样例」模式保持 `09:41` 不受影响。

在图库里把这个示例时钟加到桌面：卡片应显示实时时间并随分钟更新，拖拽调整尺寸后同一张卡在 2×2/3×2 间重新布局且不丢失运行状态。桌面编辑态下卡片右上角会出现一个齿轮按钮（第 6 节），点开后同一张卡的时间显示格式会随之切换，且刷新、重新落位或调整尺寸后设置保持不变（持久化在 `example-clock-widget.ini`，不是临时态）。切换外罩（玻璃/彩色/Material）、安装、多实例管理和生成图库缓存仍需等通用第三方 QML 宿主接线后再人工验收。

## 6. 组件自己的设置（可选 `Settings.qml`）

组件包可以在包内再放一个 `Settings.qml`，用来声明自己的配置界面。宿主只在包含这个文件、且宿主为该组件接通了设置入口时，才在卡片上显示齿轮按钮；没有这个文件的组件没有齿轮按钮。这条和 `Widget.qml`/`Snapshot.qml` 一样是按包手动接线的原型约定，不是自动发现——目前只有示例时钟这一个包接通。

| 字段/信号 | 约定 |
| --- | --- |
| `required property var data` | 当前配置的只读快照，字段由组件作者自己定义，和 `Widget.qml` 的 `data`是两套独立的数据，互不混用。 |
| `signal apply(var next)` | 用户在设置界面里改了配置后触发，参数是完整的新配置对象（不是增量 diff）。宿主负责校验、持久化，并把新值反映回同一个正式运行实例的 `data`。 |

`Settings.qml` 的根对象同样是普通 `Item`（不是 `Popup`、不是 `ApplicationWindow`）：组件不创建自己的浮动窗口或弹层，由宿主决定用什么壳子展示它——当前原型用的是一个 `Controls.Popup`，锚定在卡片的齿轮按钮旁边。组件只管内容和交互，和整卡的玻璃/Material 外罩规则（第 4 节）是同一个分工原则。

示例时钟的设置只有一个布尔字段 `format24h`（24 小时制开关），由 `ClockWidgetDataService.qml` 持久化：宿主把同一个正在运行实例的当前值通过 `data` 传给 `Settings.qml`，`Settings.qml` 触发 `apply` 后，宿主调用该实例的 `setFormat24h()`，新值立即体现在桌面上同一张卡的时间文字上——不是弹窗自己改了本地变量又被下一次刷新覆盖掉。这条「设置改了会影响这同一个实例、而不是另开一份」的约定，验证方式见第 5 节的桌面落位检查和 `examples/widgets/ClockPreview.qml` 的底部开关。
