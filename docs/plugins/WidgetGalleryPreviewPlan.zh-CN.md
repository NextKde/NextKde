# 桌面组件图库预览计划

状态：进程内动态加载（R2）、只读宿主数据快照（R1：`clock`/`media`/`weather`/`system`/`activity`/`pim`）、反向动作通道（R11）、桌面/Dock 容器契约（R3）、单包多组件（R8）、插件市场分发与安装一致性（R5）、图库预览图片缓存与按需节流渲染（R6）、Material 动态色板 `appearance.palette`、宿主统一异形外框 `surfaceShape` 与通用按实例 `Settings.qml` 均已落地，详见[第三方组件开发指南](WidgetSDK.zh-CN.md)与两个示例包（[时钟](../../examples/widgets/org.nextkde.example.clock/)、[音乐](../../examples/widgets/org.nextkde.example.music/)）。剩余待定项为旧实例迁移（R7）。

## Shell、面板与组件包的职责

- **Shell** 提供组件发现、索引、加载和实例生命周期管理，以及桌面、Dock 和面板的容器能力。宿主负责组件的添加、落位、移动、尺寸切换和输入分发。
- **面板** 由 Shell 提供，负责容器布局、背景材质和外壳样式。液态玻璃（macOS）和 Material Design 属于两套材质与形状语言不同的风格，组件包必须在 `metadata.json` 中二选一声明 `"style": "material"` 或 `"style": "macos"`；图库与桌面仅展示并运行匹配当前桌面风格的组件包，另一风格的已放置实例保留在磁盘配置中，切回对应风格后自动恢复。
- **组件包** 提供天气、时钟等具体功能，负责内容绘制和内部交互。官方组件以独立的包交付，和第三方组件使用同一套目录、索引和入口约定。macOS 风格组件由宿主统一绘制超椭圆彩色/玻璃外罩；Material 风格组件的底色、透明度与合成器模糊均由宿主统一提供，组件可通过 `surfaceShape` 选择宿主内置的异形外罩轮廓（如 `roundedRect`、`slantedOval`、`flower`、`cookie`、`clover`、`arch`、`pill`、`circle`）。

## 统一安装目录

官方组件和第三方组件都安装到 `$XDG_DATA_HOME/kos/widgets/<组件 ID>/`。`XDG_DATA_HOME` 未设置或为空时，使用 `$HOME/.local/share`。随 Shell 发布的官方组件由安装流程部署到目标用户的组件目录，第三方组件由插件中心安装到同一个目录。所有已安装组件共用同一个包结构和组件 ID 命名空间。

宿主只扫描这一处组件目录并建立一份索引。桌面、Dock、图库和后台预览队列都从这份索引查找组件及其入口。

## 组件作者的接口

每个组件包使用独立目录，包含三个固定文件，可附带组件自己的 QML 和资源。

| 文件 | 接口约定 |
| --- | --- |
| `metadata.json` | 登记组件 ID、SDK 版本、风格（`style` 必填二选一：`"material"` 或 `"macos"`）、支持的 `[列, 行]` 尺寸和默认尺寸。默认尺寸须属于支持列表。 |
| `Snapshot.qml` | 根对象公开 `getSnapshot(size)`，参数为 `[列, 行]`，同步返回该尺寸可序列化的样例数据对象。 |
| `Widget.qml` | 根对象声明 `property var snapshot: null`、`required property var widgetSize` 和 `required property var appearance`（旧版 `required property var data` 仍向后兼容）。`widgetSize` 使用同样的 `[列, 行]` 格式。 |

数据字段由组件作者定义。图库把 `getSnapshot(size)` 的返回值作为 `data` 传给视图，桌面数据适配层向同一视图提供同结构的真实数据。组件实现绘制和内部交互。拖入桌面、移动、落位和切换尺寸由宿主负责。

发现阶段只读取元数据、校验 SDK 版本和尺寸声明，并检查入口文件是否存在。生成阶段在隔离预览进程中加载 `Snapshot.qml`，检查并调用 `getSnapshot(size)`，校验返回值的类型、可序列化性和大小，再用它初始化 `Widget.qml`。整个生成任务设有耗时上限。两个入口都在同一隔离边界内执行，只开放包内资源读取，禁止访问网络、宿主的真实数据 IPC 和用户文件。

