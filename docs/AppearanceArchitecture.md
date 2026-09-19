# 全局外观系统架构

> 状态：Dock 形态、Bar 布局/隐藏、全局图标外观、Glass 预设/同步、Dock 窗口动画与 Material 3 配色（莫奈 / 中国传统色 / 日系配色三种来源）已实现（更新至 2026-09-19）。本文是后续开发和 AI 接续工作的规范来源。

## 1. 当前能力与边界

外观设置分为彼此正交的维度：

- **系统外观**：`kos-settings > 显示 > 色彩模式` 优先应用 KDE 的 `Breeze / BreezeDark` Look-and-Feel，失败时回退到 `BreezeLight / BreezeDark` 色彩方案。目前不写入本项目配置。
- **Material 3 配色**：壁纸主色作为种子，在进程内生成全套 M3 角色色。默认算法是 matugen `scheme-vibrant` 的纯 JS 移植；另有两套传统色方案（`chinese` / `japanese`）把种子吸附到命名色卡，以便主色保留壁纸自身的明度而不是被 Monet 强制到固定色调——三者在 `material` 形态下由设置页切换。**都不需要安装 matugen、Python 或 ImageMagick**，配合 Quickshell 内置 `ColorQuantizer` 完成取色，全链路无外部进程。详见第 10 节。
- **玻璃材质**：`liquid`、`soft`、`frosted` 三套预设各自保存模糊、液态强度与受限光学参数；当前样式的 `blurStrength` 与 `liquidStrength`（均为 `0.0...1.0`）同步给自定义 KWin `glass` effect，不会修改 KDE 自带的 `Effect-blur`。Quickshell 显式 Blur Region 结合全局 `CornerExponent` 与 per-surface shape/scrim；普通窗口只走同一模糊管线，不执行折射、染色、高光、噪点或圆角裁切。没有 Dock、Bar 或启动器的独立强度接口。
- **全局图标外观**：`IconAppearanceService` 持久化 `color | grayscale | tint`、不透明度和染色颜色。Dock、启动台、快速搜索、Bar/托盘和 DeskCenter 共同消费，不再由 Dock 配置单独拥有。
- **Shell 形态**：`shellStyle`，值为 `windows12 | macos | material`。设置页已可选择并持久化；Dock 已接入形态 Token，DeskCenter 尚未接入形态 Token。Bar 不随形态分叉。
- **Bar 布局**：`barIntegratedWithDock` 是独立布尔配置，适用于底部与侧边 Dock；`barLayoutMode` 提供 `full | floating | transparent`，`barVisibilityMode` 提供 `always | smart | persistent`。融合后顶部 Bar 收起，底部 Dock 托管时间与系统状态，侧边 Dock 使用纵向状态与信息布局。
- **Dock 窗口动画**：`dockWindowAnimationStyle`，值为 `scale | genie`，默认 `scale`。由 `DockWindowAnimationTargetService` 向 KWin dock-window-animation effect 发布图标矩形，设置页可选择并持久化。

主题选择会立即更新 Dock 的几何、间距、状态背景、运行指示器和动效。Bar 始终保持统一视觉；是否融入 Dock 完全由独立开关决定。DeskCenter 已接入全局图标外观，但形态 Token 仍是后续工作。

## 2. 所有权和依赖方向

```text
kos-settings Theme/Display page
        │ SettingsBridge（C++，启动 qs ipc call）
        ▼
DesktopEnvironment.qml / appearance-settings
        │
        ▼
AppearanceConfigService ──────► state/appearance/config.json
IconAppearanceService ────────► state/appearance/icon-appearance.json
        │                         custom KWin glass effect
        ▼
AppearanceTokens ◄──── 壁纸取色桥（shared 无反向依赖）
   ├── dock            │
   ├── bar             │
   ├── widget          │
   ├── surface         │
   ├── glass           │
   └── motion          │
                       │
   shared/qml/colorize/（Kos.Ui 模块）
   ├── WallpaperColorSource  读 Plasma 壁纸配置，解析壁纸包
   ├── ArtworkColorSource    ColorQuantizer 从图像抽两色
   ├── ColorScheme           种子色 → M3 全套角色色（纯 JS，无外部进程）
   ├── MaterialColorScheme.mjs   角色→色族/色调映射 + 各族色度曲线
   └── Cam16Hct.mjs          CAM16/HCT 色彩外观模型（MCU 移植）
        │
        ▼
Dock（已接入，可托管 Bar 内容） / Bar（统一视觉） / DeskCenter（图标外观已接入）
```

配色链路的数据流：

```text
Plasma 配置 ──► WallpaperColorSource ──► ArtworkColorSource ──► 主色
                     │                          │
                     │                          ▼
                     │                   ColorScheme.setSeed()
                     │                          │
                     └── paletteChanged ──► AppearanceConfigService.wallpaperSeedColor
                                                │
                                                ▼
                                        AppearanceTokens.seedColor ──► colors.*
```

职责约束：

1. `AppearanceConfigService` 是形态、Glass、Bar 与窗口动画配置的所有者；`IconAppearanceService` 单独拥有全局图标外观。
2. `AppearanceTokens` 只把配置映射成语义值，不执行 IO，也不拥有业务数据。
3. 消费组件读取 Token，不应散落 `shellStyle === ...` 分支。
   表面宿主还应读取 `AppearanceTokens.surface`：当前 `treatment` 为
   `glass | tonal`，并预留新增值；`usesBackdrop` 决定是否登记合成器背景区域，
   各 surface 的 fill/opacity/outline 则由同一组 Token 提供。新增主题应先在
   此处定义表面策略，不能把新主题当作 `!isMaterial` 的默认回退。
4. Dock 的固定项、尺寸、位置、窗口分组和显示策略仍归 `DockConfigService` 所有；全局图标模式归 `IconAppearanceService`，切换形态不得覆盖这些用户设置。
5. 独立进程 `apps/settings` 不允许 import `shell/desktop/`，只通过 IPC 读写。
6. **`shared/qml/colorize/` 属于 `Kos.Ui` 公共层，不得 import `qs.desktop.modules.*`。** 需要与 shell 通信时用「注入属性 + 出站 signal」，由 `AppearanceTokens` 中的两个 `Connections` 完成接线。


## 3. 文件索引

