# 第三方 QML 组件开发指南

**状态：原型 SDK（`sdkVersion: 1`）。** 平台服务扫描统一组件目录（`$XDG_DATA_HOME/kos/widgets/<组件 ID>/`）并提供只读包索引。组件采用**进程内运行、安全由使用者自行审计**的信任模型，**不再设硬编码包白名单**：任何通过校验且 `style` 匹配当前桌面风格（`material` / `macos`）的已安装包，都会由宿主动态加载磁盘上的 QML 入口：

- **图库预览（`WidgetPreviewHost.qml`）**：动态加载包内的 `Snapshot.qml` 调用 `getSnapshot(size)`，将样例数据通过 `snapshot` 传给同一包的 `Widget.qml` 直接绘制预览，并注入只读预览桩 `host`（`isPreview: true`，快照为 `null`，反向动作禁用）。
- **桌面落位（`WidgetPackageHost.qml`）**：动态加载包内的 `Widget.qml` 与可选 `Settings.qml`，在 `Component.onCompleted` 之前注入只读 `host` 对象，直调式提供响应式 R1 数据快照（`clock` / `media` / `weather` / `system` / `activity` / `pim`）、按实例持久化的 `settings` / `saveSettings()` / `patchSettings()`、能力探测 `hasAction()` / `apiRevision`、可见性 `active` 以及 R11 反向动作通道 `invokeAction()`——**新增组件包不需要修改 Shell 源码或手写 `*WidgetDataService.qml`**。
- **外观与外罩**：`appearance` 提供 `isDark`、`foreground`、`transparent`、`style` 与完整的 Material 动态色板 `palette`；macOS 组件通过 `backgroundSpec` 声明面板底色，Material 组件的卡片背景色、透明度与合成器模糊均由宿主统一提供，组件可通过 `surfaceShape` 选择内置异形外罩轮廓。

更多架构演进与 Review 记录见[图库预览计划](WidgetGalleryPreviewPlan.zh-CN.md)；若开发支持停靠栏槽位与悬停详细弹框的 Dock 组件，请一并阅读[第三方 Dock 组件开发指南](DockWidgetSDK.zh-CN.md)。

## 1. 建立组件包

一个组件一个目录，目录名与组件 ID 相同。示例包有四个文件：

```text
org.nextkde.example.clock/
├── metadata.json  # ID、版本、尺寸
├── Snapshot.qml   # 预览样例数据
├── Widget.qml     # 预览和正式实例共享的内容视图
└── Settings.qml   # 可选：组件自带的设置界面，见第 6 节
```

包内可以附带其他 QML 和资源，用相对路径引用。复制示例开发自己的组件时，改用自己控制的反向域名 ID，并同步修改目录名和元数据。官方与第三方包约定使用同一个安装根：`$XDG_DATA_HOME/kos/widgets/<组件 ID>/`，未设置 `XDG_DATA_HOME` 时以 `$HOME/.local/share` 为准。只要目录结构与 `metadata.json` 通过平台服务校验（包含合法非符号链接、且不逃逸出包根目录的 `Widget.qml` 和 `Snapshot.qml`），且 `style` 匹配当前桌面风格，图库就会自动发现、预览并允许将其添加到桌面，无需在 Shell 里登记白名单。

**本地开发软链与校验诊断：**
- **允许包根目录使用符号链接**：本地开发时可直接 `ln -s ~/dev/my-widget ~/.local/share/kos/widgets/com.example.mywidget`，平台守护进程会解析规范路径（`canonicalFilePath`）并加载；但包内部文件（`metadata.json`、`Widget.qml`、`Snapshot.qml`、`Settings.qml`）仍禁止为符号链接或指向包根目录之外。
- **校验失败不再静默吞掉**：若目录名、JSON 语法、`style`、`defaultSize`、版本要求或入口文件校验失败，平台守护进程会输出 `qWarning` 日志，并在 `widget-package.snapshot` 响应的 `invalidPackages: [{ id, path, code, reason }]` 中返回错误码（如 `sdk-too-old`、`sdk-too-new`、`api-too-old`、`invalid-metadata`、`missing-entry` 等）与具体拒因（`WidgetPackageService.invalidPackages` 同步暴露并打印控制台告警），方便排查“为什么图库里没出现”。

## 1.1 一个包可以包含多个组件（R8）

同一个组件包可以通过在 `metadata.json` 中声明 `widgets` 数组来导出多个子组件（例如同一个天气包同时提供 macOS 风格与 Material 风格两套入口，或同一主题包包含多个小组件）；**传统的单组件包格式保持 100% 兼容，无需任何改动**。

