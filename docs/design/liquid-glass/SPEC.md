# 液态玻璃规范 v1.1（第 0 批续 R5）

> 事实基础：同目录 `INVENTORY.md`（R1 四源盘点 + R3 补全 §4–§11 + R5 §12）。
> 所有 `文件:行` 出处沿用已核对引用，本文档不引入未经盘点的新事实。
> v1 相对 v0 的变化：补入 Apple HIG 硬约束、字阶/间距 token（R3 §8 实测）、
> 深浅 tint 实测对照（R3 §9）、关闭 4 项工程可查项（R3 §10）、
> 组件 API 扩到 13 个、待人工裁定收敛到 5 项。
> v1.1 相对 v1 的变化：组件 API 扩到 16 个（+GlassSlider/GlassSwitch/GlassNavBar
> 容器契约，R5 §12 盘点）；关闭 weather tint 公式与 scrim 下发链路两项工程项
> （R5 §12.5，回填 §1.1/§1.4）；§7 待人工裁定收敛到 3 项。
>
> 决策纪律：凡能由 HIG 数值或现有代码决定的，本文直接定值（标「定案」）；
> 标「v1 提案」的是在现有值之间做收敛选择，无需人工参与；
> 只有「视觉等价但产品语义不同」的才进 §7（≤3 项）。

## 1. 三层材质模型（沿 v0，定案）

| 层 | 内容 | 依赖 | 适用范围 |
|---|---|---|---|
| **A 纯 QML** | tint + 高光 + 描边 + 阴影，自绘完成 | 无 | **默认**。所有组件必须至少具备 A 层，在无 B/C 时独立成立 |
| **B 窗口级模糊** | 合成器模糊（KWin glass-effect / SurfaceShape v4）或 QML fallback | 一个窗口/面板宿主 | **每窗口/面板至多一次** |
| **C 折射** | KWin `RefractionSettings`（`kwin/glass-effect/src/settings.h:69-72`） | B 层 + effect 在跑 | 仅 §1.3 白名单表面 |

### 1.1 B 层入口（定案）
- shell 侧一律经 `LiquidGlassPanel`（radius 0 + 蒙版切割，`LiquidGlassPanel.qml:33-131`）
  或其配方封装 `ControlCenterGlass`（`ControlCenterGlass.qml:9-21`）；
  禁止直用底层 `RoundedBlurRegion.qml`（统一从带 SurfaceShape 声明的
  `KosRoundedBlurRegion.qml:12-97` 进）。
- Panel 型（宿主窗口，radius 0）与 Surface 型（表面内收尾，radius 跟随，
  `LiquidGlassSurface.qml:9-14`）不混用。
- bar 面板现状：走 `ControlCenterGlass` 的仅 ControlCenterCard /
  NotificationHistoryCard / NotificationHistoryPane / StatusTooltip / SysTray；
  Battery/Bluetooth/Network/NetworkTraffic/StatusCollectionPopup/TemperatureSensorPopups
  直用 `LiquidGlassPanel`/`KosFloatPanel`（INVENTORY §10.3）。
  **定案：直用 LiquidGlassPanel 的面板逐步迁到 ControlCenterGlass 配方**；
  KosFloatPanel 路线（layer-shell 单表面）保留给模态浮层。
- **weather 迁移定案**（R5 §12.5 已核实公式）：weather 卡片（白天深蓝
  `rgb(0,96,210)`@0.30 / 夜间白@0.16，`Main.qml:33-35`）可迁 GlassSurface——
  参数一一映射 tint/tintStrength/radius 16（=card 档）；但 tint 是场景驱动
  （白天/夜间），须作显式 tint 传入，不走 token 默认深浅。滚动边缘 MultiEffect
  （`Main.qml:1330-1337,1362-1369`）模糊的是自身内容非 backdrop，**不迁**，
  保留为独立滚动边缘模式。

### 1.2 C 层折射（定案）
- kwin 默认值已实测（INVENTORY §10.1）：`RefractionStrength 0.0`、
  `RefractionNormalPow 2.0`、`RefractionEdgeSize 20.0`、`RefractionRGBFringing 1.0`、
  `RefractionOffsetStrength 0.0`（`blur.kcfg:122-147`，换算 `settings.cpp:89-95`）
  —— **折射默认关闭**。