| 文件 | 责任 |
| --- | --- |
| `shell/desktop/modules/common/AppearanceConfigService.qml` | schema、校验、迁移、保存、Glass effect 同步 |
| `shell/desktop/modules/common/AppearanceTokens.qml` | 五组只读语义 Token；同时托管壁纸取色与 shell 配置之间的两个 `Connections` 适配器 |
| `shared/qml/colorize/WallpaperColorSource.qml` | 单例。读 Plasma 壁纸配置，解析壁纸包（按屏幕宽高比选图），对外只暴露 `darkMode` 注入与 `paletteChanged` / `paletteCleared` 信号 |
| `shared/qml/colorize/ArtworkColorSource.qml` | `Item`。用 Quickshell `ColorQuantizer` 从图像抽两个可区分的主色；MPRIS 封面与本地壁纸通用 |
| `shared/qml/colorize/ColorScheme.qml` | 单例。接收种子色，按 `scheme` 分派给莫奈 / 中国传统色 / 日系配色，产出 49 个角色 × light/dark。纯同步计算，不启动任何进程 |
| `shared/qml/colorize/MaterialColorScheme.mjs` | 角色→色族/色调映射、各族随色调变化的色度曲线、变体（vibrant / tonal-spot）的色相旋转表 |
| `shared/qml/colorize/TraditionalColorScheme.mjs` | 传统色方案：把种子色吸附到色卡最近邻（保真），围绕它派生其余角色，对比度不足时调整前景而不是色调；色卡无法表达时整体回退莫奈 |
| `shared/qml/colorize/ChineseColors.mjs` | 纯数据表：526 个中国传统色（色名 + hex） |
| `shared/qml/colorize/JapaneseColors.mjs` | 纯数据表：228 个日本传统色（色名 + hex） |
| `shared/qml/colorize/Cam16Hct.mjs` | CAM16/HCT 色彩外观模型。MCU 的 `hct/*.ts`、`viewing_conditions.ts`、`hct_solver.ts` 移植版，对外提供 `hexToHct` / `hctToHex` |
| `shell/desktop/modules/common/IconAppearanceService.qml` | 全局图标模式、不透明度、染色与旧 Dock 配置迁移 |
| `shell/desktop/modules/common/MaterialCardSurface.qml` | Material 形态的卡片表面：七张卡共用的漆层（`fillColor` / `fillOpacity`，无描边）+ 各自轮廓的 blur region（圆角矩形或花瓣）；不经过 `LiquidGlassPanel`、不声明 `SurfaceShape`，所以合成器只给磨砂、不给液态材质 |
| `shell/desktop/modules/common/FlowerBlurRegion.qml` | 花瓣形状的模糊区域：对 MaterialFlower 的极坐标轮廓做扫描线填充，32 行 × 2 槽位共 64 个静态 `Region`；供 Material 表面里「表面即形状」的卡片（时钟）使用 |
| `shell/desktop/modules/common/qmldir` | 注册公共组件与 singleton |
| `shell/desktop/modules/common/BundledIcons.qml` | Shell 自带图案的登记表，并为少数系统主题图标提供回退解析 |
| `shell/desktop/modules/common/BundledIcon.qml` | 统一渲染已登记的 Shell 图案 |
| `shell/desktop/modules/common/SystemIconResolver.qml` | 为回收站等少数需跟随系统图标主题的图标解析候选路径 |
| `shell/desktop/DesktopEnvironment.qml` | `appearance-settings` IPC target |
| `apps/settings/src/main.cpp` | Settings 到 Quickshell IPC 的进程桥 |
| `apps/settings/main.qml` | “显示”“主题”“顶栏”“Dock”“启动台”“快捷键”和“接入状态”页面 |
| `shell/desktop/modules/bar/BarDateStatus.qml` | 独立顶部 Bar 的时间日期内容 |
| `shell/desktop/modules/bar/BarStatusArea.qml` | 可复用的托盘、网络、电池与控制中心内容；向 Dock 提供稳定的单行最大宽度预算 |
| `shell/desktop/modules/bar/SysTray.qml` | 系统托盘宿主；原生托盘项与 Wi‑Fi、电池、设置、控制中心共用连续 Grid，融合 Dock 高度达到 48px 时自动折为两行 |
| `shell/desktop/modules/bar/BarWindow.qml` | 独立顶栏的 layer-shell 几何宿主 |
| `shell/desktop/modules/dock/DockInfoCarousel.qml` | Dock 音乐、天气、融合时钟、常驻温度的固定宽度轮播宿主 |
| `shell/desktop/modules/dock/DockSideInfoCarousel.qml` | 左/右 Dock 的单行信息轮播；父 Row 旋转 90°，面板反向旋转保持文字正立，沿边占两个图标位 |
| `shell/desktop/modules/dock/DockMetricGlyph.qml` | Dock 信息卡的主题无关高对比度字形（温度/时钟），Canvas/仓库 SVG 绘制纯白像素 |
| `shell/desktop/modules/dock/DockClockWidget.qml` | 左侧为液态时间与日期，右侧为带图标的日落/日出时间；使用与天气/音乐同规格的壁纸环境色卡片 |
| `shell/desktop/modules/dock/DockTemperatureWidget.qml` | 常驻 Dock 温度页；左侧用白色加粗的系统主题温度图标、蓝/红状态点和紧凑上下行显示平均/最高温度，右侧复用 DeskCenter 的 CPU/内存/存储三环语义与配色；只消费公共 `MetricsService` 快照 |
| `shell/desktop/modules/dock/DockContainer.qml` | Token 驱动的 Dock 自适应比例和圆角 |
| `shell/desktop/modules/dock/DockWindow.qml` | Token 驱动的贴边距离与玻璃环境系数 |
| `shell/desktop/modules/dock/DockIcon.qml` | Token 驱动的状态背景、指示器、放大与位移 |
| `shell/desktop/modules/dock/DockAnimation.qml` | 将 motion Token 投影到 Dock 动效语义 |
| `shell/desktop/modules/dock/DockWindowAnimationTargetService.qml` | 向 KWin dock-window-animation effect 发布合成器全局坐标下的 Dock 图标矩形（采样自渲染后的 AppIcon），驱动 `dockWindowAnimationStyle` |

### 3.1 Shell 图标契约

Shell 自带图案由 `BundledIcons` 的稳定名称登记，消费者使用
`BundledIcon` 或 `BundledIcons.source(name)`，不得依赖仓库外的绝对路径或
字体字形。应用图标、媒体封面和文件缩略图不属于这一契约。

只有必须跟随桌面图标主题的少数图标（当前为 Dock 回收站）通过
`SystemIconResolver` 查询 freedesktop/KDE 候选并回退到 bundled 图案。新增
系统主题图标时，候选列表集中维护在 resolver，业务组件不得自行复制解析逻辑。

## 4. 持久化契约

运行时路径：

```text
Quickshell.stateDir + "/appearance/config.json"
```

schema 27：

```json
{
  "version": 27,
  "globalBlurStrength": 0.0,
  "globalLiquidStrength": 1.0,
  "materialPresetBlurStrength": 0.1,
  "glassStyle": "liquid",
  "liquidPresetBlurStrength": 0.0,
  "liquidPresetLiquidStrength": 1.0,
  "liquidPresetRefraction": 1.0,
  "liquidPresetEdgeSize": 50.0,
  "softPresetBlurStrength": 0.1,
  "softPresetLiquidStrength": 0.5,
  "frostedPresetBlurStrength": 1.0,
  "frostedPresetLiquidStrength": 0.5,
  "blurStrength": 0.0,
  "liquidStrength": 1.0,
  "shellStyle": "macos",
  "themeMode": "system",
  "materialColorScheme": "monet",
  "glassFollowsAppearanceMode": false,
  "barIntegratedWithDock": false,
  "barVisibilityMode": "always",
  "barLayoutMode": "transparent",
  "dockWindowAnimationStyle": "scale"
}
```