```text
com.example.weatherpack/
├── metadata.json
├── macos/
│   ├── Widget.qml
│   ├── Snapshot.qml
│   └── Settings.qml     # 可选，同目录下自动识别
└── material/
    ├── Widget.qml
    └── Snapshot.qml
```

`metadata.json` 中使用 `widgets` 时的约定：
- 包顶层填好公共字段（`id`、`version`、`sdkVersion` 以及可选 `minApiRevision`）；
- `widgets` 数组每项是一个子组件描述对象（最多 32 个），可继承顶层的 `name` / `description` / `category` / `i18n` / `style` / `containers` / `dockUnits`；
- 子组件的 `id` 必须等于包 `id` 或以 `<包 id>.` 开头（防止不同包之间命名空间冲突），且不能与其他包重复；
- 子组件通过相对路径 `widgetEntry`、`snapshotEntry`（及可选 `settingsEntry`）指向包内子目录文件，禁止绝对路径、软链或 `..` 逃逸。

## 2. 在 `metadata.json` 声明风格与尺寸

| 字段 | 原型约定 |
| --- | --- |
| `id` | 反向域名 ID（至少 3 段，仅含字母/数字/连字符 `-`），与目录名一致。 |
| `name`、`description` | 给用户看的默认名称和说明。 |
| `i18n` | 可选，多语言翻译表（按语言标签分块覆盖 `name` / `description` / `categoryName`，例如 `{"en": {"name": "Clock"}, "zh-CN": {"name": "时钟"}}`）。查找顺序为完整语言标签 → 基础语言前缀 → 顶层默认字段。 |
| `version` | 组件自身的版本，如 `0.1.0`。 |
| `sdkVersion` | 组件针对的 SDK 主版本，本原型填 `1`。 |
| `minApiRevision` | 可选，组件最低要求的小版本 API 修订号（正整数，缺省为 `1`）。若当前宿主版本低于此值，索引会直接拦截该包（`api-too-old`），避免在老系统上运行时出错。 |
| `style` | **必填，二选一**：`"material"` 或 `"macos"`。组件必须明确声明自己是 Material 组件还是 macOS 组件，不可缺省、不可多选；非法或缺失时守护进程索引会直接拒绝该包。 |
| `sizes` | 非空、无重复的正整数尺寸对（范围 1～4），顺序是 `[列, 行]`。 |
| `defaultSize` | 必填，必须是 `sizes` 中的一对；用于默认添加和默认预览。 |
| `category`、`categoryName` | 可选，用于图库侧边栏分组过滤。宿主统一托管 12 个标准分类及兜底与多语言翻译：`clock`（时钟）、`weather`（天气）、`calendar`（日程与待办）、`media`（音乐与媒体）、`system`（系统监控）、`activity`（活动与健康）、`productivity`（效率与便签）、`news`（资讯与阅读）、`finance`（财务）、`photos`（相册与装饰）、`developer`（开发者）、`utilities`（实用工具），缺省或未知值自动归入 `other`（其他）。常见别名（如 `music` → `media`、`todo` → `calendar`）会自动归一化，`categoryName` 已不再必填。 |
| `containers` | 可选，声明允许放置的容器列表（`["desktop"]`、`["dock"]` 或 `["desktop", "dock"]`，缺省为 `["desktop"]`）。声明包含 `"dock"` 时支持通过 `Popup.qml` 提供悬停详情弹框，详见[Dock 组件开发指南](DockWidgetSDK.zh-CN.md)。 |
| `dockUnits` | 可选，当 `containers` 包含 `"dock"` 时，横向 Dock 展开模式下的槽位宽度（`2`～`4` 个图标单位，缺省 `4`）。 |
| `popupEntry` | 可选，Dock 悬停详细弹框入口相对路径；省略时自动检测与 `Widget.qml` 同目录下的 `Popup.qml`。 |

**为什么 `style` 强制二选一：** Material 与 macOS 桌面组件的材质语言、配色逻辑和面板轮廓本身不同（macOS 走统一超椭圆彩色/液态玻璃外壳，Material 走色调表面并允许组件自绘异形面板）。宿主按当前桌面风格过滤展示与运行：

- **Material 桌面风格**下，图库和桌面仅展示并运行 `"style": "material"` 的组件包；
- **macOS 桌面风格**下，图库和桌面仅展示并运行 `"style": "macos"` 的组件包；
- 切换桌面风格时，另一风格已放置到桌面的实例不会丢失，而是保留在磁盘配置中；切回对应桌面风格后自动恢复。
- **如果开发者希望同时适配两种桌面风格**：可在同一个包内通过 `widgets` 数组分别声明 `"style": "material"` 与 `"style": "macos"` 两份入口（见第 1.1 节），或分别发布两个独立 ID 的包。

