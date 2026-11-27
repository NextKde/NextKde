# 第三方 Dock 组件开发指南

**状态：原型 SDK（`sdkVersion: 1`）。** Dock 组件与桌面组件共用同一个扫描目录（`$XDG_DATA_HOME/kos/widgets/<组件 ID>/`）、同一套信任模型与同一套 `host` / `appearance` / `Snapshot.qml` 契约，只是容器形态为 Dock 信息槽（并支持可选的悬停详细弹框 `Popup.qml`）。

与桌面组件的通用部分（多语言 `i18n`、R1 数据快照、R11 反向动作、可选 `Settings.qml` 配置及发布到 `NextKde/appCatalog`）见[桌面组件开发指南](WidgetSDK.zh-CN.md)。

---

## 1. 组件包目录结构

与桌面组件完全一致：**一个组件一个目录**，目录名与 `metadata.json` 中的 `id` 相同：

```text
com.example.mydockwidget/
├── metadata.json   # ID、版本、style、containers、dockUnits 等元数据
├── Widget.qml      # Dock 槽位内展示的紧凑卡片视图
├── Snapshot.qml    # 图库预览样例数据（同时供 Widget.qml 与 Popup.qml 预览使用）
├── Popup.qml       # 可选：鼠标悬停时弹出的详细面板内容（自动识别）
└── Settings.qml    # 可选：组件设置界面（与桌面组件共用的配置机制）
```

### 多组件包（R8）与双风格共存
与桌面组件一致，同一个包内可以通过 `metadata.json` 的 `widgets` 数组同时导出：
- 同时适配桌面和 Dock 的两套入口（如桌面入口 `"containers": ["desktop"]`，Dock 入口 `"containers": ["dock"]`）；
- 或者同时提供 `"style": "macos"` 与 `"style": "material"` 两套子入口。

包内文件同样受路径安全校验：入口文件不可为符号链接，也不可通过 `..` 逃逸出包根目录（包根目录本身允许软链开发）。

---

## 2. `metadata.json` 中的 Dock 字段

除通用字段（`id`、`name`、`description`、`i18n`、`version`、`sdkVersion`、`minApiRevision`、`style`）外，Dock 组件重点关注以下字段：

| 字段 | 约定 |
| --- | --- |
| `containers` | 声明支持的容器列表，支持 `["dock"]` 或 `["desktop", "dock"]`（缺省为 `["desktop"]`）。 |
| `dockUnits` | 可选，横向 Dock 展开模式下的槽位宽度单位（整数 `2`～`4`，缺省 `4`，相当于 `dockUnits × iconSize`）。折叠轮播模式下宽度由宿主统一控制。 |
| `sizes` / `defaultSize` | 若同时包含 `"desktop"` 则必填；若**仅声明 `"containers": ["dock"]`**，可省略，索引会自动补全为 `[[dockUnits, 1]]`。 |
| `style` | **必填二选一**：`"material"` 或 `"macos"`，与当前系统桌面风格匹配时才会在 Dock 与图库「Dock 组件」分类中出现。 |
| `dockCardId` | 可选（写在 `widgets` 数组的子项里），Dock 卡片在排序列表中的稳定标识，缺省为子组件 `id`。同一张卡片同时提供 macOS 与 Material 两个入口时，两个子项应使用相同的 `dockCardId`，这样切换桌面风格后卡片在 Dock 中的位置与开关状态保持不变。 |
| `popupEntry` | 可选相对路径；省略时，平台索引会自动检测与 `Widget.qml` 同级目录下的 `Popup.qml` 并暴露 `hasPopup: true`。 |

**极简纯 Dock 组件 `metadata.json` 示例：**

```json
{
  "id": "com.example.netrate",
  "name": "Network Rate",
  "i18n": {
    "zh-CN": { "name": "网速监控", "description": "Dock 实时速率与连接详情" }
  },
  "version": "0.1.0",
  "sdkVersion": 1,
  "style": "macos",
  "containers": ["dock"],
  "dockUnits": 3,
  "category": "system"
}
```

---

## 3. Dock 槽位视图：`Widget.qml`

Dock 槽位内的 `Widget.qml` 与桌面组件的根属性接口完全相同：