- 每个玻璃预设还持久化 `Refraction`、`EdgeSize`、`NormalPow`、`RGBFringing`、`OffsetStrength`、`Softness` 和 `Reflection`；示例只列出代表字段。预设参数均由范围表校验，不能以手改配置绕过设置页的有效范围。
- 默认 `glassStyle` 为 `liquid`，`shellStyle` 为 `macos`，`barLayoutMode` 为 `transparent`，`themeMode` 为 `system`（合法值 `system` / `light` / `dark`）。切换玻璃样式会应用该样式的完整预设；Material 使用独立的模糊预设且禁用液态折射。
- schema 1–10 完成早期全局强度、Shell/Bar/主题迁移；v16 起为每种玻璃样式保存独立预设，v17–v24 多次校准 soft/frosted 的默认光学值，v26 将液态预设的旧 body lens 默认值迁移为 0，v27 增加 Material 配色来源。读取旧文件后会写回 schema 27。
- 非法或缺失的 `shellStyle` 回退为 `macos` 并写回；非法或缺失的 `dockWindowAnimationStyle` 回退为 `scale`；非法或缺失的 `themeMode` 回退为 `system`；非法或缺失的 `materialColorScheme` 回退为 `monet`（v27 之前写出的文件因此保持原有莫奈配色，升级不会改变观感）；非法强度不会覆盖内存默认值。
- 强度输入会裁剪到 `0...1`；未知形态输入被拒绝。
- 保存采用 350ms 防抖，并通过临时文件后 `mv` 原子替换。
- `resetStrengths()` 只恢复 `0.42 / 1.0`，不重置主题形态或 Dock 数据。
- `blurStrength` 与 `liquidStrength` 是随全局值写回的兼容字段。全局图标外观另存于同目录的 `icon-appearance.json`（schema 1），包含 `mode`、`opacity` 与 `tintColor`，并可从旧 Dock 配置迁移一次。

## 5. IPC 契约

target：`appearance-settings`。所有更新都返回完整 JSON snapshot。

| 调用 | 参数 | 作用 |
| --- | --- | --- |
| `snapshot` | 无 | 读取完整外观状态 |
| `updateGlobalBlurStrength` | real | 更新全局模糊强度；`updateBlurStrength` 为兼容别名 |
| `updateGlobalLiquidStrength` | real | 更新当前样式的液态强度；`updateLiquidStrength` 为兼容别名 |
| `updateGlassStyle` | `liquid` / `soft` / `frosted` | 切换并应用完整玻璃预设 |
| `updateGlassPresetParameter` | name, real | 更新当前预设的受限光学参数：`Refraction`、`EdgeSize`、`NormalPow`、`RGBFringing`、`OffsetStrength`、`Softness` 或 `Reflection` |
| `resetGlassPreset` | style | 将指定玻璃预设恢复为其作者默认值 |
| `updateGlobalIconMode` | string | 更新全局图标模式（`color`/`grayscale`/`tint`） |
| `updateGlobalIconOpacity` | real | 更新非彩色图标不透明度 |
| `updateGlobalIconTintColor` | string | 更新全局染色颜色（`#rrggbb`） |
| `updateShellStyle` | string | 更新 Shell 形态 |
| `updateMaterialColorScheme` | `monet` / `chinese` / `japanese` | 更新 Material 风格的配色来源（仅 `material` 形态消费） |
| `updateGlassFollowsAppearanceMode` | bool | 控制 per-surface 对比 scrim 是否随明暗外观切换 |
| `updateBarIntegratedWithDock` | bool | 更新 Bar/Dock 宿主策略 |
| `updateBarVisibilityMode` | string | 更新 Bar 显示方式（`always`/`smart`/`persistent`） |
| `updateBarLayoutMode` | string | 更新 Bar 布局（`full`/`floating`/`transparent`） |
| `updateDockWindowAnimationStyle` | string | 更新 Dock 窗口动画风格（`scale`/`genie`） |
| `resetStrengths` | 无 | 只重置两项玻璃强度 |

snapshot 示例：

```json
{
  "globalBlurStrength": 0,
  "globalLiquidStrength": 1,
  "glassStyle": "liquid",
  "activePresetRefraction": 1,
  "activePresetEdgeSize": 50,
  "effectiveDockBlur": 0,
  "effectiveDockLiquid": 1,
  "effectiveBarBlur": 0,
  "effectiveBarLiquid": 1,
  "effectiveLauncherBlur": 0,
  "effectiveLauncherLiquid": 1,
  "blurStrength": 0.42,
  "liquidStrength": 1,
  "iconMode": "color",
  "iconOpacity": 0.5,
  "iconTintColor": "#a855f7",
  "shellStyle": "macos",
  "materialColorScheme": "monet",
  "materialAccentName": "",
  "glassFollowsAppearanceMode": false,
  "barIntegratedWithDock": false,
  "barVisibilityMode": "always",
  "barLayoutMode": "transparent",
  "dockWindowAnimationStyle": "scale",
  "tokenVersion": 9
}
```

手动检查：

```bash
quickshell --path shell ipc call appearance-settings snapshot
quickshell --path shell ipc call appearance-settings updateShellStyle material
```

`SettingsBridge` 会拒绝缺少任一核心字段的响应，并用 `lastError` 告知 QML。增加 snapshot 字段时应保持向后兼容；删除或重命名字段需要同时升级桥接层。

## 6. AppearanceTokens v9

数值单位：`height/radius/gap` 与 duration 分别为逻辑像素和毫秒；以 `Ratio` 结尾的值乘以消费组件的 `iconSize` 或基准高度。字符串用于选择布局策略或视觉 delegate。

### Dock

| Token | Windows 12 | macOS | Material |
| --- | --- | --- | --- |
| `form` | `taskbar` | `floatingDock` | `navigationDock` |
| `position` | `bottom` | `bottom` | `bottom` |
| `radiusRatio` | 0.20 | 0.50 | 0.50 |
| `horizontalPaddingRatio` | 0.24 | 0.40 | 0.32 |
| `verticalPaddingRatio` | 0.12 | 0.20 | 0.16 |
| `itemSpacingRatio` | 0.07 | 0.09 | 0.08 |
| `dividerMarginRatio` | 0.16 | 0.20 | 0.18 |
| `edgeMargin` | 0 | 5 | 8 |
| `workspaceGap` | 0 | 5 | 8 |
| `indicatorStyle` | `underline` | `dot` | `tonal` |
| `indicatorLengthRatio` | 0.42 | 0.13 | 0.34 |
| `indicatorThicknessRatio` | 0.07 | 0.13 | 0.07 |
| `activeRadiusRatio` | 0.18 | 0.30 | 0.28 |
| `activeBackgroundMode` | `subtle` | `glass` | `tonal` |
| `magnificationEnabled` | false | true | false |
| `hoverScale` | 1.00 | 1.20 | 1.00 |
| `hoverLiftRatio` | 0.00 | 0.08 | 0.00 |

### Bar 与桌面组件

| Token | Windows 12 | macOS | Material |
| --- | --- | --- | --- |
| `bar.placement` | top | top | top |
| `bar.height` | 35 | 35 | 35 |
| `bar.radius` | 0 | 0 | 0 |
| `bar.surfaceMode` | transparent | transparent | transparent |
| `bar.unifiedWithDock` | 独立配置 | 独立配置 | 独立配置 |
| `widget.radius` | 12 | 26 | 20 |
| `widget.gap` | 8 | 10 | 12 |
| `widget.elevation` | 2 | 1 | 3 |
| `widget.surfaceMode` | acrylic | glass | tonal |

### Glass 与 motion

`glass.blurStrength` 和 `glass.liquidStrength` 直接投影配置。局部表面可以乘以下列系数，但不得重新定义全局强度。