时钟声明 `style: "macos"`、`sizes: [[1, 1], [2, 1]]`、默认 `[1, 1]`。只为声明过的档位设计布局，不使用 `small`、`medium` 或 `large`。档位不是像素尺寸：`Widget.qml` 可结合 `widgetSize` 选择布局，再按宿主实际给出的 `width`、`height` 排版。宿主网格上限与屏幕放不下时的处理仍在规划中。

## 3. 写一份视图，接两种数据

`Widget.qml` 的根对象使用 `Item`，声明以下接口：

```qml
Item {
    id: root
    property var snapshot: null        // 可选：图库预览来自 Snapshot.qml；桌面模式含 { status, settings }
    required property var widgetSize   // [列, 行]，拖拽调大小时会实时更新
    required property var appearance   // 主题、前景、透明模式、桌面风格与 Material 动态色板
    property var host: null            // 可选（勿加 required）：直调式只读宿主代理，在 Component.onCompleted 前注入
}
```

> [!WARNING]
> **切勿在根对象 `Item` 上声明 `property var data`！**
> Qt Quick 的 `Item` 自带默认属性 `list<QtObject> data`（用于挂载所有直接子元素）。如果在根 `Item` 上重定义 `property var data`（或 `required property var data`），只要按常规写法在 `Item` 内直接写 `Column { ... }` / `Text { ... }` / `Timer { ... }`，就会触发运行期属性覆盖警告甚至静默丢失子元素，必须改写 `children:` / `resources:`。
> **请统一使用 `property var snapshot: null` 接收预览快照。**（宿主仍对旧版声明了 `required property var data` 的组件保留向后兼容回退，但新组件禁止再使用 `data` 作为属性名。）

- **生命周期保证（`host` 早于 `Component.onCompleted`）**：`WidgetPackageHost` 与 `WidgetPreviewHost` 在实例化 `Widget.qml` 时直接传入 `host`、`snapshot`、`widgetSize` 与 `appearance`，因此组件在 `Component.onCompleted` 内即可直接读取 `host.isPreview`、`host.settings`、`host.clock` 或 `host.apiRevision`，不会拿到 `null`（仅脱离 Shell 的独立预览器中 `host` 保持默认 `null`）。
- **图库预览与独立预览器**：在图库预览中，`WidgetPreviewHost` 会调用 `Snapshot.qml.getSnapshot(size)` 并把返回值传进 `snapshot`，同时传入 `host.isPreview === true`（各数据快照字段为 `null`）；在仓库里的独立预览器（`qml examples/widgets/ClockPreview.qml` 等）中，`host` 保持默认 `null`。因此组件用 `readonly property bool liveMode: Boolean(host && !host.isPreview)` 即可自然区分真实桌面与预览，同一份 `Widget.qml` 既能脱离 Shell 单独预览，也能落到桌面直接绑定实时数据。
- **图库与桌面同壳同视图（仅数据不同）**：图库预览与桌面落位不仅加载同一份 `Widget.qml`，外层卡片也共用同一份 `DeskWidgetCard.qml`（图库侧启用 `preview: true`，按桌面逻辑网格尺寸——2× 缩略图尺寸，例如 2×1 为 `316×152` px——渲染后再等比 `scale: 0.5` 缩放进缩略图框），确保超椭圆圆角、渐变与 Material/玻璃外罩规则完全一致。开发者只需按正常桌面尺寸与像素字号编写一份 `Widget.qml`，无需为图库缩略图单独适配一套外观或迷你字号。
- **热刷新与错误提示**：每次进入编辑模式 / 打开图库都会立即刷新包索引，平台索引会为每个包计算内容修订号 `revision` 并附带在 QML URL 查询参数（`?rev=...`）上绕过 `QQmlEngine` 编译缓存，改完 `Widget.qml` / `Snapshot.qml` / `Settings.qml` 保存后重新打开图库即可看到最新结果。若 QML 存在编译或运行期错误，桌面卡片与图库预览都会直接展示具体错误原因与行列号，不再静默空白。
- **桌面正式实例**：`WidgetPackageHost` 会把同一个只读 `host` 对象注入 `Widget.qml`，组件直接绑定 `host.clock` / `host.media` / `host.weather` / `host.system` / `host.activity` / `host.pim` 与 `host.settings` 即可，不需要再写一份 per-package 的 `*WidgetDataService.qml`。
- **响应式尺寸 `widgetSize`**：`widgetSize` 在组件的生命周期里会变化，不是只在创建时赋值一次。用户把已落位的组件拖拽调整尺寸后，宿主只按 `metadata.json` 的 `sizes` 离散吸附，并用新的 `[列, 行]` 更新同一个 `Widget.qml` 实例的 `widgetSize`，组件应响应式重新布局。