```qml
Item {
    id: root
    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null
}
```

### 3.1 横向 Dock 与侧边 Dock 自适应
Dock 支持底部横向与左/右侧边竖向停靠，组件通过 `host` 区分布局：
- `host?.container === "dock"`：确认当前处于 Dock 中（或图库中的 Dock 预览）。
- `host?.orientation === "horizontal"`（底部 Dock）：组件可用空间为宽矩形（`widgetSize` 为 `[dockUnits, 1]`，即高度约 `iconSize × 1.2 - 8`，宽度约 `iconSize × dockUnits`）。
- `host?.orientation === "vertical"`（左/右侧边 Dock）：宿主会反旋转内部面板保持文字正立，尺寸偏向紧凑小块（`widgetSize` 为 `[1, 2]`），适合精简为“核心数值 + 标签”双行结构。

### 3.2 外壳与交互规范
- **槽位外罩与同心圆角由宿主统一管理**：
  - 宿主会根据外 Dock 的实时圆角与端头留白自动计算同心内圆角 `cardRadius`，并按弦长几何自动为内部 `WidgetPackageHost` 预留防圆角裁剪的安全边距；第三方 `Widget.qml` 直接铺满自身根 `Item` 排版即可，无需为了避开外层圆角而手动多加超宽左右边距。
  - macOS 风格下，宿主提供统一圆角/透明底板；`Widget.qml` 可按需声明 `backgroundSpec` 提供渐变底色（透明模式下自动隐藏）。
  - Material 风格下，槽位底色与透明度始终跟随系统 Material 主题，不采纳 `backgroundSpec`。
- **禁止吞掉右键事件**：与桌面组件一致，槽位内的 `MouseArea` 必须显式指定 `acceptedButtons: Qt.LeftButton`（图库右键快捷键与 Dock 编辑手势由宿主接管）。
- **按需隐藏卡片：`dockVisible`**：`Widget.qml` 可选声明 `readonly property bool dockVisible`，为 `false` 时宿主会把该卡片从 Dock 轮播/展开布局中摘掉，恢复为 `true` 后自动回到原位置（适合仅在特定条件下展示的第三方组件；官方内置卡片默认始终展示，省略该属性即等同于始终可见）。
- **切勿在根 `Item` 上定义 `property var data`**，请始终使用 `property var snapshot: null`。

---

## 4. 图库预览：`Snapshot.qml`

在设置/桌面编辑态的「Dock 组件」分类中，图库不再显示静态占位图标，而是采用与桌面组件完全一致的预览机制：
1. 宿主加载包内的 `Snapshot.qml` 并调用 `getSnapshot(size)`：
   - 渲染 Dock 槽位条形预览时传入 `[dockUnits, 1]`；
   - 点击卡片上的「详情弹框（Popup）」按钮预览悬停弹框时，同样调用 `getSnapshot([dockUnits, 1])` 注入 `Popup.qml`。
2. 宿主向 `Widget.qml` / `Popup.qml` 注入只读预览桩 `host`（`host.isPreview === true`、`host.container === "dock"`、`host.invokeAction(...)` 无副作用）。
3. 组件只需沿用 `readonly property bool liveMode: Boolean(host && !host.isPreview)`，即可用同一套代码同时支持图库真实预览与 Dock 实时运行。

---

## 5. Hover 详情弹框契约：`Popup.qml`（核心约定）

只要包内提供 `Popup.qml`（或在 `metadata.json` 中显式指定 `popupEntry`），用户将鼠标悬停在该 Dock 组件上约 `220ms` 后，宿主会自动在对应槽位旁打开详情弹框；鼠标移入弹框内部时保持开启，离开约 `260ms` 后自动收起。

### 5.1 职责边界：宿主掌控外壳，组件只定义内容与高度
为了保证所有 Dock 弹框宽度整齐、质感（液态玻璃/Material 材质、KWin 模糊、圆角、入场动画、边缘锚定与防遮挡）完全一致：
- **宿主（`DockWidgetPopup.qml`）统一负责**：
  - 弹框窗口、`LiquidGlassPanel` 外壳、圆角、阴影、KWin `blurRegion`；
  - 底部 Dock 向上弹出、左/右侧边 Dock 向屏幕内侧弹出；
  - 悬停打开/关闭延时与鼠标跨缝保活；
  - **固定统一宽度 `300px`**，并将高度安全钳制在 **`72px ~ 480px`**（内容超过 `480px` 时由宿主自动提供纵向滚动）。