| Token | Windows 12 | macOS | Material |
| --- | --- | --- | --- |
| `glass.highlightMultiplier` | 0.72 | 1.00 | 0.55 |
| `glass.ambientMultiplier` | 0.85 | 1.00 | 0.70 |
| `motion.fastDuration` | 120 | 135 | 100 |
| `motion.normalDuration` | 180 | 200 | 220 |
| `motion.slowDuration` | 260 | 360 | 300 |
| `motion.standardEasing` | OutCubic | OutCubic | OutQuart |
| `motion.springEnabled` | false | true | false |

### Shape

| Token | 值 | 说明 |
| --- | --- | --- |
| `shape.cornerExponent` | 3.0 | 圆角族指数。`2.0` 是精确的圆弧，等价于改造前的 `Rectangle.radius`；大于 2 时角相对圆弧沿对角线外鼓 `2^(1/2-1/n) - 1`，即 2.5→7%、3→12%、4→19%。**数值越大角越方**，想更圆就往 2.0 调；要改角的大小（形状不变）动的是各组件的 `radius`。 |
| 圆角刻度 | 非 Material `5/5/10/14/20/26/999`，Material `6/8/12/17/23/30/999` | 依次为 `unsharpened / extraSmall / small / medium / large / extraLarge / full`。 |

指数是形状族里唯一跨进程的 Token，有两处消费者，必须一起看：

- **QML 侧**：`common/Squircle.mjs` 是几何真值；`LiquidGlassPanel` 是常规消费者（内部经 `SquircleMask` 上遮罩），全仓唯一仍手写遮罩的地方是带全出血画面的 DeskCenter 卡片 `deskcenter/DeskWidgetCard.qml`。
- **合成器侧**：同一个值经 `AppearanceConfigService._syncGlassEffect()` → `theme.sync-glass` → `kwriteconfig6 Effect-blurplus CornerExponent` → `reconfigureEffect("glass")` 送达自定义 KWin glass effect。**这条通道是全局单值**，不是按窗口传的。

QML 无法把半径告诉合成器——`ext-background-effect` 只有 `set_blur_region`，载荷是整数矩形列表，没有 radius 字段。逐 surface 的精确形状因此走项目自有的 `kos-surface-shape-v1`，细节见 `PlatformArchitecture.md`。

Token schema 当前为 `AppearanceTokens.version === 9`。现有 Dock、Bar、widget、glass 与 motion Token 表保持上表语义；修改现有 Token 语义或删除字段时必须升版本。v9 新增 `shape.cornerExponent`，并把非 Windows 12 形态的 `dock.radiusRatio` 统一到 0.50。

## 7. 消费规则

推荐写法：

```qml
radius: iconSize * AppearanceTokens.dock.radiusRatio
spacing: iconSize * AppearanceTokens.dock.itemSpacingRatio
Behavior on opacity {
    NumberAnimation { duration: AppearanceTokens.motion.fastDuration }
}
```

不要在 surface 内复制这类逻辑：

```qml
// 禁止：会形成第二套主题映射。
radius: AppearanceConfigService.shellStyle === "macos" ? 24 : 12
```

接入时还要遵守：

- Token 决定视觉形态，现有业务 service 决定数据和行为。
- 主题热切换不能重建应用模型、改变 pinned 顺序或清除窗口状态。
- `bar.unifiedWithDock` 是独立布局要求，不是把两个 layer-shell 窗口简单叠在底部。开启后无论 Dock 位于底部、左侧还是右侧，顶部 Bar surface 都把排斥区设为零并隐藏。底部 Dock 把时间放入信息轮播、状态区作为右侧附件；左/右 Dock 使用 `DockSideInfoCarousel` 单行轮播（父 Row 旋转 90°、内容反向旋转保持文字正立，沿边占两个图标位），状态序列沿侧边排列。
- 融合宿主必须按 Dock 边缘决定弹窗方向：底部向上、左侧向右、右侧向左，包括托盘菜单/提示、网络、蓝牙和电池；控制中心卡片组在左侧 Dock 时镜像到屏幕左侧。恢复独立顶部 Bar 后仍向下展开。
- Bar 状态区的图标来自 `BundledIcon`/`BundledIcons`（shell 自带图案，任何机器上一致）；只有必须跟随系统图标主题的少数图标走 `SystemIconResolver`，目前是 Dock 回收站。Wi‑Fi 由 `WifiSignalIcon` 按信号等级用 Canvas 绘制，设置、控制中心使用项目自绘 SVG：独立 Bar 与 Dock `color` 模式输出白色，`grayscale` 叠加与应用图标相同的 `iconOpacity`，`tint` 将 72% 基准亮度投影到 `iconTintColor` 后再叠加轻微暗影，避免纯色 SVG 比其他图标突兀。电池保留电量绘制，但在 Dock `tint` 模式下使用同一 tonal 色、透明度和阴影。快捷状态组只保留布局 padding，不绘制整组白色蒙层。
- `IconAppearanceService.mode` 同时约束 Dock 应用图标、启动台、快速搜索、原生 SystemTray、自绘 Wi‑Fi/设置/控制中心图标、DeskCenter 内容，以及天气/时间/温度卡片背景。`color` 保留内容原色；`grayscale` 按亮度去色；`tint` 先保留亮度层级再投影到 `tintColor`。该规则是 Shell 全局设置，独立顶部 Bar 与 Dock 承载的状态区都消费同一配置；电池继续使用能够表达电量与充电状态的专用绘制。
- 融合模式的状态托盘把原生 SystemTray 项与 Wi‑Fi、电池、设置、控制中心组成一条连续序列，以 `48px` 可用高度为两行阈值：至少两个项目且达到阈值时按列连续填入两行，否则保持单行；独立顶部 Bar 永远单行。Dock 温度页在融合与非融合模式下都保留；融合后状态附件隐藏重复的 CPU 摘要，恢复独立 Bar 后摘要重新显示。Dock 高度求解使用 `BarStatusArea.layoutMaximumWidth` 的单行最大宽度，最终宽度才采用折行后的实际宽度，禁止让行数反向参与高度求解形成 binding loop。
- Dock 温度页、独立 Bar 温度摘要和 DeskCenter 温度区必须只读取公共 `MetricsService`。该 singleton 从 `kos-data-service` 的原子快照取值；任何 surface 都不得另外读取 `/proc`、`/sys` 或启动新的采样进程。快照尚未就绪时 Dock 页仍占位并显示 `--`，不能从轮播中消失。
- Material 的 `tonal` 需要从系统 palette/壁纸 palette 派生，不得在组件里硬编码紫色。设置页紫色仅用于预览识别。
- 可读性遮罩和最小对比度优先于透明度；局部 multiplier 只允许弱化或增强材质细节。

## 8. 设置页行为