默认尺寸的预览缓存生成成功后，组件才进入图库。入口缺失、接口无效、返回值无法使用或渲染失败时，插件中心显示具体原因。

## 组件外罩与背景接口（SDK 草案）

Shell 绘制组件外罩，负责圆角、裁切、底板、玻璃、边框和阴影。组件负责内容和内部交互。第三方作者可在 `Widget.qml` 根对象上提供可选的 `readonly property var backgroundSpec`，让宿主为当前实例绘制底色。

| 作者提供 | 现行契约 |
| --- | --- |
| 省略 `backgroundSpec` 或返回 `null` | 使用宿主默认底板。无效描述也回退到默认底板。 |
| 纯色面板 | `{ startColor, endColor }`，将 `startColor` 与 `endColor` 设为同一颜色即可。 |
| 渐变面板 | `{ startColor, endColor, midColor?, midPosition?, orientation?: "vertical" \| "horizontal" }`。`midPosition` 取 `[0.01, 0.99]`（默认 `0.5`）；省略 `midColor` 时按起止色中值插值。 |

`backgroundSpec` 可以绑定到 `snapshot` 或 `host` 快照（例如音乐组件绑定 `host.media.artworkColors`，天气组件按晴雨昼夜切换渐变），桌面卡片颜色变更时由外壳（`DeskWidgetCard.qml`）自动做平滑 `ColorAnimation` 过渡。`WidgetGallery.qml`、`DeskWidgetCard.qml` 与 `MusicPreview.qml` 均采用这一统一格式；描述采用普通可序列化数据，字段变化时组件重新发布对象，宿主自动更新当前实例底板。

**用户的透明设置优先。** 透明模式下（macOS 玻璃卡片），宿主关闭组件 `backgroundSpec`，保留内容、裁切、输入命中区与编辑态提示，并把 `appearance.transparent` 设为 `true`。Material 桌面模式下不采用 `backgroundSpec`，始终由 `MaterialCardSurface` 统一绘制当前主题底色、透明度与 KWin 合成器模糊区域；仅 `"style": "material"` 的组件包可在 `Widget.qml` 声明 `readonly property string surfaceShape` 点选宿主内置异形轮廓（默认 `"roundedRect"`，`"style": "macos"` 组件忽略该属性），不向第三方开放自定义背景色，保证全局透明度与质感一致。宿主向组件提供实际外观模式、动态色板和建议前景色，作者可据此调整文字、图标和内容配色。

作者应把需要随透明设置消失的整卡底色都交给 `backgroundSpec`。组件可以在内容层绘制图表、图标和局部色块。全幅 Canvas 或 `Rectangle` 如果把背景画进内容，宿主无法把这些像素单独移除。

**单一外壳硬性约定（禁止在图库侧重写第二套卡片外壳）：** 图库预览（`WidgetGallery.qml`）与桌面正式实例（`DeskCenterWindow.qml`）**不仅加载同一份 `Widget.qml`，外层卡片也必须共用同一个 `DeskWidgetCard.qml`**（图库侧仅开启 `preview: true` 以关闭合成器模糊区域与背景渐变动画，并按桌面逻辑尺寸渲染后等比缩放）。**严禁在图库里另外手写简化的 `Rectangle` / `Gradient` 背景**，避免出现圆角遮罩（`SquircleMask`）、渐变或透明底板与桌面不一致的问题。预览与桌面之间只允许存在数据源（`Snapshot.qml` 样例 vs 实时 `host.*`）以及无合成器时的玻璃预览替代底板差异；每次调整 `DeskWidgetCard.qml` 的预览视觉表现时，须同步递增 `WidgetPreviewCacheLogic.mjs` 的 `CACHE_FORMAT_VERSION`，让磁盘上已缓存的旧缩略图自动失效重绘。将实际外观模式纳入图片缓存键。

## 从第三方场景核对 Shell 能力

先用公开 SDK 描述每类组件所需的输入、输出和生命周期，再对照当前 Shell。内置实现可以作为可行性证据，只有第三方能通过公开接口取得的能力才算已支持。