- **第三方 `Popup.qml` 只需关注内容与高度**：
  - 根对象必须是普通 `Item`（**严禁**自建 `Window`、`PopupWindow` 或 `Popup`）；
  - 通过 `implicitHeight`（或优先的 `readonly property real popupHeight`）声明所需高度，内部排版以 `width`（即宿主注入的 `300px`）自适应即可。

### 5.2 `Popup.qml` 可用属性与能力
`Popup.qml` 由与 `Widget.qml` 完全相同的宿主包装器加载，可直接使用：
- `property var snapshot: null`：图库预览弹出框时来自 `Snapshot.qml`。
- `required property var appearance`：`isDark`、`foreground`、`transparent`、`style`、`locale`、`palette`。
- `property var host: null`：
  - R1 数据快照（`host.clock` / `host.media` / `host.weather` / `host.system` / `host.activity` / `host.pim`）；
  - `host.active`：弹框真正可见时为 `true`，收起时为 `false`（建议把弹框内的动画/定时器绑定到 `host?.active` 省电）；
  - `host.settings` & `host.patchSettings(partial)`：与同一包的 Dock `Widget.qml` 共享实例键 `"dock:<组件 ID>"`，在弹框里调整设置会实时持久化并同步到 Dock 槽位视图；
  - `host.invokeAction(action, payload)`：可在弹框内放置按钮，直接触发播放控制或打开对应应用。

### 5.3 极简 `Popup.qml` 示例

```qml
import QtQuick

Item {
    id: root

    property var snapshot: null
    required property var widgetSize
    required property var appearance
    property var host: null

    readonly property bool liveMode: Boolean(host && !host.isPreview)
    readonly property var sysData: liveMode ? (host.system ?? snapshot) : snapshot
    readonly property color ink: appearance?.palette?.onSurface ?? appearance?.foreground ?? "#ffffff"

    // 宿主固定 width = 300，组件仅需通过 implicitHeight 声明高度（72~480px）
    implicitHeight: contentCol.implicitHeight + 28

    Column {
        id: contentCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8

        Text {
            width: parent.width
            text: "资源详情"
            color: root.ink
            font { pixelSize: 14; weight: Font.DemiBold }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.ink
            opacity: 0.14
        }

        Text {
            width: parent.width
            text: "CPU: " + Math.round(Number(root.sysData?.cpuUsage ?? 0) * 100) + "%"
            color: root.ink
            opacity: 0.85
            font.pixelSize: 12
        }
    }
}
```

---

## 6. 官方 Dock 组件即标准包

Dock 里的音乐、天气、时钟、系统四张卡片不再是 Shell 里写死的内置页面，而是随 Shell 发布的四个官方包（`widgets/org.nextkde.dock.music`、`.weather`、`.clock`、`.system`），与第三方组件使用完全相同的目录结构与接口，可直接作为开发参考：

- 每个包用 `widgets` 数组导出 `macos` 与 `material` 两个子项，共用同一份 `Widget.qml` / `Popup.qml` / `Snapshot.qml`，并通过相同的 `dockCardId` 保持排序位置；
- `Widget.qml` 通过 `appearance.style` 区分前景色（macOS 在渐变底色上用白色文字，Material 用 `appearance.palette.onSurface`），macOS 渐变底色通过 `backgroundSpec` 提供；
- 悬停详情由各包自己的 `Popup.qml` 提供，宿主统一绘制外壳；
- 旧版本保存的 Dock 排序里的 `music` / `weather` / `clock` / `metrics`（及更早的 `temperature`）会在读取配置时自动迁移为对应的官方包 ID。

宿主为这些卡片扩充了只读快照字段：`host.weather` 增加 `apparentTemperature`、`sunriseTime`、`sunsetTime`；`host.system` 增加 `temperatureMaxMilliC`（最近 5 分钟最高温度）。