- 侧栏顺序为：显示 → 主题 → 顶栏 → Dock → 启动台 → 快捷键 → 接入状态。
- “显示”保留系统明暗与玻璃强度；“主题”只选择 Shell 形态，避免把配色与形态耦合。
- 三张卡片展示 Bar、Dock 和桌面卡片的形态缩略图；点击后同步调用 IPC，成功响应决定最终选中态。
- 选择 Material 形态后，卡片下方出现“主题色系”：三张色卡并列（莫奈色 / 中国传统色 / 日系配色），每张用**该方案在当前壁纸下的真实颜色**画出（主色大块 + 伴随色与两种外观的表面色条），选中态用各自的强调色描边，并显示当前吸附到的传统色名。换成其它形态时这一块连同其高度一起消失，因为玻璃形态不消费这个设置；切换仍写入配置，所以在形态之间往返不会丢失选择。
- 色卡的颜色由 Shell 计算并经 snapshot 的 `materialColorSwatches` 下发（`ColorScheme.previewSwatches()`）。设置页是独立进程，不评估配色，也不为了取预览而反复切换 `scheme`——那会让整个 shell 每个 snapshot 重绘三次。
- 桌面 Shell 未运行、IPC 超时或响应不完整时，页面显示 `SettingsBridge.lastError`，不得伪造保存成功。
- Dock、启动台、快速搜索、Bar 与 DeskCenter 已接入全局图标外观；DeskCenter 的形态 Token 仍待后续阶段接入。

## 9. 后续实施顺序

1. **Dock（已完成第一轮）**：圆角、padding、spacing、indicator、状态背景和 motion 已接入；位置、尺寸、显示策略及模型保持用户所有。
2. **Bar 融合（已实现）**：Bar 保持统一视觉；底部 Dock 将时间作为音乐/天气轮播的一页，并托管系统状态；侧边 Dock 自动回退顶部 Bar。
3. **DeskCenter**：全局图标外观已接入；后续只替换形态相关的卡片容器、gap、surface/elevation，不触碰天气、文件、活动等数据逻辑。
4. **Dock 收口**：完成三风格 × 独立/融合 Bar 的视觉回归。
5. **全局收口**：搜索并移除已被 Token 取代的散落常量，增加三风格 × 明暗模式视觉回归。

每完成一个 surface，更新本文的“当前能力与边界”和 Token 消费清单，再开放下一 surface。

## 10. Material 3 配色算法

配色方案完全在进程内计算，**不依赖 matugen、Python 或 ImageMagick**。算法实现在
`shared/qml/colorize/MaterialColorScheme.mjs`（纯 ES module，可被 Node 直接测试），
底层的 CAM16/HCT 色彩外观模型在 `shared/qml/colorize/Cam16Hct.mjs`。

### 10.1 用 CAM16/HCT，不是 CIE Lab

> **HCT 移植已经完成（2026-09-11）。** 本节原有的「用 Lab 近似」方案已被替换。
> 下面保留替换的理由与实测证据，因为它们是这次决策的依据。

Material 的 HCT 用 CAM16 承载色相与彩度通道，tone 则精确等于 CIE Lab 的 L\*。
曾经据此认为可以「用普通 Lab/LCh 复现官方方案，完全跳过 CAM16」——**这个判断是
错的**。实测下来，Lab 近似只在当初校准用的那一个种子上准确，换任何别的种子都会
明显偏色；原因是 Lab 与 CAM16 的彩度通道在 M3 所使用的观看条件下并不可线性互换。

现在的实现是 MCU 的 `hct/*.ts`、`viewing_conditions.ts`、`hct_solver.ts`、
`utils/color_utils.ts` 的忠实移植。代价只是「一次 3×3 矩阵加几次非线性」，在
QML/JS 里完全可以承受：单次生成整套 49×2 角色耗时在毫秒级。

实测准确率（12 个种子 × 49 角色 × 2 模式）：

| 指标 | 数值 |
| --- | --- |
| 逐角色完全一致 | **75.0%** |
| ≤ 1 字节步长（肉眼等同） | **91.2%** |
| 最大字节步长 | 9 |

**已知残差（都不是 bug，改动前先读）**：

1. 容器色调上，请求色度基本不起作用——色域会把高、低两种请求裁到同一个代表色。
   所以「按角色取名义色度」这条路走不通：用字节步长重测后，它反而比现在的
   tone 表更差（曾输出 `#00fde7` 而基准是 `#bcece3`，188 步）。
2. `on_surface_variant:dark` 差 1 步，是基准工具自身不一致：同一个角色在它的
   `outline_variant:light` 里必须等于同一颜色，却输出了不同字节。我们取满足更多角色的那个值。
3. `on_background:light` 在个别种子上差几步，因为基准那边这个值经过 `ContrastCurve` /
   `tMaxC` 处理，我们只做纯 M3 角色映射。

### 10.2 结构

| 部分 | 说明 |
| --- | --- |
| 色彩空间 | sRGB ↔ 线性 ↔ XYZ(D65) ↔ CAM16（HCT）|
| 色域映射 | `HctSolver.solveToInt(hue, chroma, lstar)` 单入口求逆；J 上二分（MCU 的牛顿种子在我们的观看条件下会过冲）|
| 六个色族 | `primary` / `secondary` / `tertiary` / `neutral` / `neutralVariant` / `error` |
| 色度策略 | 每族的色度**随所请求色调变化**（锚点表 + 分段线性插值），不是每族常量 |
| 色相策略 | 旋转用 MCU 的 `getPiecewiseHue` / `getRotatedHue` 分段表，不是线性拟合 |
| 角色映射 | 49 个角色 × (色族, light 色调, dark 色调)，遵循 M3 baseline 分配 |

### 10.3 shell 如何引用 Kos.Ui（源码别名）

`shared/qml` 在 CMake 里注册为 QML 模块 `Kos.Ui`（`qt_add_qml_module(kos_ui ... STATIC)`），
由 `apps/` 编译链接使用。但 **shell 不走这条路**：`qs -p shell` 直接读源码，而 Quickshell
既不会把配置目录、也不会把它的父目录加入 QML 导入路径，所以 `import Kos.Ui 1.0` 在源码
运行时永远报 `module "Kos.Ui" is not installed`。

解决办法是仓库里的源码别名 `shell/Kos/Ui/`：

| 组成 | 作用 |
| --- | --- |
| `shell/Kos/Ui/qmldir` | 与编译模块完全相同的类型清单，条目写成相对路径 `colorize/ColorScheme.qml` |
| `shell/Kos/Ui/{colorize,foundation,controls}` | 指向 `../../../shared/qml/*` 的符号链接 |
| `shared/qml/{colorize,foundation}/qmldir` | 让目录内同族类型互相可见（如 `WallpaperColorSource.qml` 里的 `ArtworkColorSource`）|
| shell 各文件 | `import "../../../Kos/Ui"` —— 相对导入，不需要任何环境变量 |

三个必须遵守的约束：

1. **qmldir 条目不能写 `../` 逃出配置根。** Quickshell 会拦截并报
   `Script qrc:/qs-blackhole unavailable`，即使那个路径在磁盘上真实存在。
   因此必须用符号链接，把词法路径留在 `shell/` 内部。
2. **`import qs.Kos.Ui` 同样不可行**（同上，撞 blackhole）。
   `QML_IMPORT_PATH` 倒是能解决，但要求每次启动都带环境变量，不采用。
3. **符号链接只服务于源码运行。** `kosctl install` / `kosctl sync` 会把它们替换成
   真实文件（见 `materialize_kos_ui`），因为拷到 `~/.config/quickshell/kos` 之后
   链接目标已不存在，会变成悬空链接。

这个模式不是新发明的：`shell/shared/qml/controls` 本来就指向
`../../../shared/qml/controls`，这里只是把同一套做法扩展到 colorize 与 foundation。

### 10.4 修改算法时的注意事项

1. **色度表对齐的是 matugen 的 `colors` 表，不是 `palettes` 表。** 两者不同：
   `palettes` 永远是 `scheme-tonal-spot`（不论 `--type` 传什么），`colors` 才是
   按 scheme type 解析后的方案。曾经对着 `palettes` 校准导致偏差卡在 4.1。