| 场景 | 当前 Shell 能力 | 需要核对或补齐的 SDK |
| --- | --- | --- |
| 天气随状态变色，透明时保留温度和图标 | `DeskCenterWindow.qml` 已把天气配色传给 `DeskWidgetCard.qml`，宿主已有渐变、Material 和玻璃绘制。 | 公开响应式 `backgroundSpec`、实际外观和前景色。现有 `widgetStyle` 只有彩色和玻璃，需要整卡透明与模糊区域门控。 |
| 时钟同时放在桌面和 Dock | 两处各有内置时钟。 | 同包如何声明可用容器，Dock 槽位尺寸如何传给视图，以及时间数据通过哪个公开入口提供。 |
| Canvas 组件点击内容显示详情 | 内置 QML 可以绘制并接收输入，现有 JSON 插件仅有固定节点和动作。 | 第三方 QML 的运行边界、组件内部输入、编辑态输入归属和实例状态。拖动整个组件由宿主负责。 |
| 日历显示真实事件，图库只显示样例 | 内置日历已有宿主数据路径。 | 正式实例的数据授权及接口，预览环境如何执行 `getSnapshot(size)` 并隔离真实数据。 |

## 服务职责与状态流转

第一版建议由现有平台守护进程统一管理安装、索引和预览调度。桌面、Dock、图库与设置页面订阅同一份索引。实际预览渲染由按需启动的隔离进程执行，正式实例由运行时管理。

| 职责 | 负责的状态和行为 |
| --- | --- |
| 目录与安装 | 远程目录负责发现可安装版本。安装流程复用现有来源校验与安装确认的做法，在暂存区校验包结构、SDK 兼容性、来源和内容摘要，成功后原子发布到统一组件目录。安装、升级、卸载按组件 ID 串行处理。升级失败保留原版本，同 ID 的不同来源需处理冲突。官方包也经过同一发布流程，来源身份由安装记录确定。 |
| 已安装索引 | 从组件目录与安装记录读取元数据、版本、来源、启用状态、可用位置和尺寸。启动时可重建，安装提交后发布带修订号的变更，客户端重连时重新取得完整状态。扫描阶段只读取元数据和校验文件，组件 QML 由运行时或预览进程加载。 |
| 预览队列 | 根据组件内容修订、尺寸和外观调度任务，分别记录待生成、生成中、就绪和失败。缓存可重建，建议存放在 `$XDG_CACHE_HOME/kos/widgets/`。任务结束时核对包修订和目标缓存键，避免更新或卸载之后发布过期结果。 |
| 正式实例与配置 | 组件包和每个实例的位置、尺寸、配置、持久状态分别维护。升级按 SDK 和配置兼容性切换，卸载时显式处理是否保留实例配置。正式运行的隔离、数据授权和状态保存属于独立于预览的 SDK 约定。 |

安装成功后先进入已安装索引，插件中心可以立即显示安装状态与预览进度。当前默认尺寸预览就绪后才进入图库。预览失败只影响图库就绪状态，设置侧保留失败原因和重试入口。已放置实例的运行状态独立记录。若预览预算不足以保留全部默认尺寸图片，应先确定保留容量和异常提示，避免淘汰与重新生成反复触发。

预研时从第三方作者视角走一遍安装、发现、生成预览、添加两份实例、升级和卸载。逐项标记哪些流程已有公开接口，哪些可复用现有平台能力，哪些需要新增。优先核对升级时实例如何切换、同一组件多个实例如何保存独立配置，以及权限撤销后正式实例如何降级。

## 图库生成与缓存

1. 后台服务根据已安装组件索引和当前主题、像素密度检查缓存。登录时补齐缺失项，安装、更新或主题与像素密度变化时按需入队。图库关闭时队列也可以处理，有任务时才启动隔离渲染进程，空闲时释放渲染进程。
2. 初期同时运行 1～2 个预览任务，按缓存键合并重复请求，优先生成各组件的默认尺寸，再补齐其他尺寸。卸载组件或包版本变更后取消过期任务。超时或渲染失败时记录原因并限制重试次数，错误可在插件中心查看。
3. 在隔离环境调用 `getSnapshot(size)`，把样例数据注入同一 QML 视图并绘制一帧。将 PNG 或 WebP 原子写入缓存，提交成功后通知图库，并释放临时 QML 实例和渲染资源。
4. `WidgetGallery.qml` 只列出当前默认尺寸预览已就绪的组件。组件出现后，每个其他尺寸的预览就绪时再显示对应卡片。生成期间可显示全局进度，区分正在生成与没有匹配结果。视口内及附近的卡片按需读取缓存图。
5. 缓存键包含组件 ID、包版本或内容修订、尺寸、主题和像素密度。使用内容修订可以覆盖本地开发时的同版本修改。磁盘图片和内存解码结果分别设置容量上限。磁盘优先保留当前主题和像素密度下每个组件的默认尺寸预览，淘汰其他项后在需要时再补生成。

