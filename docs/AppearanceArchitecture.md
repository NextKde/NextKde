# 全局外观系统架构

> 状态：Dock 形态、Bar 布局/隐藏、全局图标外观、Glass 预设/同步、Dock 窗口动画与 Material 3 配色已实现（更新至 2026-09-17）。本文是后续开发和 AI 接续工作的规范来源。

## 1. 当前能力与边界

外观设置分为彼此正交的维度：

- **系统外观**：`kos-settings > 显示 > 色彩模式` 优先应用 KDE 的 `Breeze / BreezeDark` Look-and-Feel，失败时回退到 `BreezeLight / BreezeDark` 色彩方案。目前不写入本项目配置。
- **Material 3 配色**：壁纸主色作为种子，在进程内生成全套 M3 角色色。算法是 matugen `scheme-vibrant` 的纯 JS 移植，**不需要安装 matugen、Python 或 ImageMagick**。配合 Quickshell 内置 `ColorQuantizer` 完成取色，全链路无外部进程。详见第 10 节。
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
| `shared/qml/colorize/ColorScheme.qml` | 单例。接收种子色，产出 49 个 M3 角色 × light/dark。纯同步计算，不启动任何进程 |
| `shared/qml/colorize/MaterialColorScheme.mjs` | 角色→色族/色调映射、各族随色调变化的色度曲线、变体（vibrant / tonal-spot）的色相旋转表 |
| `shared/qml/colorize/Cam16Hct.mjs` | CAM16/HCT 色彩外观模型。MCU 的 `hct/*.ts`、`viewing_conditions.ts`、`hct_solver.ts` 移植版，对外提供 `hexToHct` / `hctToHex` |
| `shell/desktop/modules/common/IconAppearanceService.qml` | 全局图标模式、不透明度、染色与旧 Dock 配置迁移 |
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

schema 26：

```json
{
  "version": 26,
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
  "glassFollowsAppearanceMode": false,
  "barIntegratedWithDock": false,
  "barVisibilityMode": "always",
  "barLayoutMode": "transparent",
  "dockWindowAnimationStyle": "scale"
}
```

- 每个玻璃预设还持久化 `Refraction`、`EdgeSize`、`NormalPow`、`RGBFringing`、`OffsetStrength`、`Softness` 和 `Reflection`；示例只列出代表字段。预设参数均由范围表校验，不能以手改配置绕过设置页的有效范围。
- 默认 `glassStyle` 为 `liquid`，`shellStyle` 为 `macos`，`barLayoutMode` 为 `transparent`，`themeMode` 为 `system`（合法值 `system` / `light` / `dark`）。切换玻璃样式会应用该样式的完整预设；Material 使用独立的模糊预设且禁用液态折射。
- schema 1–10 完成早期全局强度、Shell/Bar/主题迁移；v16 起为每种玻璃样式保存独立预设，v17–v24 多次校准 soft/frosted 的默认光学值，v26 将液态预设的旧 body lens 默认值迁移为 0。读取旧文件后会写回 schema 26。
- 非法或缺失的 `shellStyle` 回退为 `macos` 并写回；非法或缺失的 `dockWindowAnimationStyle` 回退为 `scale`；非法或缺失的 `themeMode` 回退为 `system`；非法强度不会覆盖内存默认值。
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
6. `.mjs` 必须列在 `shared/qml/CMakeLists.txt` 的 `QML_FILES` 中，否则不会打进
   `Kos.Ui` 模块资源。`MaterialColorScheme.mjs` 依赖 `Cam16Hct.mjs`，**两个都要
   列出**（相对 import 在打包后由 QML 模块解析，漏一个会在运行时才炸）。

## 11. 验证清单

```bash
qmllint -I shared/qml -I shell -I . apps/settings/main.qml
qmllint -I shared/qml -I shell -I . \
  shell/desktop/modules/common/AppearanceConfigService.qml \
  shell/desktop/modules/common/AppearanceTokens.qml \
  shared/qml/colorize/ColorScheme.qml
node tests/color-scheme/test_color_scheme.mjs
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