2. **色度是色调的函数。** 反解每个色调对应的色度得到的是一条光滑曲线，写进
   `NEUTRAL_CHROMA_ANCHORS` 等锚点表。把它退化成每族常量会让所有表面角色出现
   残差——这曾经是最大的偏差来源。
3. **不要用 HCT 距离单独判断对错。** 色度约 1.2 时色相坐标数值不稳定，1 个
   sRGB 步长能让色相读数摆动 10° 以上、距离算出 13。会掩盖真实错误：曾有一版
   实现输出 `#00fde7` 而 matugen 是 `#bcece3`（188 步），HCT 距离报 2.41。
   **必须同时用 sRGB 字节步长兜底**（测试套件里有 `byte-step sanity` 块，并按色度
   分流度量）。
4. 改动后必须跑 `node tests/color-scheme/test_color_scheme.mjs`——它锁定了参考
   种子 `#64c4d4` 的 33 个角色值、matugen 的 44 个角色逐字节值、表面色调落点、
   色域裁剪的色相依赖，以及确定性。
5. `ColorScheme.qml` 保留 `color(role, darkMode, fallback)` 签名以兼容既有消费点，
   但 `AppearanceTokens` 已不再传 fallback：调色板在单例加载时就会用
   `AppearanceTokens.seedColor`（KDE 强调色）预置，壁纸取色完成后替换。
6. `.mjs` 并没有进编译版 `Kos.Ui`。本节此前声称它们必须列在
   `shared/qml/CMakeLists.txt` 的 `QML_FILES` 中——**这个说法与现状不符**：
   该列表里只有 `foundation/` 和 `controls/`，整个 `colorize/` 目录都不在编译
   模块内。目前不构成故障，因为 `apps/` 只用 `foundation/AppTheme.qml`，而 shell
   走源码运行（`shell/Kos/Ui/qmldir` + 符号链接），由 QML 的相对 import 解析
   `.mjs`。新增文件时因此有两件事要做、一件不要指望：
   - 必须：确认相对 import 的依赖文件都在同目录（`TraditionalColorScheme.mjs`
     依赖 `ChineseColors.mjs`、`JapaneseColors.mjs`、`Cam16Hct.mjs`、
     `MaterialColorScheme.mjs`，漏一个只会在运行时炸）。
   - 必须：`shell/Kos/Ui/qmldir` 同步加条目，否则源码运行找不到类型。
   - 不要指望：加了 `.mjs` 就自动进编译模块。真要给 `apps/` 用，得先把整个
     `colorize/` 目录补进 `QML_FILES`。
   `tests/traditional-color/run.mjs` 用符号链接树在真实 Quickshell 下加载这些
   模块，正是为了覆盖「Node 能跑、QML 加载不了」这一类失败。

### 10.5 中国传统色 / 日系配色

`shellStyle === "material"` 时，设置页在风格卡片下面提供三个配色来源（`materialColorScheme`）：

| 值 | 算法 | 色卡 |
| --- | --- | --- |
| `monet`（默认） | Material You / Monet，见 10.1–10.4 | — |
| `chinese` | `TraditionalColorScheme.mjs` | 526 个中国传统色 |
| `japanese` | 同一算法 | 228 个日本传统色 |

**为什么需要它。** Monet 保色相、不保色调。用本仓库的实现实测：主色与种子的色相
偏差全部 < 1°，但明度被强制改写——浅色模式固定压到 tone 40（实测压暗 23–46 个
tone），深色模式固定抬到 tone 80（抬亮 32–64）。`#1a2847`（深藏青）在深色模式
变成 `#b0c6ff`，Δ明度 63.6；表面色一律被去彩到 chroma ~2，不同壁纸拿到同一套
灰。用户感到的「跟我壁纸完全不是一个色」几乎全部来自这里，而不是色相。

**做法。** 种子色在 HCT 空间吸附到色卡最近邻，基准色直接取该色卡色本身，不再
重新上色调：

1. **是否比较色相只看种子**（`NEUTRAL_CUTOFF = 2.5`）。早先版本改成「任一侧近
   中性就丢弃色相项」，等于给色卡里的灰色免考：`#1a2847`（chroma 5.9）因此匹配
   到色相 3° 的低彩度灰，而不是色相 269° 的 钢青（距离 0.084 对 0.141）。改成
   只看种子后，低彩度色卡色仍要站在色环正确的位置上。
2. **色相项权重 4.0 对彩度 1.0。** 权重低时 `#7fecad` 会为 2.5 的彩度差放弃 6°
   的色相优势，去选 16° 之外的色。
3. **`primary` 两个模式都用该色卡色**，`on_primary` 按该色**真实明度**在两个
   方向试探，直到满足 4.5:1，而不是套用 M3 固定的 100/20——传统色可以是
   tone 8（墨）也可以是 tone 95（月白），固定前景必然有读不清的组合。
4. `secondary` / `tertiary` / `error` 同样保真；容器与 `on_*_container` 由基准色
   的色相彩度派生。曾经只让 `primary` 保真、其余走 M3 色调，结果 `on_secondary`
   落在 `secondary` 上只有 1.70:1。
5. **表面角色从色卡的低彩度色（chroma < 6）里按色调取**，浅色主题因此落在
   象牙白/月白系、深色主题落在玄/墨系；同一色调恒定映射到同一色，`surface` 与
   `background` 不会因为调用先后而分叉。
6. **色卡无法表达种子时整套回退莫奈**（色相差 > 42°、明度差 > 22、或彩度落差
   > 34），`variant` 一并转发，输出与直接调用 `MaterialColorScheme` 逐字节相同。

**实测**（600 个覆盖 HCT 空间的种子；`tests/traditional-color/test_traditional_color.mjs` 锁定这些数字）：

| 指标 | 传统色 | 莫奈 |
| --- | --- | --- |
| 主色与种子的 Δ明度（平均） | **1.4** | 17.6 |
| 匹配色相误差 p50 / p90 | 5.3° / 14.3° | — |
| 前景对比度不达标次数 | **0** | — |
| 回退莫奈比例 | 0/500 | — |

回退率接近 0 是因为色卡在色相上几乎连续。兜底条件仍被测试**直接驱动**（注入一张
单色色卡）——否则它会悄悄变成死代码。

另有一条实测事实值得记住：sRGB 在 HCT 空间的彩度上限约 27（tone 50 时 hue 0 为
24.8、hue 180 为 10.7），而两份色卡也在 0–27 内，所以「彩度落差过大」这一条在现
有色卡下永不触发。保留它是为了色卡或色彩空间放宽时仍然正确。

**表面着色（让切换看得见）。** 只让 `primary` 保真是不够的：`material` 形态的大面积表面来自 `layer0..4`，而它们原先在浅色模式下几乎不着色（`layer0` 只混 1%，`layer1..4` 完全不混），深色模式也只混 7–12%。实测后果是切换配色来源时 Dock 底色从 `#eefafe` 变到 `#ecf5f0`——两个都是近白，用户完全看不出区别。