主缓存保存画好的像素结果，命中时省去快照调用、QML 实例创建、布局和 Canvas 绘制。样例数据可按需缓存，但命中后仍需渲染。图库预览缓存以图片为主，正式桌面实例按组件逻辑持续更新。

## SDK 与宿主能力逐项 Review

以下各项均待 Review。逐项记录第三方作者需要的公开接口、Shell 现有能力、缺口和最终决定。若示例需要访问 Shell 私有对象，对应的公开接口仍有缺口。

- [x] **R1 正式数据来源与封装。** 区分正式实例和 `getSnapshot(size)` 的数据来源。通过宿主只读快照封装时间、媒体、天气、系统、活动与日历/待办数据，明确刷新与离线展示状态。
  **2026-11-25 完成：** 在**进程内运行、安全由使用者自行审计**的信任模型下，`WidgetHostService.qml` 已封装全部 6 组响应式只读 R1 快照（`clock` / `media` / `weather` / `system` / `activity` / `pim`，均带 `status: ready|idle|loading|unavailable`），并通过 `WidgetPackageHost.qml` 的只读 `host` 代理直接注入任意 `Widget.qml`（图库侧 `WidgetPreviewHost.qml` 注入 `host.isPreview === true` 桩对象）。`appearance` 同步暴露 `style` 与完整 Material 动态色板 `palette`。新增组件不再需要写 per-package `*WidgetDataService.qml`。
- [x] **R2 正式视图嵌入与输入。**
  **2026-11-25 完成（进程内动态加载，去白名单）：** 确定采用进程内信任模型（类似 Plasma Plasmoids，不建独立渲染进程）。`WidgetPackageIndex.cpp` 校验并返回每个已安装包的 `rootPath` / `widgetEntry` / `snapshotEntry` / `hasSettings` / `settingsEntry`；`WidgetRegistry.canExecute(entry)` 不再查硬编码白名单；`WidgetPreviewHost.qml` 与 `WidgetPackageHost.qml` 直接从 `$XDG_DATA_HOME/kos/widgets/<id>/` 动态加载 `Snapshot.qml`、`Widget.qml` 与可选 `Settings.qml`；编辑态下由 `DeskWidgetCard` 统一禁用内容输入（`contentEnabled: !root.editMode`）。
- [x] **R3 桌面与 Dock 的容器契约。** 桌面用 `[列, 行]` 描述占格。核对 SDK 如何提供容器类型、实际逻辑尺寸和 Dock 方向，以及正式入口和预览入口如何接收这些信息。用同一时钟包核对桌面表盘与横向、竖向 Dock 紧凑布局。
  **2026-11-26 完成：** `WidgetPackageIndex.cpp` 支持声明 `containers`（`["desktop", "dock"]`）与 `dockUnits`（`2`～`4`）；`host.container`（`"desktop"` \| `"dock"`）与 `host.orientation`（`"horizontal"` \| `"vertical"`）已由 `WidgetPackageHost` / `WidgetPreviewHost` 暴露；`DockContainer`、`DockInfoCarousel`、`DockSideInfoCarousel`、`DockConfigService` 与图库「Dock Widgets」标签均已接入第三方包，示例时钟已验证桌面与横/竖向 Dock 三种形态。