- 白名单：中央控制面板、通知中心、锁屏时间卡片；白名单外忽略折射参数。
- `useKwinEffect=false` / QML fallback 时静默降级 B→A。

### 1.4 scrim 单一来源（R5 已核实链路，定案）

- `scrimEnabled/scrimLevel` 是**合成器侧 shader 机制**，不是 QML 背板。链路
  （INVENTORY §12.5）：`LiquidGlassPanel.qml:132-181`（preset 表：readable .72/1.0、
  balanced .47/.75、transparent .22/.5、subtle .15/.45）→ `:239-246` 转发
  KosRoundedBlurRegion → `KosRoundedBlurRegion.qml:77-83` SurfaceShape →
  Wayland 协议 v3 `set_scrim`（`surfaceshapemanager.h:29-34`）→ KWin shader
  uniform（`blur.cpp:195-199`；adaptive=decay≤1.0 按背景亮度采样，fixed=decay 2/3/4）。
- QML 侧仅有两条独立变暗路径，触发条件不同：`adaptiveDarkScrim`（默认 false，
  `LiquidGlassPanel.qml:127,283`）与 tonal/paintInQml 自绘 fallback（:260）。
  「合成器 scrim × QML 自绘」同开是唯一潜在双重变暗组合，需宿主显式 opt-in。
- **定案：默认路径单一（compositor scrim）；GlassDialog/GlassPopover 等 spec 中
  「scrim 单一来源 = compositor」契约成立，无需重议。**

## 1.5 Shell 内场景采样