现在 `layer0..4` 在两种外观下都按主色着色：`layer0` 为浅色 0.20 / 深色 0.30，逐级递减到 `layer4` 的 0.11 / 0.18。这些数字是定标出来的，不是拍的——在 200 个种子 × 2 方案 × 2 模式上最差的正文对比度是 5.71:1（要求 4.5:1），再上一档（0.40）掉到 4.0:1 因此被否掉。`tests/traditional-color/test_traditional_color.mjs` 会**从 `AppearanceTokens.qml` 源码读出这些比例**再复算对比度，并断言一次配色来源切换至少能把 Dock 底色移动 8/255（中位数实测 14/255），防止再次出现「数值合法但看不见」的情况。

Dock 以 `dockOpacity 0.50` 绘制，屏幕上只留下一半着色——这是着色值必须高于「看起来合理」的原因。Bar 融合进 Dock（`barIntegratedWithDock`）时同理。

这些比例必须声明在 `AppearanceTokens` **singleton 自身**上，不能放进嵌套的 `colors` 对象。曾经把它们定义在 `colors` 内部、却用 `tokens._layerTint0` 引用（正确路径是 `tokens.colors._layerTint0`），路径解析成 `undefined`，`_mix` 里 `(tint.r - base.r) * undefined` 得到 NaN，于是 `layer0..4` 全部变成 `Qt.rgba(NaN, NaN, NaN, 1)`。无效颜色渲染为黑：**卡片文字立刻不可读**；而同一个坏值在任何配色来源下都相同，所以**切换看起来毫无作用**，只有直接用 `primary` 的 DeskCenter 圆环还在正常变色——三个症状同源。`tests/traditional-color/run.mjs` 现在会真正实例化 `AppearanceTokens`（而不仅是 `ColorScheme`），断言这些比例可解析、五个 layer 都是有效颜色、且随配色来源变化。

**Canvas 消费者需要一个统一信号。** 逐帧读取配色的组件（DeskCenter 的时钟指针、CPU/内存圆环）只在显式 `requestPaint()` 时重绘，而它们原来的重绘清单只覆盖日期、指标和图标染色——切形态（material → macos）或切配色来源时，指针与圆环会停在旧颜色上。因此 `ColorScheme` 暴露 `revision`（每次重建递增），`AppearanceTokens` 转发为 `colorRevision`，Canvas 只需监听这一个信号。`tests/traditional-color/shell.qml` 断言它确实递增。

**色卡来源与许可。** `ChineseColors.mjs` 取自 zhongguose.com 的公开色表；
`JapaneseColors.mjs` 取自维基百科 *Traditional colors of Japan*（CC BY-SA 4.0，
再分发需署名）。两份都只保留「色名 + hex」并做同色值去重，是纯数据——换表、裁剪
表都不需要改算法。

**原色与派生（实测每个模式 49 个角色）。** 约 **27 个是色卡原色**（有色名可查），其余围绕它们派生；两种模式合计原色占比：中文 **56.3%**、日系 **46.7%**：

| 角色 | 来源 |
| --- | --- |
| `primary` / `secondary` / `tertiary` / `error` 及对应 `*_fixed` | **色卡原色**——灰蓝 / 沙鱼灰 / 牛角灰 / 殷红 |
| `*_container` | **色卡原色**——云峰白 / 淡藤萝紫 / 淡肉色（色相跟随基准色，明度落在 90 / 30） |
| `surface*` / `background` / `on_surface` / `outline*` / `surface_variant` / `inverse_*` | **色卡低彩度原色**——月白 / 银白 / 艾背绿 / 云峰白 / 嫩灰 |
| 全部 `on_*` 前景、`*_fixed_dim`、`inverse_primary`、`surface_tint` | 派生：由基准色的色相与彩度算出，hex 不在色卡中 |

container 的搜索由**明度主导**（先满足 tone，再比色相，彩度只用于打破平局）——这个角色一旦偏离自己的层级就会破坏 surface 排序；色卡里找不到接近落点时退回派生。实测 container 与 primary 的色相差 < 2.1°，同族关系没有因为改取原色而变松。`on_*_container` 的前景跟随 container 的**实际**颜色计算对比度，与 accent 的处理一致。

派生不是偷懒。M3 的 49 个角色之间存在层级与对比度约束，而色卡是 526 个离散色，不可能为每个角色都提供位置合适的色；基准色保真、其余派生，才能同时满足「贴壁纸」与「container 与 primary 同族、`on_*` 对底色达标」。

> **修正记录：** `error` 一度全部是派生的。原因是我把它的请求彩度写成 M3 的 60，而 sRGB 在 HCT 中最大彩度约 27，`acceptMatch` 因此拒绝了每一个候选并静默退回派生。改成 25 后它解析为 殷红 / 丽春红 这类真实传统红，原色占比从 46.9% 升到 49.0%。

**已知限制。** 传统色没有官方明暗对偶表：`*_fixed*` 按「两模式同色」处理（与 M3 的 fixed 语义一致）。设置页只显示主色的色名；色卡稀疏导致回退时显示「已回退莫奈」。

### 10.6 Material 的卡片表面与花瓣轮廓

Material 形态有自己的一套卡片表面组件 `MaterialCardSurface`，桌面七张卡全部走它；液态玻璃形态继续走 `ControlCenterCard` + `LiquidGlassPanel`。两者对 KWin 的索取完全不同：

| | glass（macos / windows12） | Material |
| --- | --- | --- |
| 卡片表面 | KWin 画（`LiquidGlassPanel`，`fallbackEnabled: false`） | 卡片自己画（QML tonal 填充） |
| 向 KWin 声明 | 每张卡一个 `SurfaceShape` | **一个都不声明** |
| blur region | 面板的圆角矩形区域 | **每张卡各自的轮廓**（圆角矩形 / 花瓣） |
| 合成器效果 | 液态材质：模糊 + 折射 + glints + noise | 普通 blur 管线：纯磨砂 |

**液态材质的开关是「有没有声明形状」，不是「是不是 Quickshell 窗口」**——`blur.cpp` 里：

```cpp
const bool usesGlobalQuickshellMaterial = isQuickshellWindowSurface
    && !declaredSurfaceShapes.isEmpty();
```

Material 卡一律不声明 `SurfaceShape`：`DeskWidgetCard` 只实例化**当前形态的后端**（`Loader`），Material 下根本不创建 `ControlCenterCard`，所以窗口一份声明都没有，KWin 在 `shapesFor()` 里也就没有这个 surface。整个窗口于是退回普通 blur 管线——没有折射、没有 glints、没有 liquid noise。这就是两种形态观感差异的来源：同一个 `DeskCenterWindow`，glass 下每张卡都声明形状、整窗走液态材质；Material 下一张都不声明、整窗只有模糊。

**两张形态是怎么统一的。** 全链路只有三处知道形态，而且边界不重叠：

| 层 | 职责 | 位置 |
| --- | --- | --- |
| 形态策略 | 要不要背景、用哪个后端、谁画漆 | `AppearanceTokens.surface`：`treatment` / `cardBackend` / `paintInQml`。加一种形态就是在这里加一行映射 |
| 表面出口 | 每个后端只承诺一个 `blurRegion` | `DeskWidgetCard`（`Loader` 选后端）→ `DeskCenterWindow`（七张卡的 region union 成一个窗口 `BackgroundEffect`） |
| 合成器材质 | 声明了形状 → 液态；一个都没声明 → 磨砂 | `blur.cpp` 的 `usesGlobalQuickshellMaterial` |