- [ ] **R4 实例配置与生命周期。** 用两份城市各异的天气实例核对配置声明、默认值、更新通知和独立持久化。明确实例暂时隐藏、恢复、重启或升级时的行为，以及定时刷新、动画和资源释放由谁管理。
  "同一个包能添加多份独立实例"这条已经打通一条最小路径：每次从图库把包添加到桌面都会生成一个新的实例 ID（如 `org.nextkde.example.clock#1`、`#2`），各自独立的位置、尺寸和 `Settings.qml` 数据。但这条路径只活在当前这次运行里——已放置的实例完全不会写回 `DeskCenterConfigService` 之外的持久层，重启 Shell 后全部消失，跟桌面文件图标的持久化是两套机制。R4 要闭环，还得把实例 ID、位置、尺寸这三项接上一个会在启动时重新展开的持久化来源。
  **2026-11-25 进展（落盘这一环已接上）：** 实例记录（实例 ID + 包 ID）写入 `deskcenter-widgets.ini` 的 `instancesJson`（按输出分组），位置与尺寸沿用原有键；Shell 启动时按输出重新展开成 `widgetInstances`，ID 序号跨输出持久化，删除实例时同步清掉记录、位置和尺寸。包缺失或当前不可执行的记录会保留在磁盘和内存里（不显示、不丢弃），供 R7 迁移恢复。仍差：实例隐藏/恢复/重启/升级的具体语义，以及定时刷新、动画和资源释放的归属。
- [x] **R5 安装记录与运行版本的一致性。** 官方包与第三方包共用安装目录，评审如何将官方身份与已验证的安装内容绑定。检查索引何时发布新版本、旧实例何时切换、更新失败如何保留旧版本，以及安装中断后目录、记录与索引如何恢复一致。预览任务完成时也应核对当前内容修订。
  **2026-11-26 完成：** 在 `kos-settings`「应用与服务」新增「插件」标签页并复用 `AppCatalog` + GitHub Release 审核流水线：目录仓库中的插件清单放在独立签名文件 `widgets.json` + `widgets.json.sig`；`WidgetPackages` 下载发布压缩包（`.tar.gz`/`.tgz`/`.zip`/`.koswidget`）后校验体积与 SHA-256、在临时暂存区解包并调用 `WidgetPackageIndex::snapshotForRoots()` 做兼容性与安全结构检查，随后原子替换 `$XDG_DATA_HOME/kos/widgets/<appId>`（升级失败自动回滚保留原版本），并在 `AppCatalog` 独立写入 `widget-installed-<appId>.json` 来源回执；`WidgetPackageWatcher` 自动监听变更并通知图库与桌面。
- [x] **R6 已展示组件的预览更新策略。** 新安装的组件等默认尺寸预览就绪后进入图库。评审升级、主题变化或缩放变化时，是否短暂保留上一次成功的预览，以及何时替换、失败提示和旧图过期规则。卸载或撤销信任时立即移除对应图库条目。
  **2026-11-26 完成：** 新增 `WidgetPreviewCacheLogic.mjs` 与 `WidgetPreviewCache.qml`，将渲染结果以 PNG 缓存至 `$XDG_CACHE_HOME/kos/widgets/`（索引存 `$XDG_STATE_HOME/.../widget-preview-cache.ini`），键绑定组件 ID、内容修订号、尺寸、桌面风格、主题色板、语言与屏幕缩放；冷命中直接展示静态图并销毁后台实时 QML 预览，插件升级或切换主题/缩放时暂留上一版有效预览图直至后台以最多 2 个并发（默认尺寸优先）重新抓帧落盘后无缝替换；超出上限优先淘汰非默认尺寸的冷门缓存，卸载、无效或崩溃暂停的包在图库目录同步时立即移除索引与对应缓存图。
- [ ] **R7 现有实例迁移。** 评审内置天气、时钟等拆包后，如何映射旧组件 ID、位置、尺寸和配置。首次升级时目标包尚未部署的情况应保留实例记录，待包就绪后恢复显示。
- [x] **R8 一个包包含多个组件。** 方向已确认（多个组件可以共享一个包），结构未定。`WidgetPackageIndex.cpp` 的 `readPackage()` 仍假设一个目录对应一个组件（单个 `id`/`sizes`，固定各一份的 `Widget.qml`/`Snapshot.qml`），需要定义多组件包的元数据结构、目录内多组视图文件如何组织，以及索引如何把包内每个组件分别暴露给图库。
  **2026-11-26 完成：** `metadata.json` 支持可选 `widgets: [...]` 数组（单组件包保持完全兼容），子组件 `id` 需与包 `id` 一致或以其为命名空间前缀，入口路径 `widgetEntry` / `snapshotEntry` / `settingsEntry` 校验留在包根目录内且支持同目录自动探测 `Settings.qml`，`WidgetPackageWatcher` 同步监听嵌套子目录及入口文件，索引向图库展开为独立条目并附带所属 `packageId`。