`Snapshot.qml` 的根对象公开同步函数 `getSnapshot(size)`，参数是 `[列, 行]`，返回可 JSON 序列化的普通对象。预览使用固定样例；不读真实时间、用户文件、网络或 Shell IPC，确保图库只靠样例即可稳定绘制。

以数字时钟示例（`examples/widgets/org.nextkde.example.clock/`）为例：预览样例返回 `{ timeText: "09:41", dateText: "2026-11-24" }`；桌面正式运行时 `Widget.qml` 直接读 `host.clock.time24h` / `host.clock.time12h`、`host.clock.isoDate` 和 `host.settings.format24h`。`1×1` 只显示时间，`2×1` 增加日期。

## 4. 组件内容、面板底色、自定义形状、输入与主题

内容可以用 Qt Quick、Canvas、QtQuick.Shapes，也可以自己处理内部点击和键盘输入。整卡拖放、落位、占格、切换尺寸和编辑态输入交给 Shell。组件不要创建自己的桌面窗口。

**交互与右键菜单规则（必读）：**
- 组件内部的 `MouseArea` / `TapHandler` **必须显式限制为 `acceptedButtons: Qt.LeftButton`**，不要拦截 `Qt.RightButton`（或使用 `Qt.AllButtons`）。
- 卡片外壳的右键菜单负责尺寸切换等系统操作；虽然宿主已为卡片右键设置了抢占权限，组件仍不应吞掉右键事件，以免影响编辑态或桌面交互。

### 4.1 组件声明面板底色：`backgroundSpec`（macOS 风格组件）

`"style": "macos"` 的组件可选公开 `readonly property var backgroundSpec`，其值为普通数据对象，由宿主外壳负责绘制、超椭圆圆角裁切与平滑渐变过渡，并随绑定自动更新。当前支持的字段：

| 字段 | 说明 |
| --- | --- |
| `startColor`、`endColor` | 必填，起止颜色（十六进制字符串或 QML 颜色值）。缺省或无效描述不绘制组件背景。**纯色面板**只需将 `startColor` 与 `endColor` 设为同一颜色即可。 |
| `midColor` | 可选，中间色标；缺省时由宿主按起止色线性中值退化为两段渐变。 |
| `midPosition` | 可选，中间色标位置（`0.01`～`0.99`，默认 `0.5`）。 |
| `orientation` | 可选，`"vertical"`（默认）或 `"horizontal"`。 |

**QML 写法示例：**

```qml
// 1. 纯色面板（startColor 与 endColor 相同）
readonly property var backgroundSpec: ({
    startColor: appearance.isDark ? "#1e293b" : "#e2e8f0",
    endColor:   appearance.isDark ? "#1e293b" : "#e2e8f0"
})

// 2. 响应式三段横向渐变（绑定快照，如音乐封面取色）
readonly property var backgroundSpec: ({
    orientation: "horizontal",
    startColor: media?.artworkColors?.ready ? media.artworkColors.primary : "#2b2135",
    midColor:   media?.artworkColors?.ready ? media.artworkColors.secondary : "#1d1826",
    midPosition: 0.45,
    endColor:   "#14101a"
})
```

颜色变化时，桌面卡片外壳（`DeskWidgetCard.qml`）会自动执行 `ColorAnimation` 平滑过渡，组件不需要自己绘制全幅背景或写过渡动画。作者应把需要整卡透明（玻璃模式）时消失的底色放进此接口，不要在内容树或全幅 Canvas 中重复绘制整卡底色；图表、图标和局部色块仍由组件内容绘制。这条链路桌面落位（`DeskCenterWindow.qml` → `DeskWidgetCard.qml`）、图库预览（`WidgetGallery.qml` 复用 `DeskWidgetCard.qml` 的 `preview: true` 模式）与独立预览器（`examples/widgets/MusicPreview.qml`）均已接通。

**各外罩模式下 `backgroundSpec` 的生效规则：**

- **macOS · 彩色卡片（`widgetStyle === "color"`）**：宿主按 `backgroundSpec` 绘制整卡纯色或渐变，并做超椭圆裁切与颜色过渡。
- **macOS · 玻璃卡片（`widgetStyle === "glass"`）**：用户的透明设置优先，宿主隐藏 `backgroundSpec`，保留组件内容，并把 `appearance.transparent` 置为 `true`；外罩液态玻璃由 KWin 合成器统一管理。
- **Material 桌面风格（色调模式）**：宿主不采用 `backgroundSpec`，始终由 `MaterialCardSurface` 统一绘制背景色、透明度与 KWin 合成器模糊区域；组件不可自行绘制外部底板，仅可通过下文 4.2 节声明 `surfaceShape` 选择异形外框轮廓。