QML 只决定几何与漆，合成器只决定材质。卡片和窗口都不判断当前是哪种形态——`DeskWidgetCard` 里 `AppearanceTokens.isMaterial` 出现次数为 **0**。

**画内容的人只需要认识一个出口。** widget 内部的绘制也不判断形态，而是问 `AppearanceTokens.content`：

| 需求 | 写法 |
| --- | --- |
| 卡片背后有没有背板（墨色能不能直接压在壁纸上） | `AppearanceTokens.content.onBackdrop` |
| 墨色 / 带透明度的墨色 | `AppearanceTokens.content.ink("#7d7782")`、`ink("#7d7782", 0.72)` |
| 语义强调色：Material 用主题角色，其它形态用墨或 widget 自己的色 | `AppearanceTokens.content.accent(AppearanceTokens.colors.tertiary, "#30d158")` |

这三个在两种形态下与原三元表达式**逐字段等价**（`content.onBackdrop` 就是原来各 widget 自己重复声明的 `glassMode`），所以把 `glassMode ? … : …` 换成它们不会改观感。`DeskCenterWindow` 里原本 109 处形态判断，其中 81 处收进了 token（`ink` 44、`onBackdrop` 20、`accent` 7、`pick` 10）。

**这套契约覆盖整个 shell，不只是桌面卡片。** 所有面板与弹层 —— Dock、Bar、控制中心、WiFi / 蓝牙列表、通知、右键菜单、启动器、快速搜索、Overview、天气弹层 —— 都通过 `LiquidGlassPanel` 取表面，而它在 tonal 形态下**保留模糊区域、去掉 `SurfaceShape` 声明**（`shapeEnabled: … && !root.tonal`）。这一行让 23 个消费者同时从液态玻璃切到纯磨砂，各自的 `blurRegion` 出口不变；面板族的其它形态差异（颜色、圆角、弹出动效、Dock 时钟的装饰面）由 `surface.pick(tonal, glass)`、`content.*` 和 `motion.popupAnimatesOnShow` / `motion.drawsFormDecorations` 表达。

于是**全仓只有两个地方还认识形态名**：`AppearanceConfigService`（形态与预设的定义处）和 `AppearanceTokens`（policy 本身）。除此之外仅剩 `DeskCenterWindow` 的 7 处语句/布局分支（Material 与玻璃是两套设计，例如表盘配色与列表布局）和 `IconAppearanceService.glassContentColor`（墨色的实现点）。

`MaterialCardSurface` 同时提供**漆层**和**轮廓区域**，七张卡共用一套参数：同一个 `fillColor`（`layer1`）、同一个 `fillOpacity`（`widgetOpacity`）、同样 `border.width: 0`、同样没有描边。时钟只是把轮廓换成花瓣——填充色、不透明度、磨砂与其它卡逐字段相同，**形状是唯一的差别**。花瓣之外直接透出壁纸（没有任何矩形材质板），磨砂只裁剪花瓣内容区。宿主用 `DeskWidgetCard.flowerShapedSurface: true` 声明这一点（`DeskCenterWindow` 只对 `clock` 传），组件里不写死任何 widget 名字。

漆层与时钟的表盘是两层：`MaterialCardSurface` 画表面（花瓣填充 + 花瓣区域），`DeskCenterWindow` 的内容层只加表盘与倒计时。时钟**不在内容层再画一遍花瓣**——那正是它此前看起来是另一张卡的原因（自己的颜色、自己的 0.34 不透明度、自己的 1px 描边）。

`FlowerBlurRegion` 的路径选择：

| 方案 | 结论 |
| --- | --- |
| 若干个 `RegionShape.Ellipse` 摆成花瓣 | **不可行**。`Ellipse` 是轴对齐的，而十二个瓣是径向分布的，摆不出这个形状；用内切圆代替则模糊范围比花瓣小得多 |
| 用 `Intersection`（Combine / Subtract / Intersect / Xor）拿圆拼出正弦瓣 | **不可行**。正弦瓣不是任何有限圆组合的结果 |
| JS 动态生成矩形列表塞进 `Region.regions` | **不可行**。`regions` 是 `readonly` 的 `list<PendingRegion>`，只能靠声明子项填充 |
| 扫描线填充 + 固定槽位 | **采用**。`Region` 的 `defaultProperty` 就是 `regions`，所以静态声明 64 个 `Region` 子项，每个绑定到预算好的扫描线段 |

几何与 `MaterialFlower` 同源：`r(θ) = R · (1 − A + A·sin(lobes·θ))`，`R` 由 `(min(w,h) − inset) / 2 − outlineInset` 得出；`inset: 18` 必须与 `MaterialCardSurface` 画花瓣时留的边距一致，否则磨砂边缘落不到轮廓上。

每行最多两次穿越——最小半径是 `R·(1−2A) = 0.85R > 0`，形状中心恒为实心——所以「每行 2 槽位」是**精确**表达而非近似。实测区域覆盖轮廓面积的 **100.18%**，缺口只来自行的量化。改 `sliceCount` 时必须重新生成那 64 个子项：槽位是静态声明的，行会静默丢失而不是报错。

## 11. 验证清单

```bash
qmllint -I shared/qml -I shell -I . apps/settings/main.qml
qmllint -I shared/qml -I shell -I . \
  shell/desktop/modules/common/AppearanceConfigService.qml \
  shell/desktop/modules/common/AppearanceTokens.qml \
  shared/qml/colorize/ColorScheme.qml
node tests/color-scheme/test_color_scheme.mjs
node tests/traditional-color/test_traditional_color.mjs
node tests/traditional-color/run.mjs
node shell/desktop/modules/dock/test_wallpaper_color_source.mjs
node shell/desktop/modules/dock/test_adaptive.mjs
node shell/desktop/modules/dock/test_autohide.mjs
# 无显示环境下编译 QML 模块需把 TMPDIR 指到大分区，/tmp 常为小容量 tmpfs
TMPDIR=$PWD/.build/tmp cmake --build .build/apps-dev --target kos_ui
# 源码运行链路（不设任何环境变量；无显示时用 offscreen 平台）。
# 加载链走完 = 只剩 "No PanelWindow backend loaded"，那是缺少合成器，不是代码问题。
QT_QPA_PLATFORM=offscreen quickshell --path shell --no-color
node tools/qml-duplicate-handlers.mjs   # 同一对象内重复 Component.onCompleted 等
git diff --check
```

运行验证需按 `.agents/skills/verify/SKILL.md` 启动独立 Quickshell 实例，确认 `Configuration Loaded`，检查新错误后只停止该验证实例。IPC 测试切换三个枚举后必须恢复测试前的 `shellStyle`，不得改动用户玻璃强度。

> 注意：`tests/date-projection` 与 `shared/qml/test_visual_contract.mjs` 依赖
> `qmltestrunner`，在无显示环境下无法运行（`qmltestrunner` 静默退出码 1）。
> 这两项失败是环境限制，不是回归。

## 12. AI 接续检查表

开始后续外观工作前，AI 应依次：

1. 阅读本文。
2. 检查工作区未提交修改，避免覆盖用户正在开发的 Dock/Bar/桌面文件。
3. 读取当前运行时 snapshot，不猜测用户选择。
4. 一次只让一个主要 surface 消费 Token，并保留原业务行为。
5. 运行静态、构建、单元和独立 Quickshell 验证。
6. 更新本文的状态、Token 表和已接入组件列表。