- [x] **R9 图库多尺寸展示约定。** 方向已确认：同一个组件 ID 显示为一个分组标题，标题下按 `metadata.json` 的 `sizes` 数组各显示一张预览卡（`WidgetGallery.qml` 的 `Column`/`Flow` 结构已是这个布局），不拆成互不相关的多个图库条目，也不收进一张带选择器的单卡。`sizeChoices()` 直接读包自身声明的 `sizes`（任意 1～4 的 `[列, 行]`，按 `.length` 做类数组判断），并通过 `WidgetPreviewHost` 动态执行所有匹配当前桌面风格的已安装包。
  其下游曾有一个渲染缺陷，已定位并修复：不同档位（如 2×2 与 3×2）的预览卡像素尺寸看起来完全相同。真正原因不是 `cellUnit` 换算公式本身（公式一直是对的），是 `modelData.span` 这个数组字段穿过 `Repeater` 的 `model:` 绑定边界后，被 QML 装箱成一个"类数组"对象——能用下标取值、能 `JSON.stringify`，但 `Array.isArray()` 对它返回 `false`；`WidgetGallery.qml` 的 `cols`/`rows` 判断原来就是用 `Array.isArray(modelData.span)`，于是永远落回 1，预览卡永远按 1×1 的比例换算宽高。现在改成按 `.length` 做类数组判断，不用 `Array.isArray`，已经人工验收通过。
- [x] **R10 落位后尺寸按离散档位吸附，宿主要把新尺寸传回组件内部。** 方向已确认：组件尺寸不是连续区间，是像内置组件 `allowedSizeOrder`（`WidgetLayout.mjs`）那样按包声明的 `sizes` 离散吸附；吸附后宿主必须把新的 `widgetSize` 传给同一个正式运行的 `Widget.qml` 实例，组件据此重新布局（见[组件开发指南](WidgetSDK.zh-CN.md)第 3 节的 `widgetSize` 契约）。桌面落位已升级为通用动态加载：`DeskCenterWindow.qml` 通过 `WidgetPackageHost` 直接加载磁盘上的任意已安装包 `Widget.qml` 与可选 `Settings.qml`，并将 `[card.displayColumns, card.displayRows]` 实时绑定到 `widgetSize`。
  吸附逻辑本身一度整体失效：缩放把手判断 `declaredSizes` 是否存在时同样用了 `Array.isArray()`，命中 R9 描述的同一个装箱 bug，于是永远判定"没有声明尺寸"，退化成连续自由缩放。和 R9 一起修复、一起人工验收通过，现在只能停在包声明的那几档。

建议按三个作者场景开展 Review。先用 Canvas 核对嵌入和输入，再用两份天气实例核对数据、权限和持久化，最后用桌面和 Dock 共用的时钟核对容器契约。三个场景均沿安装、预览、放置、升级与卸载的正常路径核对。

## 逐个核对能否用这套 SDK 写出旧的内置组件

`main` 分支 `DeskCenterWindow.qml` 里旧的内置组件（时钟、天气、日历、待办、系统、活动、音乐、桌面图标分组）都是直接写在桌面窗口里的 `Loader`/`Component`，按 `modelData.id` 分支，不经过任何包边界。本分支已经移除这套内联实现，改成本文档描述的包/索引/宿主模型，但旧代码仍在 `git show main:shell/desktop/modules/deskcenter/DeskCenterWindow.qml` 里，可以逐个读出它们实际依赖了哪些 Shell 私有能力，再对照当前 SDK 草案看缺口在哪。这比只看文档描述更可靠：以下结论都是读旧实现源码得出的，不是猜的。