### 4.2 Material 宿主统一异形外框：`surfaceShape`

Material 风格下的组件面板外框与 macOS 液态玻璃一样完全由宿主统一提供：背景色严格跟随系统 Material 主题底色、透明度与 KWin 合成器模糊在所有组件之间完全一致。**仅 `"style": "material"` 的组件包**可在 `Widget.qml` 根对象声明外框形状（支持绑定 `widgetSize` 动态切换，建议仅在 `1×1` 使用异形，大卡片保持 `"roundedRect"`）：

```qml
readonly property string surfaceShape: widgetSize[0] === 1 && widgetSize[1] === 1
    ? "slantedOval"
    : "roundedRect"
```

内置支持的 `surfaceShape` 取值：

- `"roundedRect"`：标准圆角矩形（默认，省略或传入未知值时自动回退）。
- `"slantedOval"`：斜椭圆（约 -35° 倾斜药丸，Material 3 Expressive 经典小组件外框）。
- `"flower"`：12 瓣波浪花朵。
- `"cookie"`：8 瓣曲奇锯齿圆。
- `"clover"`：4 叶柔和四叶草。
- `"arch"`：拱门形（上半半圆 + 下方圆角）。
- `"pill"`：全圆角胶囊。
- `"circle"`：正圆。

行为约定：

- **桌面与图库一致**：宿主在桌面（`DeskWidgetCard.qml` → `MaterialCardSurface.qml`）与图库预览（`WidgetGallery.qml` 复用 `MaterialShapeVisual`）使用完全一致的多边形/圆角轮廓、主题底色与透明度，并在桌面端自动生成对应的 KWin 扫描线模糊区域，组件只负责内部前景排版与着色。
- **`"style": "macos"` 组件包**：忽略 `surfaceShape`，保持统一的 macOS 超椭圆彩色/液态玻璃外罩契约。

### 4.3 主题、可读性与 Material 动态色板：`appearance`

宿主通过必需的 `appearance` 属性提供只读上下文（在桌面正式实例和图库预览中结构一致），组件不应直接导入 Shell 私有单例：

| 字段 | 类型与说明 |
| --- | --- |
| `isDark` | `bool`，当前生效的浅色/深色主题。 |
| `foreground` | `color`，宿主建议的前景色。 |
| `transparent` | `bool`，当前实例是否处于透明卡片模式（macOS 玻璃模式为 `true`；Material 色调模式下恒为 `false`）。 |
| `style` | `"material"` \| `"macos"`，当前生效的桌面风格。 |
| `locale` | `string`，当前生效的界面语言标签（如 `"zh-CN"`、`"en"`、`"pt-BR"`），随系统设置实时更新。 |
| `palette` | Material 动态配色对象（随壁纸与深浅色主题实时刷新），包含：`primary`、`onPrimary`、`primaryContainer`、`onPrimaryContainer`、`secondary`、`onSecondary`、`secondaryContainer`、`onSecondaryContainer`、`tertiary`、`tertiaryContainer`、`onTertiaryContainer`、`background`、`surface`、`surfaceContainerLow`、`surfaceContainer`、`surfaceContainerHigh`、`surfaceContainerHighest`、`layer0`～`layer4`、`onSurface`、`onSurfaceVariant`、`outline`、`outlineVariant`、`error`、`scrim`。 |

当 Material 组件声明了 `surfaceShape` 后，外框背景由宿主负责，组件内部的前景文字、图标、徽章与控件应直接从 `appearance.palette`（如 `primary`、`onSurface`、`onSurfaceVariant`）取色；对于斜椭圆、花朵、拱门等异形轮廓，注意预留适当的内边距以免内容贴边。

`appearance.transparent` 为真时，宿主不再为卡片绘制底色，示例时钟与音乐组件会给文字加一层描边（`Text.style: Text.Outline`）以保证在任意壁纸上可读。人工核对方式：`qml examples/widgets/ClockPreview.qml` 的工具栏勾选「透明模式」即可在彩色渐变背景上验证描边效果。

## 5. 人工查看示例与验证

如果本机装有 Qt 6 的 `qml` 工具，在仓库根目录打开独立预览器：`qml examples/widgets/ClockPreview.qml` 或 `qml examples/widgets/MusicPreview.qml`。预览器不启动 Quickshell、不访问 KOS 数据，也不是组件包的一部分。