Gallery 与应用组件 Demo 已迁至
[nextkdeAppDemo](https://github.com/NextKde/nextkdeAppDemo)。主项目保留 Shell 自身的
`GlassBackdrop`、`LiquidGlassSurface`、`LiquidGlassPanel` 与 `scene_liquid.frag(.qsb)`。

- 宿主通过 `GlassBackdrop.sourceItem` 声明同一窗口内的采样源；表面也可显式设置
  `backdropItem`。`null` 不启用场景采样。该机制不能捕获桌面或其他应用窗口。
- `LiquidGlassSurface.sceneSampling` 控制采样路径；`ShaderEffectSource` 以表面
  1/6 尺寸、`hideSource: true`、`live: true` 捕获，`scene_liquid.frag` 执行模糊、
  着色、scrim 与裁剪。独立弹窗需要本窗口内的采样源。
- scrim preset 经 `GlassBackdrop.scrimCap/scrimDecay` 解析：readable 0.72/1.0、
  balanced 0.47/0.75、transparent 0.22/0.5、subtle 0.15/0.45。
- `LiquidGlassPanel.backdropItem` 默认接 `GlassBackdrop.sourceItem`。删除 Demo
  不改变 Shell 的 KWin 接入，也不将 Shell 自动切换到独立仓库的纯 QML 实现。

## 2. Token 表 v1

Token 宿主：shell 玻璃体系 = `AppearanceTokens`（`AppearanceTokens.qml:17-94`）；
应用内色板 = `AppTheme`（`KosSurface.qml:6-7`）。**定案：玻璃组件的色值出口
统一走 AppearanceTokens；AppTheme 保留为应用内普通（非玻璃）表面色板，
迁移时按 §9 对照表映射**——不作为人工裁定项。

### 2.1 材质三档 × 浅/深

| 档 `material` | 用途 | tintStrength | 模糊等级(KWin) | opacity/reflection scale |
|---|---|---|---|---|
| `clear` | tooltip、贴边浮条等小面积最透表面 | 0.10（v1 提案） | 1..5，默认 3（v1 提案） | 0.58 / 0.62（`LiquidGlassSurface.qml:60-62`，定案） |
| `regular` | 面板/卡片默认 | 0.16（listenfree `GlassSurface.qml:10`，定案） | 6..10，默认 8（v1 提案） | 0.44 / 0.48（v1 提案） |
| `thick` | 菜单/弹层/对话框/toast | 0.24（v1 提案） | 11..15，默认 12（v1 提案） | 0.32 / 0.36（v1 提案） |

> 迁移注记：`ControlCenterGlass` 现为 material regular + KWin level 1
> （`ControlCenterGlass.qml:9-21`）；迁移到上表后 small 面板应改标
> `clear` 或按 regular 默认 8 提升。属机械迁移，不需裁定。

**浅/深色值（实测，非提案）**：shell 玻璃的深浅差异不是独立色值——
`baseColor` 恒为 `rgba(0,0,0,0.1)`（`LiquidGlassSurface.qml:16`、`LiquidGlassPanel.qml:115`），
深浅由环境光混合（`baseColor×0.72 + ambient×0.28`，`LiquidGlassSurface.qml:69-71`）
与 scrim 决定；mac 平台例外 tint 浅 `#F5F5F7` / 深 `#1D1D1F`
（`AppearanceTokens.qml:496-497`）；玻璃前景恒白 `rgba(1,1,1,0.78)`
（`AppearanceTokens.qml:333`）。应用内 tint 角色对照（R3 §9.1，`AppTheme.qml:106-120`）：

| 角色 | 深色 | 浅色 | 用途 |
|---|---|---|---|
| cardStrong（GlassSurface tint） | `#f02d3740` | `#f2ffffff` | :116 |
| card | `#e629323a` | `#dff7f8f9` | :115 |
| control / controlHover | `#b937424c` / `#e0495661` | `#c8f6f6f6` / `#efffffff` | :117-118 |
| selected | `#30ffffff` | `#22000000` | :120 |
| textPrimary/Secondary/Muted | `#f3f6f8`/`#bdc6cd`/`#89959f` | `#20262b`/`#68747c`/`#858d93` | :112-114 |
| ComboBox sheet（ LiquidSelect.qml:29） | `#262b31` | `#f6f8fb` | 弹层底 |

### 2.2 圆角（定案三档 + 形状档）

| Token | 值 | 依据 |
|---|---|---|
| `radius.panel` | 32 | `KosFloatPanel.qml:45` |
| `radius.surface` | 24 | listenfree `GlassSurface.qml:10` |
| `radius.card` | 16 | `MaterialCardSurface.qml:25` |
| `radius.pill` | `height/2` | `ActionFeedbackToast.qml:28`、`LiquidSelect.qml:35`、`NotificationHistoryPane.qml:212` |
| `radius.small` | 10 | `AppearanceTokens.qml:249-252`（shape.small，用于 tooltip/输入框等收编 7/6 散值） |
| `cornerExponent`（玻璃系） | 2.0 | `LiquidGlassPanel.qml:33`、`KosRoundedBlurRegion.qml:12-97`；`AppearanceTokens.qml:281` 的 3.0 归非玻璃普通形状体系 |

废值：SessionMenu 卡片 14 / item 9（`SessionMenu.qml:147,269`）、
WallpaperValueMenu 17-19（`WallpaperValueMenu.qml:92-119`）、
MusicEditorDialog 16/20/24 混用（`MusicEditorDialog.qml:131,231,241`）、
WallpaperOptionsDialog 18/22（:21,55）→ 全部归并上表。

### 2.3 阴影与描边（定案两档）

| Token | 浮层级（dialog/popover） | 卡片级（玻璃卡片） |
|---|---|---|
| 阴影 opacity / offset / softness | 0.30 / 12,16 / 18（`KosFloatPanel.qml:45-76`） | 0.16 / 5,7 / blurMax 16（listenfree `GlassSurface.qml:30`） |
| 实现 | MultiEffect 合并渲染（唯一实现；废 KosCardShadow 自绘与 EventDetailsPopover shadowInset 内绘，`EventDetailsPopover.qml:64-69`） | 同左 |

| 描边 | 值 | 依据 |
|---|---|---|
| `strokeWidth` | 1 | `KosSurface.qml` |
| 控件描边 alpha | 深 0.16 / 浅 0.12 | `LiquidSelect.qml:30` |
| 弹层描边 | Material 档 0.30 | `AppearanceTokens.qml:549` |

### 2.4 字阶（HIG 硬约束，不允许自创档位）

Apple HIG 文本样式：LargeTitle 26/32、Title1 22/26、Title2 17/22、Title3 15/20、
Headline 13/16 Bold、Body 13/16、Callout 12/15、Subheadline 11/14、
Footnote 10/13、Caption 10/13；正文 13pt，**最小 10pt**。

现有值归并（R3 §8.1 实测全部值）：

| 现值（出处） | 归并到 |
|---|---|
| 24（MusicEditorDialog:173）、21（AlertDialog:78）、19（MusicDialog:20） | Title1 22/26（弹层标题） |
| 17（NotificationHistoryCard:187）、16（WallpaperOptionsDialog:29） | Title2 17/22 |
| 18（NotificationHistoryEntry:164）、15 | Title3 15/20 |
| 14（SettingsCheckBox:35）、13（ContextMenu:132、LiquidSelect:200、GlobalMenu:39、SegmentedTabBar:79 等） | Body 13/16 |
| 12（StatusTooltip:63、ActionFeedbackToast:57 等） | Callout 12/15 |
| 11（DockAppNameTooltip:85、NotificationHistory 121/135/144 等） | Subheadline 11/14 |
| 10（StatusTooltip:70、NotificationHistoryCard:199） | Footnote 10/13 |
| **9（NotificationHistoryEntry:108）** | **违规，迁 Footnote 10**（HIG 最小 10pt） |
| SessionMenu 字号=`itemHeight*0.34`（:286） | **比例字号废除**，按用途取固定档 |

权重：Headline 态用 Bold；DemiBold/Medium 归并为 SemiBold/Medium 两档
（现混用于 StatusTooltip:63/:70、GlobalMenu:40、ActionFeedbackToast:58 等，
作为 token 收敛，标 v1 提案）。字族不得硬编码 `"Noto Sans CJK SC"`
（现硬编码于 StatusTooltip:63、DockAppNameTooltip:84）→ 走主题默认字体。

### 2.5 间距

| Token | 值 | 依据 |
|---|---|---|
| `space.xs` | 4 | 高频实测：NotificationHistoryCard:135、StatusTooltip:57 |
| `space.sm` | 8 | SessionMenu:138、SettingsTransferDialog:25、WallpaperOptionsDialog:51 |
| `space.md` | 12 | HIG「带边框控件周围约 12pt」+ dialogs 表单（EventEditorDialog:170 等） |
| `space.lg` | 20 | MusicDialog:7、KosFloatPanel contentPadding:20 |

废值归并：1/3/5/6/7/9/10/14 → 就近档（6→4 或 8 按视觉密度，14→12）。

### 2.6 可达性硬约束（HIG，定案）

- 对比度：≤17pt 文本 ≥4.5:1；≥18pt 或粗体 ≥3:1。
- 命中区：默认 28×28，最小 20×20（SettingsCheckBox 20×20，`SettingsCheckBox.qml:10-11`，达标）。
- 仅键盘可完成全部操作；不得只靠颜色传达状态（focus 环 + 勾选图形必配）。
- 支持 Reduce Motion（见 §2.7）；尽量少用定时自动消失（Toast 例外，见 §7-①）。

### 2.7 动效

| Token | 值 | 依据 |
|---|---|---|
| `fast / normal / slow` | 135 / 200 / 360（glass 档） | `AppearanceTokens.qml:553-557` |
| popup open / close | 150 / 140 | `AppearanceTokens.qml:568-569` |
| popup startScale / anchorOffset | 0.96 / 20 | `AppearanceTokens.qml` 同处 |
| 弹层缓动 | open=OutCubic / close=InCubic，时长按剩余进度等比缩放 | `PopupMotion.qml:9-11,46-57` |
| 液态按压 expansion | pressed 1.0 / hovered 0.3 / idle 0，进 token，删控件内硬编码 | 现 `LiquidGlassButton.qml:25` |
| slider expansion / x 跟随 | pressed 270 OutBack / 释放 460 OutQuint / x 200 OutQuint | `LiquidSlider.qml:64-70,245-250`（R5 收进 token） |
| switch thumbX / expansion | 200 OutCubic / pressed 120·释放 200 | `LiquidGlassSwitch.qml:71-84`（R5 收进 token） |
| 环境光过渡 | 2600，收进 motion token | 现 `LiquidGlassSurface.qml:45`、`LiquidGlassPanel.qml:119` |
| tooltip 显隐 | 70ms（= fast 档内短反馈，保留现值） | `StatusTooltip.qml:27-28` |
| toast 存留 | 2600ms（悬停暂停，离开按剩余继续） | `ActionFeedbackToast.qml:10`；§7-① 已裁定 B |
| **reduceMotion = 0** | 上述时长全部置 0；C 层折射动画关闭；环境光过渡跳过；expansion 关闭 | 定案 |

**reduceMotion 贯通（定案，非人工项）**：`ApplicationPreferences` 已有键
`Appearance/reduceMotion`（默认 false）并导出 env "1"/"0"
（`ApplicationPreferences.cpp:15,105-108,172`）；listenfree
`SegmentedTabBar.qml:19` 是全库唯一自带该属性的控件。v1 方案：shell QML
经 ApplicationPreferences 单例只读绑定补消费点（现 `git grep reduceMotion -- shell`
无命中），SegmentedTabBar 属性改为绑定全局值。

## 3. 组件 API（16 个）

命名统一 `Glass*` 前缀；listenfree `GlassSurface.qml:8-30` 升格为全局
GlassSurface，calendar 局部同名组件（`Main.qml:672`）废弃迁移。
**控件双家族定案**：Glass* = 玻璃态标准控件；`shell/Kos/Ui/foundation/Kos*.qml`
保留为普通（非玻璃）态；`shell/Kos/Ui/controls/Liquid*.qml` 逐步并入 Glass*
（LiquidSelect→GlassComboBox 等），不设人工裁定项。

所有组件公共契约：`material` 三档（§2.1）、A 层自足（无 B/C 不破相）、
reduceMotion 继承全局、状态不得仅用颜色区分。

### 3.1 GlassSurface（通用表面，A 层）
- 属性：`radius`（默认 `surface` 24）、`tint`（AppTheme.cardStrong 映射进 AppearanceTokens）、
  `tintStrength`、`stroke`、`shadow`（卡片级档）。
- 状态：`idle / hovered`（hover = expansion 0.3 提亮）。
- 层级：不自建 blur region；宿主已挂 B 层时自动降为 tint+高光+描边薄壳。

### 3.2 GlassDialog（模态对话框）
- 属性：`radius: surface 24`、`material: thick`、scrim（**单一来源** = compositor
  scrim，链路定案见 §1.4；QML 背板仅 fallback，废双重变暗）、
  标题 Title1 22/26、正文 Body 13/16、按钮高 28、内边距 `space.lg` 20。
- 状态：`opening / open / closing / closed`。
- 层级：layer-shell 单表面（KosFloatPanel 路线）；生命周期三模型
  （QML Dialog / opacity 自绘 / KosDialog，INVENTORY 冲突⑨）统一到
  `KosDialog` foundation + PopupMotion 门控。
- 字阶：现值 19/21/24 标题→Title1 22；正文字号不得低于 10。

### 3.3 GlassPopover（弹出层）
- 属性：`anchor`、`offset`（默认 `popupAnchorOffset` 20）、`radius: card 16`、
  内边距 `space.md` 12（收编 EventDetailsPopover:31 的 14）、
  `shadowInset` 仅作布局余量不内绘阴影、阴影浮层级档。
- 状态：`opening / open / closing / closed`，运动一律走 `PopupMotion.qml:5-71`
  的 mapped/interactive 契约（显隐保持 mapped + interactive 门控，
  不用 QML Popup closePolicy 管生命周期）。

### 3.4 GlassMenu
- 复用 GlassPopover 宿主与运动；属性：`padding: space.sm` 8
  （收编实测 0/6/8 三档，`ContextMenu.qml:53`/`MusicMenu.qml:7`/`SessionMenu.qml:138`）。
- 项：高 ≥28（HIG 命中区）、item radius 8（`ContextMenu.qml:117`、`GlobalMenu.qml:206`）、
  字号 Body 13（`ContextMenu.qml:132`）、项间距 `space.xs` 4。
- 收编对象：MusicMenu（AppTheme Rectangle 背景）、WallpaperValueMenu（自绘 19 radius）、
  SessionMenu（自绘 + 比例字号）、GlobalMenu 内部复用 listenfree ContextMenu（:290）。

### 3.5 GlassTooltip
- 属性：`material: thick`（小面积最厚档）、`radius: small 10`（收编现值 7/6，
  `StatusTooltip.qml:52`、`DockAppNameTooltip.qml:73`）、primary 字号 Callout 12 +
  secondary Footnote 10（现值 12/10，`StatusTooltip.qml:63,70`）、贴边 margin +4
  正间隙（§7-② 已裁定 B，手感需真实 bar/dock 悬停复核）。
- **定案：dock tooltip 迁入玻璃配方**（现状 ThemeService 纯色 Rectangle，
  INVENTORY 冲突⑥）。

### 3.6 GlassToast
- LiquidGlassPanel 子类：`material: regular`、`scrimLevel: "readable"`、
  `radius: pill`（`ActionFeedbackToast.qml:28-31`）、高 36、字号 Callout 12 Medium、
  显隐 150/180ms + scale 0.96→1（:38-41）、存留 2600ms + 悬停暂停（§7-① 已裁定 B）。

### 3.7 GlassNotification（通知卡片族）
- 容器卡片 `radius: surface 24`（`NotificationHistoryCard.qml:78,93`）；
  卡片内列表项/分组 pill 统一 `radius: card 16`（收编 18/16）。
- 字阶：标题 Title2 17（:187）、正文 Body 13（:155）、次要 Subheadline 11、
  时间戳 Footnote 10（:199）；**Entry 的 9 号字迁 Footnote 10**（:108）。
- 面板本体走 ControlCenterGlass 配方（已确认，INVENTORY §10.3）。

### 3.8 SegmentedControl
- 定案统一比例制：pill 形态 `height/2`、card 形态 `height×0.38`
  （`LiquidSegmentedControl.qml:87`）；废弃 `Math.min(AppTheme.smallRadius, height/2)`
  （`KosToolButton.qml:33`）与 `AppearanceTokens.shape` 的第三套 ratio
  （`:414`）两套口径。
- 参数：cell 72×40（`SegmentedTabBar.qml:12`）、outerPadding 2（:13）、
  字号 Body 13（:79）；`reduceMotion` 属性绑定全局（§2.7）。

### 3.9 GlassButton
- 属性：`material: regular`、高 28（HIG 命中区默认）、`radius: pill`（单按钮）或
  `small 10`、`icon` / `text`。
- 状态：`idle / hovered / pressed / disabled`；expansion 读 token（§2.7），
  不得组件内硬编码。

### 3.10 GlassTextField
- 属性：高 28（HIG）、`material: regular`、字号 Body 13、`placeholderText`、`error`。
- 状态：`normal / focused / error / disabled`；focus = 描边强调 + tint 加深
  （不新增模糊）；error = 描边红 + 图标（非纯颜色）。

### 3.11 GlassCheckbox
- 属性：框 20×20（`SettingsCheckBox.qml:10-11`，= HIG 最小，达标）、
  `radius: 5`（现值保留）、label 字号 Body 13（收编现值 14，:35）。
- 状态：`unchecked / checked / hovered / pressed / focusVisible / disabled`；
  勾选必须有图形（√），不靠颜色。
- 收编 KosCheckBox 三份同名实现（`shell/Kos/Ui/foundation/`、`shared/qml/foundation/`、
  SettingsCheckBox，INVENTORY 冲突⑩）。

### 3.12 GlassComboBox
- 属性：高 36（`LiquidSelect.qml:17`，> HIG 默认 28 允许）、`radius: pill`
  （`fieldRadius: height/2`，:35）、字号 Body 13（:200,211）、
  描边 alpha 深 0.16/浅 0.12（:30）、sheetColor 深 `#262b31`/浅 `#f6f8fb`（:29）。
- 弹层：radius card 16（收编 AppTheme.mediumRadius/19 散值）、
  高 `min(360, 内容+12)`（:232，收编 280/300 两版）、菜单偏移 5（:92-96）、
  popup padding `space.sm` 8。
- 收编三份并存：LiquidSelect / KosComboBox / MusicComboBox（INVENTORY 冲突⑪）。

### 3.13 GlassScrollBar
- 现状四种做法无统一组件（原生 ScrollBar policy ×3、内联 Basic.ScrollBar、
  局部 StableScrollBar、shell 侧 KosKineticScroll，INVENTORY 冲突⑫）。
- v1 提案：单一 overlay 式 GlassScrollBar——宽 6（hover 8）、
  滚动/悬停时显示、静止淡出、radius pill、thumb 用 selected 角色
  （浅 `#22000000` / 深 `#30ffffff`，`AppTheme.qml:120`）。数值无代码依据，
  标 v1 提案；shell 侧保留 KosKineticScroll 作为行为层。

### 3.14 GlassSlider（R5 §12.1 盘点后新增）
- 收编对象：LiquidSlider（双形态收编目标）；KosSlider 保留为 foundation 非玻璃
  形态；ColorRampSlider 维持专用（不收编，INVENTORY §12.1）。
- 属性：`value 0..1`、`wheelStep 0.01` / `wheelPixelStep 10`（Ctrl+滚轮协议，
  `LiquidSlider.qml:107-112`）、`trackHeight 6`、thumb 32×16（:27-29）、
  `accentColor`（进 token，废 `#0a84ff` 硬编码，:18）。
- 信号契约：`previewChanged / commitRequested / canceled`；提交去抖 180ms、
  提交后 400ms 屏蔽 x 动画（:50-54,:153）——异步写回不跳变，为定案行为。
- 形态：双形态沿用 `ControlForm.materialForm`（:41）——iOS 玻璃 thumb（六层，
  :252-418）/ M3 竖把手（`m3Scale=min(1,h/44)`，:430-434）；高度 44 默认，
  M3 随宿主高度 30–44 缩放。
- 状态：`idle / hovered / pressed / disabled`；expansion 读 token（§2.7），
  **悬停 expansion 收敛 0.3**（slider 现 0.40 `:507` vs button 0.3——v1 提案取 0.3）。
- 时长：pressed 270/释放 460、x 跟随 200（:66-67,:247）进 motion token
  （§2.7 增补行）。

### 3.15 GlassSwitch（R5 §12.2 盘点后新增）
- 收编对象：LiquidGlassSwitch（注意实名，无 "LiquidSwitch"，qmldir 为证）；
  KosSwitch 保留为 foundation 非玻璃形态（无障碍实现完整，`KosSwitch.qml:15-20`，
  其无障碍做法为 GlassSwitch 必须具备）。
- 属性：`checked` / `toggled(bool)`（宿主确认值，组件不本地赋值，:98-104 定案
  行为）；尺寸 74×32、thumb 44×26、`travel = width-44-6`（:29-30,:56-58）；
  M3 形态 handle 16dp off/24dp on、`m3Scale=min(1,h/32)`（:323-324）。
- 状态：`off / on / hovered / pressed / disabled / focusVisible`；focus 环必配
  （§2.6，KosSwitch :36-38 的描边做法收编）。
- 时长：thumbX 200 OutCubic、expansion pressed 120/释放 200（:71-84）进 motion
  token；layer 门控（仅 expansion>0 或半透明开 FBO，:42-49）为性能定案行为。
- 主题：玻璃形态无深浅分支（track 只看 progress，:63-68）——保持现状，深浅由
  材质三档与 scrim 承担（§2.1）。

### 3.16 GlassNavBar（导航容器契约，R5 §12.3 判定：容器）
- **判定为导航容器**（model/currentIndex/selectionChanged 契约，:21-23,:50），
  非表单控件；表面做法属玻璃控件家族，归入弹层页/表面页演示而非控件页表单区。
- 属性：`model [{id,label?,icon}]`、`currentIndex`、`selectionChanged(index)`、
  5 档 size presets（tiny 34 / small 42 / medium 54 / large 67 / XL 80，
  :56-62）、`barHeight`（比例缩放，:65）、`itemDelegate` 可覆写（:453）。
- 字阶：label 字号 preset 7/8/9/11/13 **低于 HIG 最小 10** → label 最小 Footnote
  10（icon 为符号文本，豁免字阶但 iconSize 保持 preset 14–28）。
- 颜色：accent 进 token（废 `#ff453a` 硬编码，:32）；itemColor `#ffffff`（:37）
  仅适配深色玻璃底 → 浅色底改走 AppearanceTokens 前景角色（机械迁移）。
- 动效：弹簧 physics（velocity=diff×0.5，:160-180）+ 显示层 100ms OutCubic
  （:115-117）+ lens 280ms 自动隐（:148）；reduceMotion 时 physics/100ms 过渡
  关闭、直接落位。
- 状态：`idle / selected / disabled`；item 命中区 = itemWidth×barHeight，
  最小档 56×34 ≥ HIG 28×28（达标）。

## 4. 性能规则（沿 v0 定案）

1. 禁止每组件独立 `layer.enabled` + ShaderEffect；玻璃收尾由 GlassSurface 系承担，
   宿主已挂 B 层时子组件不得再加效果层。
2. 阴影唯一实现 = MultiEffect 合并（§2.3）。
3. B 层每窗口/面板至多一次 blur region / SurfaceShape。
4. C 层仅限白名单（§1.2），fallback 时静默降级。
5. 圆角模糊区域统一从 `KosRoundedBlurRegion` 进，关闭 `RoundedBlurRegion` 直用。

## 5. 与 HIG 的差异登记（不裁定，仅登记）

- Toast 定时消失 2600ms（悬停暂停）：HIG 建议尽量少用定时自动消失；
  已裁定 B 采用 2600ms + 悬停暂停，比 1600ms 更贴近 HIG → 后果见 §7-①。
- ComboBox 高 36：超 HIG 默认 28，但属允许范围（≥最小 20）且为现值。
- 通知 Entry 9 号字、SessionMenu 比例字号：违规已定迁移方案（§2.4），
  极端情况可读性见 §7-③。
- NavBar label 字号 preset 7/8/9（`LiquidNavBar.qml:57-59`）：低于 HIG 最小
  10pt，迁 Footnote 10（§3.16）。

## 6. 迁移清单（机械项，不需裁定）

1. bar 直用 LiquidGlassPanel 的 6 个面板 → ControlCenterGlass 配方（§1.1）。
2. dock tooltip → GlassTooltip 玻璃配方（§3.5）。
3. 菜单四来源（listenfree ContextMenu / MusicMenu / WallpaperValueMenu / SessionMenu）
  → GlassMenu（§3.4）。
4. ComboBox 三份 → GlassComboBox；CheckBox 三份 → GlassCheckbox；Segmented 两套 →
  统一比例制（§3.8）；ScrollBar 四做法 → GlassScrollBar + KosKineticScroll；
  Slider 收编 LiquidSlider（KosSlider/ColorRampSlider 保留，§3.14）、
  Switch 收编 LiquidGlassSwitch（§3.15）、NavBar 立容器契约 GlassNavBar（§3.16）。
5. Dialog 三生命周期模型 → KosDialog + PopupMotion（§3.2）；圆角/字号散值归档。
6. 字号 9→10、比例字号废除、硬编码字族移除（§2.4）。
7. 间距散值 1/3/5/6/7/9/10/14 → 四档（§2.5）。
8. 液态 expansion / ambientTransitionDuration 进 token，删硬编码（§2.7）。
9. shell QML 补 reduceMotion 消费点（§2.7）。
10. calendar 局部 GlassSurface 废弃迁移到全局 GlassSurface（§3 开头）。
11. weather 卡片 → GlassSurface 显式 tint（昼夜场景值传参，§1.1）；
    滚动边缘 MultiEffect 保留为独立模式，不迁（INVENTORY §12.5）。

## 7. 已裁定（3 项，均为视觉/产品语义）

> R5 已由代码关闭 2 项：weather tint 公式（→ §1.1 定案，INVENTORY §12.5）、
> scrim 下发链路（→ §1.4 定案）。以下保留 3 项已裁定的产品语义；旧 Gallery
> 裁定页已移除，不再作为当前操作入口。

1. **① Toast 存留 → B（已裁定）**：2600ms（原 1600ms）+ 悬停暂停、
   离开按剩余时间继续（不重置）；`ActionFeedbackToast.qml:10`。
   后果：更贴近 HIG「少用定时消失」；代价是 toast 可见期间其 36px 药丸
   区域接收悬停（点击不再穿透），并比原值多占用屏幕约 1s。
2. **② Tooltip 贴边 → B（已裁定）**：+4px 正间隙（原 -6px 负 margin）；
   `StatusTooltip.qml:40-43`、`DockAppNameTooltip.qml:67-69`。
   后果：tooltip 不再压进锚点，贴边处露出细缝；真实 bar/dock 悬停手感
   需人工复核。
3. **③ SessionMenu 极端高度 → A（已裁定）**：接受固定 Footnote 10，
   不为 SessionMenu 单独设定 itemHeight 范围；生产代码不改。
   后果：字号不再随 itemHeight 比例缩放，极矮行偏拥挤、极高行偏空，
   可读性由固定 10pt 兜底。