| 旧组件 | 旧实现实际依赖的 Shell 私有能力 | 当前 SDK 是否覆盖 | 结论 |
| --- | --- | --- | --- |
| 时钟 | 只读：本机时间。可选：模拟/数字换面、Material 花瓣异形面板、内嵌倒计时。 | `host.clock` + `host.settings` + 可选 `Settings.qml` + `appearance.palette` + `surfaceShape` 均已覆盖。 | **完全可写**（示例已接入 `host.clock` 与按实例持久化 `Settings.qml`；Material 模拟/数字时钟可直接通过 `surfaceShape: "flower"` / `"clover"` + `appearance.palette` 实现）。 |
| 天气 | 只读：`WeatherService`（地点、实时气温、天气代码、7 天预报、加载/错误状态），点击卡片打开天气应用。 | `host.weather` + `host.invokeAction("app.open-weather", { location })` + 动态 `backgroundSpec` 均已覆盖。 | **完全可写**，无需新增宿主适配层。 |
| 系统（CPU/内存/磁盘/频率） | 只读：`MetricsService` 实时值及 `cpuHistory` / `memoryHistory` / `frequencyHistory` 历史曲线。 | `host.system` 已直接暴露实时指标与三条历史数组。 | **完全可写**，无需新增宿主适配层。 |
| 活动（应用使用时长等） | 只读：`ActivityUsageService` 今日开机时长、60 天趋势、今日应用时长排行。 | `host.activity` 已直接暴露 `todayKey` / `todayUptimeSeconds` / `recentUptimeDays` / `todayApps`。 | **完全可写**（进程内用户自审模型下直接可读）。 |
| 音乐 | 读：`MediaService` 当前播放器元数据、歌词、封面配色；写：播放控制 + 呼起播放器窗口。 | `host.media`（含 `artworkColors`）+ `host.invokeAction("media.*")` + 动态三段渐变 `backgroundSpec` 均已覆盖。 | **完全可写**，示例包 `org.nextkde.example.music` 已验证。 |
| 待办 / 日历 | 读：`PimWidgetService`（今日日程、待办列表、缓存/错误状态）；写：深链打开日历 App 指定视图/条目。 | `host.pim` + `host.invokeAction("app.open-calendar", { view, item })`（支持 `day`/`week`/`month`/`year`/`todo`/`today`/`reminders`）均已覆盖。 | **完全可写**，无需新增宿主适配层。 |
| 桌面图标分组（`groups`） | 直接读写桌面文件网格本身的状态（`desktopFileGrid.orderedEntries`、重命名回调、右键菜单回调、分类选择）。 | 不适用——这不是一个"内容独立的组件"，它就是桌面图标视图本身套了一张卡的壳。 | **本来就不该走 SDK**，保留在 Shell 私有实现里即可。 |

概括：截至 2026-11-25，随着直调式 `host` 代理（R1 全部 6 组只读快照 + R11 反向动作 + 通用按实例持久化 `Settings.qml`）、`appearance.palette` Material 动态色板，以及去白名单的磁盘动态 QML 加载（R2）全部落地，除本质属于桌面文件视图的 `groups` 之外，**全部 6 类旧内置组件（时钟、天气、系统、活动、音乐、待办/日历）以及自定义第三方组件都已经可以纯按 SDK 文档写出来并直接运行**。

- [x] **R11 组件向宿主请求执行动作(反向命令通道)。** 旧音乐组件需要播放控制(上一首/播放暂停/下一首)、唤起或聚焦正在播放的 App 窗口;旧待办/日历组件需要"深链打开日历 App 的指定视图或条目"。这两种都是"组件→宿主"方向的请求,不是数据展示。
  **2026-11-25 完成：** `WidgetHostService.invokeAction(actionName, payload)` 封装了 `media.previous`/`media.toggle-play-pause`/`media.next`/`media.raise-player`/`app.open-weather`/`app.open-calendar`（含 `todo`/`today`/`reminders` 视图），返回结构化 `{ ok, code, message }`（`ok`/`unknown-action`/`unavailable`/`invalid-argument`）；`WidgetPackageHost` 同时通过 `host.invokeAction(...)` 与可选 `actionRequested` 信号两条路径提供调用，图库预览自动断开动作通道返回 `unavailable`。

## 预算与实施顺序

- 以 100 个可搜索组件为规模目标。若单个预览实例增加约 20 MB，1～2 个并发实例对应约 20～40 MB 的实例增量。隔离进程、解码图片和 GPU 纹理另计。20 MB 是规划假设，并发数与缓存上限待实机测量后确定。
- 先用一个支持多个尺寸的 Canvas 组件打通显示链路，确认同一视图可以分别接收桌面数据和图库样例数据。
- 再接入图库索引、按需生成和图片缓存，覆盖版本、主题、尺寸或像素密度变化后的重新生成。
- 实现后由人工观察冷缓存和热缓存的打开速度、快速滚动时的响应、生成预览时的峰值内存，以及关闭图库后临时实例与渲染资源是否释放。