- 切换尺寸档位，确认布局按档位响应。
- 切换「样例」和「实时」，确认同一份 `Widget.qml` 可分别驱动样例快照与动态数据；在时钟预览器底部切换「24-hour time」，确认仅影响实时模式。

在桌面图库里将已安装到 `~/.local/share/kos/widgets/` 的组件添加到桌面：
- 卡片自动按 `WidgetPackageHost` 实时运行，拖拽调整尺寸后同一张卡在声明档位间重新布局且不丢失运行状态。
- 对包含 `Settings.qml` 的包，桌面编辑态下卡片右上角自动出现齿轮按钮（第 6 节），修改后立即生效并由宿主统一按实例保存在 `$XDG_STATE_HOME/.../deskcenter-widgets.ini`（单实例配置上限 64 KB），重启 Shell 后保持不变，从桌面删除卡片时自动一并清理。

## 6. 组件自己的设置（可选 `Settings.qml`）

组件包可以在包内放一个可选的 `Settings.qml` 声明配置界面。平台服务在索引包时自动检测该文件并发布 `hasSettings: true` 与 `settingsEntry`，**宿主自动为所有含 `Settings.qml` 的已安装包显示齿轮按钮并动态加载**，无需在 Shell 源码里逐包注册。

| 字段/信号 | 约定 |
| --- | --- |
| `property var settings: ({})` | 当前实例已持久化配置的只读快照（全新实例初始为空对象 `{}`）。同样不要在 `Item` 上命名为 `data`（宿主仅对旧版 `required property var data` 保留回退）。**组件作者必须为每个字段提供默认值读取**（如 `root.settings?.format24h !== false`），不要假设首次打开或升级配置结构后字段已存在。 |
| `property var appearance` | 可选，宿主在加载后自动注入与 `Widget.qml` 同结构的 `appearance` 对象。 |
| `signal apply(var next)` | 用户改了配置后触发，参数为完整的新配置对象（可 JSON 序列化，单实例上限 64 KB）。建议先合并原配置（`Object.assign({}, root.settings, { ... })`）以避免覆盖未知字段或未来新增字段；`Widget.qml` 内也可直接调用 `host.patchSettings(partial)` 做增量局部更新。宿主统一写入 `deskcenter-widgets.ini` 后，会实时把新配置推送回同一实例的 `host.settings` 与 `Settings.qml` 的 `settings`，并在卡片被删除时自动清理对应配置。 |

`Settings.qml` 的根对象同样是普通 `Item`（不是 `Popup`、不是 `ApplicationWindow`）：组件不创建自己的浮动窗口或弹层，由宿主决定用什么壳子展示它（当前为锚定在齿轮按钮旁的 `Controls.Popup`）。

示例时钟（`examples/widgets/org.nextkde.example.clock/Settings.qml`）只有一个布尔字段 `format24h`（默认 `true`，用 `root.settings?.format24h !== false` 兜底）：用户切换开关后发出 `apply(Object.assign({}, root.settings, { format24h: checked }))`，`WidgetPackageHost.applySettings()` 落盘并更新 `host.settings`，桌面同一张时钟卡立刻切换 24/12 小时制；同一包放置多份实例时，每份实例独立保存各自配置。

## 7. 直调式只读宿主 `host`（R1 快照 + R11 反向动作）

组件采用**进程内运行、安全由使用者自行审计**的信任模型，不引入跨进程沙箱或运行时细粒度权限门控。为了既免去每加一个包就写一份 `*WidgetDataService.qml` 的样板代码，又避免组件直接耦合 Shell 内部私有单例，宿主在加载 `Widget.qml` 时直接注入只读代理对象 `host`（在 `Widget.qml` 根对象声明 `property var host: null`，不要加 `required` 以兼容独立预览器）。

### 7.1 `host` 对象接口一览

| 属性 / 方法 | 桌面正式实例（`WidgetPackageHost`） | 图库预览（`WidgetPreviewHost`） |
| --- | --- | --- |
| `host.sdkVersion` / `host.apiRevision` | 主版本 `1` / 小版本修订号（当前 `1`） | 同右 |
| `host.locale` | 当前生效的界面语言标签（如 `"zh-CN"`、`"en"`），可响应切换 | 同右 |
| `host.container` / `host.orientation` | 宿主容器类型（`"desktop"` \| `"dock"`）与方向（`"horizontal"` \| `"vertical"`） | `"desktop"` / `"horizontal"` |
| `host.availableSources` | 当前版本支持的数据源列表（如 `["clock", "media", ...]`） | 同右 |
| `host.hasAction(name)` | 探测指定反向动作是否在当前宿主受支持（返回 `bool`） | 同右 |
| `host.isPreview` | `false` | `true` |
| `host.active` / `host.visible` | 桌面可见且未锁屏时为 `true`，锁屏或不可见时为 `false` | `active` 为 `false` / `visible` 随预览可见性 |
| `host.packageId` / `host.instanceId` | 当前包 ID / 实例 ID | 包 ID / `""` |
| `host.clock` / `host.media` / `host.weather` / `host.system` / `host.activity` / `host.pim` | 响应式只读 R1 数据快照对象 | `null`（预览请渲染 `snapshot`） |
| `host.settings` | 当前实例已持久化的 JSON 配置对象（初始 `{}`） | `{}` |
| `host.saveSettings(next)` | 持久化完整配置对象并同步更新 `host.settings`，返回 `bool` | 返回 `false`（无副作用） |
| `host.patchSettings(partial)` | 增量合并 `partial` 到 `host.settings` 并持久化，返回 `bool` | 返回 `false`（无副作用） |
| `host.invokeAction(action, payload)` | 执行 R11 反向动作，同步返回 `{ ok, code, message }` | 返回 `{ ok: false, code: "unavailable", ... }` |
| `host.lastActionResult` | 最近一次动作返回结果 | `null` |

### 7.2 R1：只读数据快照结构

每份快照都是普通可序列化对象，并带显式 `status` 字段（`"ready"` \| `"idle"` \| `"loading"` \| `"unavailable"`）：

- **`host.clock`**：`{ status, timestampMs, isoDate, time24h, time12h, hours, minutes, seconds, weekday }`（每秒更新）。
- **`host.media`**：`{ status, hasPlayer, playing, loading, title, artist, album, artworkUrl, artworkColors: { ready, primary, secondary }, positionSeconds, lengthSeconds, canPrevious, canTogglePlayPause, canNext, canSeek, canRaise, lyric }`。其中 `artworkColors` 由宿主复用 `ArtworkColorSource` 异步提取，可直接绑定到 `backgroundSpec` 驱动封面动态渐变。
- **`host.weather`**：`{ status, available, loading, locationId, locationName, temperature, temperatureText, weatherCode, isDay, conditionSymbol, conditionText, humidity, windSpeed, units, apparentTemperature, sunriseTime, sunsetTime, errorMessage, sourceMessage, daily, forecastDays: [{ date, label, code, symbol, high, low }] }`。
- **`host.system`**：`{ status, cpuUsage, cpuFrequencyMhz, memoryUsedBytes, memoryTotalBytes, diskUsedBytes, diskTotalBytes, temperatureMilliC, temperatureMaxMilliC, cpuHistory, memoryHistory, frequencyHistory }`。
- **`host.activity`**：`{ status, todayKey, todayUptimeSeconds, recentUptimeDays, todayApps: [{ id, name, icon, seconds }] }`。
- **`host.pim`**：`{ status, available, ready, cached, today, errorMessage, todayEvents, pendingTodos }`。

### 7.3 R11：反向动作通道（Widget → Host）

组件可直接调用 `host.invokeAction(action, payload)`，同步拿到 `{ ok, code, message }`；为了兼容独立预览器（如 `MusicPreview.qml`），也可同时保留可选 `signal actionRequested(string action, var payload)` 与 `property var lastActionResult: null`（`WidgetPackageHost` 会自动连接该信号并写回结果）：

```qml
function triggerAction(action, payload) {
    if (host && typeof host.invokeAction === "function")
        return host.invokeAction(action, payload)
    actionRequested(action, payload)
    return null
}
```

当前固定动作枚举：

| `action` | 宿主行为 |
| --- | --- |
| `media.previous` / `media.toggle-play-pause` / `media.next` | 调用当前活跃 MPRIS 播放器的上一首 / 播放暂停 / 下一首。 |
| `media.seek` | 调整当前播放进度（参数 `{ positionSeconds }`，非负秒数）。 |
| `media.raise-player` | 聚焦或呼起当前活跃播放器窗口。 |
| `app.open-weather` | 打开天气应用（可选 `location` 字符串参数）。 |
| `app.open-calendar` | 打开日历应用（可选 `view`: `day`/`week`/`month`/`year`/`todo`/`today`/`reminders` 与 `item` 参数）。 |

返回码枚举：`ok`、`unknown-action`、`unavailable`、`invalid-argument`。

### 7.4 版本演进、运行期能力探测与节电契约

- **向后兼容承诺与淘汰机制（`sdkVersion` / `minApiRevision`）**：在 `sdkVersion: 1` 生命周期内，宿主仅做向后兼容的增量扩展（提升 `host.apiRevision`），不删除或重命名已公开的 `host` 属性、快照字段或动作名称；组件声明未识别的扩展元数据字段时也会保持忽略不报错。未来需要破坏性变更时才会递增 `sdkVersion`，守护进程通过 `[kMinSupportedSdkVersion, kMaxSupportedSdkVersion]` 区间控制兼容窗口并淘汰过旧主版本（`sdk-too-old`）；新插件若依赖新小版本能力，可在 `metadata.json` 声明 `minApiRevision` 防止被装到老系统上运行（`api-too-old`）。
- **能力探测与优雅降级**：调用未来版本才引入的新动作或读取新数据源前，建议用 `host.hasAction("...")`、`host.availableSources.indexOf("...") >= 0` 或 `host.apiRevision` 判断是否支持，并在旧宿主上隐藏或降级对应按钮（例如：`readonly property bool canToggleTodo: Boolean(host?.hasAction?.("pim.toggle-todo"))`）。
- **可见性与节电生命周期**：带有高频 `Timer`、`FrameAnimation` 或连续 `Canvas` 重绘的组件，应将动画/定时器 `running` 绑定到 `Boolean(host ? host.active : true)`（或暂停非必要轮询），确保在锁屏、输出断开或预览非激活态下不消耗后台 CPU/GPU 资源。
- **已知后续扩展方向（尚未实装，请勿假定存在）**：
  - `pim.toggle-todo` 等待办/日程写操作动作；
  - `host.weather` 按实例/城市查询的扩展接口（目前仅暴露系统当前选定城市）。

### 7.5 人工查看音乐示例（R1 + R11）

仓库提供了第二个示例包 `examples/widgets/org.nextkde.example.music/` 及其独立预览器：

```bash
qml examples/widgets/MusicPreview.qml
```

- 切换 `1×1`、`2×1`、`2×2`，确认紧凑方卡、横向条与大卡（含歌词与完整进度条）的布局切换。
- 切换「样例」与「实时」，确认样例模式点击控制按钮不会执行真实动作；在「实时」模式点上一首/下一首，确认背景渐变随每首模拟曲目的 `artworkColors` 平滑过渡。
- 勾选「透明模式」，确认背景隐藏且文字出现描边。

## 8. 发布到插件市场（`NextKde/appCatalog`）

桌面组件插件复用设置中心「应用与服务 → 插件」标签页，以及与桌面应用相同的 GitHub Release + `NextKde/appCatalog` 签名索引流程，但索引文件独立为 **`widgets.json`**（配合 **`widgets.json.sig`**）。

### 8.1 作者仓库 Release 附件格式

作者发布插件的新版本（例如标签 `v1.0.0`）时，需上传组件压缩包（支持 `.tar.gz`、`.tgz`、`.zip`、`.koswidget`，包内根目录或单层子目录直接包含 `metadata.json`、`Widget.qml`、`Snapshot.qml`）以及清单 JSON（例如 `widget-release.json`，如配置了作者签名再附带 `widget-release.json.sig`）：

```json
{
  "schemaVersion": 2,
  "appId": "org.example.ClockWidget",
  "version": "1.0.0",
  "package": {
    "asset": "clock-widget-1.0.0.tar.gz",
    "sha256": "<64 位小写 hex>",
    "size": 12345
  }
}
```

### 8.2 `NextKde/appCatalog` 中的 `widgets.json` 条目格式

将插件的 GitHub 仓库与审核版本登记到目录仓库的 `widgets.json`：

```json
{
  "schemaVersion": 2,
  "sourceId": "nextkde",
  "sequence": 1,
  "issuedAt": "2026-11-26T00:00:00Z",
  "expiresAt": "2027-01-01T00:00:00Z",
  "widgets": [
    {
      "appId": "org.example.ClockWidget",
      "key": "example-clock",
      "format": "qml-widget",
      "repository": "Example/ClockWidget",
      "manifest": "widget-release.json",
      "status": "active",
      "name": { "en": "Clock Widget", "zh-CN": "时钟组件" },
      "description": { "en": "Desktop & Dock clock plugin", "zh-CN": "支持桌面与 Dock 的时钟插件" },
      "release": {
        "version": "1.0.0",
        "tag": "v1.0.0",
        "manifest": "<widget-release.json 的 Base64>"
      }
    }
  ]
}
```

设置中心下载后会在 `$XDG_DATA_HOME/kos/widgets/.staging-*` 中校验 SHA-256、拒绝符号链接与越界路径、调用 `WidgetPackageIndex` 检查 `sdkVersion`/`metadata.json` 合规，再原子部署到 `$XDG_DATA_HOME/kos/widgets/<appId>/`；`WidgetPackageWatcher` 会立即感知目录变化并刷新组件图库与桌面。
