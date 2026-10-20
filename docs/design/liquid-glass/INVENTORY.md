# 液态玻璃组件盘点（第 0 批 R1）

> 来源分支（只读盘点，未 checkout）：
> - `origin/codex/calendar-ui-iter-20261016`（下称 **cal**）
> - `origin/claude/weather-app`（下称 **wx**）
> - `origin/codex/liquid-animation-experiment`（下称 **liq**）
> - 当前工作树 `codex/liquid-glass-foundation`（下称 **WT**）
>
> 四个来源是同一仓库的不同分支；`apps/listenfree`、`apps/lockscreen`、`apps/sddm`
> 在四个来源中内容一致（GlassSurface.qml 逐行比对一致），差异集中在
> `shell/`（仅 WT 全面展开）、`apps/calendar`（cal）、`apps/weather`（wx）、
> `apps/settings`（liq 的动效实验）。未逐项 diff 的部分在文中标注。

## 1. 总矩阵表

| 组件 | 来源 | 实现方式 | 关键参数 | 主题适配 | 已知不一致 |
|---|---|---|---|---|---|
| **LiquidGlassPanel** | WT `shell/desktop/modules/common/LiquidGlassPanel.qml:33-131` | Item(不画) + SDF 蒙版子项；默认走 KWin Glass 合成器模糊，QML fallback | `radius:0` + `cornerExponent:2.0`(可连续圆角)、`useKwinEffect:true`、`frostOnly:false`、`blurOverrideEnabled:false`、`compositorRevealDuration:320`、`baseColor:rgba(0,0,0,0.1)`、`material:"clear/regular/thick"` | `fallbackEnabled: AppearanceTokens.surface.paintInQml`（:111） | 与 LiquidGlassSurface 职责相邻但方向相反（见 §2 冲突①） |
| **LiquidGlassSurface** | WT `shell/desktop/modules/common/LiquidGlassSurface.qml:14-62,182` | 纯 QML 收尾层（tint+反射+环境光），叠在合成器模糊之上 | `baseColor:rgba(0,0,0,0.1)`、`material` 三档（clear 的 `materialOpacityScale:0.58`、`materialReflectionScale:0.62`）、`ambientTransitionDuration:2600`、`blurStrength:AppearanceConfigService.effectiveDockBlur` | `AppearanceTokens.surface.usesTonalRoles`（:20） | 只服务「已有合成器模糊」的宿主，半径为 0 时依赖蒙版 |
| **GlassSurface**（listenfree） | 四源一致：`apps/listenfree/music_player_desktop/components/GlassSurface.qml:8-30` | 纯 QML Rectangle + `layer.effect: MultiEffect` 阴影 + 可选 backdrop 模糊 | `cornerRadius:24`、`tint:AppTheme.cardStrong`、`tintStrength:.16`、`exclusionStrength:.04`、`noiseStrength:.01`、`backdropBlur:32`、`shadowOpacity:0.16`、`shadowOffset:5/7`、MultiEffect `blurMax:16, blur:.6` | AppTheme（单例色板），无 wallpaper 桥 | 同名组件在 cal `apps/calendar/qml/Main.qml:672` 被重新实现为局部 `component GlassSurface: Rectangle`，参数体系完全不同（冲突②） |
| **KosSurface** | WT `shell/Kos/Ui/foundation/KosSurface.qml:6-16,29,45` | 纯 Rectangle 三层：外阴影(r+3)、描边(r+1)、内填充(r) | `radius:AppTheme.mediumRadius`、`strokeWidth:1`、`elevation:0.5`、`showInnerHighlight:true`、modernDesign 时 elevation×0.38 | AppTheme.cardSurface/border | 与 Liquid* 家族零共享：无蒙版、无合成器协作（冲突③） |
| **KosFloatPanel** | WT `shell/desktop/modules/common/KosFloatPanel.qml:45-76` | layer-shell 面板，内部包 LiquidGlassPanel；modal 背板 | `radius:32`、`cornerExponent:AppearanceTokens.shape.cornerExponent`、`shadowOffsetX/Y:12/16`、`shadowSoftness:18`、`shadowColor:rgba(.5,.5,.5,.30)`、`materialDepth:1`、`blurStrength:0.3`、`fixedScrimOpacity:0.8`、`contentPadding:20` | AppearanceTokens.surface.pick(surfaceContainer, black/white)（:76） | radius 32 与 GlassSurface 24、MaterialCardSurface 16 三种面板圆角并存（冲突④） |
| **MaterialCardSurface** | WT `shell/desktop/modules/common/MaterialCardSurface.qml:24-47` | Rectangle 填充 + Region 模糊（矩形或花形） | `radius:16`、`fillColor:"transparent"`、`flowerLobes:12`、`flowerAmplitude:0.075` | 上色交给宿主 | 仅供时钟等少数场景；与 ControlCenterGlass 不同配方 |
| **ControlCenterGlass** | WT `shell/desktop/modules/bar/ControlCenterGlass.qml:9-21` | LiquidGlassPanel 的「一份配方」封装 | `material:"regular"`、`materialDepth:0`、`blurOverrideEnabled:true`、`blurStrength:0`(→KWin level 1)、`scrimLevel:"balanced"`、`ambientStrength:0.35×ambientMultiplier` | ThemeService.backgroundColor + WallpaperColorSource.primary/secondary | 是正确的收敛样板；其余 bar 面板是否全部走它未逐个核对（标注：未逐项核对） |
| **KWin glass-effect** | WT `kwin/glass-effect/src/blur.cpp`（2612 行）、`settings.h:19,69-83` | KWin effect：模糊 + 折射 + SurfaceShape 协议 v4 | `blurStrength`(全局 1..15)、`RefractionSettings{refractionStrength, refractionNormalPow, refractionRGBFringing, refractionOffsetStrength}`；**具体默认值未找到**（settings.h 只声明字段） | 深浅由 QML 侧 scrim 参数下发 | C 层折射已存在但 QML 侧默认 `useKwinEffect` 才启用 |
| **RoundedBlurRegion** | WT `shell/desktop/modules/common/RoundedBlurRegion.qml:7-58` | Quickshell `Region`：2 矩形 + 4 椭圆拼圆角 | `radius` 默认 `min(w,h)/2`，整数化取整 | 无 | 与 KosRoundedBlurRegion 是父子关系，非冲突 |
| **KosRoundedBlurRegion** | WT `shell/desktop/modules/common/KosRoundedBlurRegion.qml:12-97` | RoundedBlurRegion + `SurfaceShape`(radius/exponent) + scrim + per-shape blur | `exponent:2.0`、`scrimTint 0/1`、`scrimCap`、`scrimDecay`、`blurLevel 1..15`(协议 v4)、`revealDuration:320`、`materialOpacity` | scrim 黑/白由调用方定 | — |
| **FlowerBlurRegion** | WT `shell/desktop/modules/common/FlowerBlurRegion.qml:31-52` | Region 花形轮廓（多行带状矩形拼合） | `lobes:12`、`amplitude:0.075`、`sliceCount:32`、`inset:18` | 无 | — |
| **Weather 表面** | wx `apps/weather/qml/Main.qml:39-48,454,1330,1362` | Rectangle（圆角圆片/tileRadius）+ MultiEffect | 多处内联 radius、两处 MultiEffect；具体 tint 公式未逐段抄录（**抽查级**） | 局部配色 | 与 GlassSurface 并存，未走统一组件 |
| **Calendar 内联 GlassSurface** | cal `apps/calendar/qml/Main.qml:672,776,891-958` | 局部 `component GlassSurface: Rectangle` + MultiEffect（lensBlur blurMax 48，:243） | `lensBlur` 为 MultiEffect 归一化柔化量 blurMax 48（:243） | 局部 neutral 调色板（「无蓝灰 tint」，EventDetailsPopover.qml:11） | 与 listenfree GlassSurface 同名不同物（冲突②） |
| **EventDetailsPopover** | cal `apps/calendar/qml/EventDetailsPopover.qml:15-69` | `Popup` + 应用内自绘阴影（画进 `shadowInset` 边距） | `shadowInset:14`、`width:340+2×14`、`padding:14+14`、`CloseOnPressOutside|Escape` | `AppTheme.popoverBorder`（:23） | 自绘阴影 vs shell 侧 KosCardShadow/合成器阴影（冲突⑤） |

## 2. 分类结论

### 玻璃表面

**重复实现**
1. 同名 `GlassSurface` 有两份互不相干的实现：listenfree 版（四源一致，`GlassSurface.qml:8-30`）与 calendar 版局部组件（`apps/calendar/qml/Main.qml:672`）。
2. 「圆角模糊区域」两层实现：几何 Region（`RoundedBlurRegion.qml`）与其增强版（`KosRoundedBlurRegion.qml`，加 SurfaceShape/scrim/blurLevel）——后者是有意封装，前者仍是独立入口，宿主可能直接用底层版漏掉形状声明。
3. QML 端玻璃收尾有两套：`LiquidGlassSurface.qml`（叠合成器模糊）与 listenfree `GlassSurface.qml`（MultiEffect + backdropBlur 32），参数词汇完全不同（material 档位 vs tintStrength/exclusionStrength/noiseStrength）。

**互相冲突**
- ① `LiquidGlassPanel`（宿主不画、蒙版切割、默认走 KWin）与 `LiquidGlassSurface`（纯 QML 收尾）对 radius 的约定相反：前者 radius 必须 0（`LiquidGlassPanel.qml:33`），后者要求 radius 跟随或显式 `cornerInset`（`LiquidGlassSurface.qml:9-14`）。
- ② 面板圆角三标并存：32（KosFloatPanel:45）/ 24（GlassSurface:10）/ 16（MaterialCardSurface:25）。
- ③ 阴影三套：listenfree GlassSurface 用 MultiEffect blurMax 16（:30）；KosFloatPanel 用 KosCardShadow 自绘外阴影（:47-54）；calendar EventDetailsPopover 用 padding 内自绘（:64-69）。
- ④ KWin C 层折射参数已具备（`settings.h:69-72`），但 QML 组件层没有「何时开折射」的契约，仅 `useKwinEffect` 布尔。

### 弹层

**重复实现**
1. 弹层运动：`PopupMotion.qml`（WT，进度驱动的 mapped/interactive 契约，:5-71）是收敛实现；但 `AnimatedPopupWindow.qml`、`KosFloatPanel.qml` 各自的显隐路径是否都走它，未逐个核对（标注：未逐项核对）。
2. 弹层宿主三种：Quickshell PopupWindow 系（bar 面板）、`KosFloatPanel`（layer-shell 单表面）、QML `Popup`（calendar）。
3. 阴影/边距方案重复：EventDetailsPopover 的 shadowInset 自绘与 KosFloatPanel 的 KosCardShadow 语义重叠。

**互相冲突**
- ① 显隐模型：PopupMotion 要求「保持 mapped + interactive 门控」（`PopupMotion.qml:6-8`）；QML Popup 用 closePolicy 原生开关——两套生命周期无统一契约。
- ② 弹层持续时间：`AppearanceTokens.motion.popupOpenDuration:150 / popupCloseDuration:140`（`AppearanceTokens.qml:568-569`）对 shell 生效；calendar/weather 弹层无动画参数（未找到）。
- ③ 背板 scrim：shell 侧有 compositor scrim（`KosRoundedBlurRegion.qml:78-81`，tint/cap/decay）+ `popupScrimLevel:"balanced"`（`AppearanceTokens.qml:453`）；KosFloatPanel 另有 QML 背板 `backdropTint:black`+`backdropOpacity`（:27-38）。同一弹层可能双重变暗。

### 控件

**重复实现**
1. 控件双家族并行：`shell/Kos/Ui/controls/Liquid*.qml`（LiquidGlassButton/LiquidSegmentedControl/LiquidTextField/LiquidSelect/LiquidSlider/LiquidSwitch）与 `shell/Kos/Ui/foundation/Kos*.qml`（KosButton/KosToolButton/KosTextField/KosComboBox/KosCheckBox/KosDialog…共 30 文件，见 `shell/Kos/Ui/foundation/`）。liquid 版自带玻璃高光，foundation 版走 KosSurface。
2. Segmented 两份：`LiquidSegmentedControl.qml`（:87 materialForm 半径 `height/2`，否则 `height*0.38`）与 listenfree `SegmentedTabBar.qml`（`apps/listenfree/music_player_desktop/components/SegmentedTabBar.qml`，参数未逐项抄录——抽查级）。
3. TextField 两份：`LiquidTextField.qml` 与 `KosTextField.qml`；ComboBox：`LiquidSelect.qml` vs `KosComboBox.qml` vs `apps/music/qml/MusicComboBox.qml`（三份）。
4. 按钮内按压/悬停液态参数各自硬编码：`LiquidGlassButton.qml:25` `_expansion = pressed?1.0:(hovered?0.3:0)`，无共享 motion token。

**互相冲突**
- ① 圆角体系：LiquidSegmentedControl 用比例（0.38/0.42/0.34，:87,121,218）；KosToolButton 用 `Math.min(AppTheme.smallRadius, height/2)`（:33）；AppearanceTokens.shape 用 ratio（`tokens.isWindows12 ? 0.20 : 0.50`，:414）。三种口径。
- ② KosSurface（AppTheme 纯色板）与 AppearanceTokens（SystemPalette + wallpaper 桥 + Material/Monet）是两套颜色入口（`KosSurface.qml:6-7` vs `AppearanceTokens.qml:17-94`）。

### 动效

**现状**
1. 集中 token：`AppearanceTokens.motion`（WT `AppearanceTokens.qml:552-571`）：`fastDuration 120/normalDuration 180/slowDuration 260`（windows12 分支，:553-557）、`popupOpenDuration:150`、`popupCloseDuration:140`、`popupStartScale:0.96`、`popupAnchorOffset:20`、`popupAnimatesOnShow:true`。
2. `PopupMotion`（:9-11）open=OutCubic / close=InCubic，时长按剩余进度等比缩放（`animateTo`，:46-57）。
3. `PageMotion.qml` 存在于 WT `shell/desktop/modules/common/PageMotion.qml`，但 grep `property|duration|easing` 无命中——内容未能读取结论，**待人工核对**。
4. `reduceMotion`：仅 `apps/common/src/ApplicationPreferences.cpp:15,105-108,172,219`（键 `Appearance/reduceMotion`，默认 false，导出为 env "1"/"0"）及测试消费；**shell QML 侧未找到任何读取点**（`git grep reduceMotion HEAD -- shell` 无命中）→ 玻璃动效目前不受 reduceMotion 约束。
5. 环境光过渡 `ambientTransitionDuration:2600` 硬编码于 `LiquidGlassSurface.qml:45` 与 `LiquidGlassPanel.qml:119`，不进 motion token。

## 3. 未找到 / 待人工核对清单

- kwin glass-effect 各参数的**默认值**（settings.h 只有字段声明；blur.cpp 2612 行未逐段读）。
- `shell/desktop/modules/common/PageMotion.qml` 的内容（grep 无命中，异常）。
- bar 各面板（NetworkPanel/BatteryPanel/BluetoothPanel 等）是否统一走 ControlCenterGlass 配方——只确认了 ControlCenterGlass 本身。
- liq 分支相对其他分支的动效实验差异（集中在 `apps/settings/src/WindowSettings.cpp`、`main.qml`、`tests/widgets/tst_widgets.qml`，未逐项核对）。
- weather `apps/weather/qml/Main.qml` 的具体 tint/模糊配方（仅抽查 MultiEffect 出现位置 :1330,:1362）。
- `shell/desktop/modules/common/LiquidGlassPanel.qml` 的 scrim 实现细节（`scrimEnabled/scrimLevel` 在 :86 一带声明，下发路径未读到）。

---

# R3 补全（第 0 批续）

> 以下为本轮追加。行号均基于工作树 `codex/liquid-glass-foundation`（WT）；
> 分支文件用 `git show origin/<branch>:<path>` 读，出处标注分支前缀。

## 4. Tooltip / Toast / 通知

| 组件 | 来源 | 实现方式 | 关键参数 | 主题适配 | 不一致 |
|---|---|---|---|---|---|
| **StatusTooltip** | WT `shell/desktop/modules/bar/StatusTooltip.qml:9-74` | AnimatedPopupWindow + **ControlCenterGlass** | `radius:7`(:52)、open/closeDuration 70(:27-28)、primary 字号 12 DemiBold(:63)、secondary 10 Medium(:70)、列 spacing 3(:57)、隐式宽/高 = 内容 +18/+12(:24-25)、贴边 margin +4(:40-43，G7 裁定 B) | `tooltipSurface.foregroundColor/secondaryForegroundColor`（ControlCenterGlass 导出） | — |
| **DockAppNameTooltip** | WT `shell/desktop/modules/dock/DockAppNameTooltip.qml:73-89` | PopupWindow + 普通 **Rectangle**（非玻璃） | `radius:6`(:73)、border 1(:75)、字号 11 DemiBold(:85-87)、贴边 margin +4(:67-69，G7 裁定 B) | `ThemeService.tooltipBackground/borderColor/foregroundColor`(:74-81) | **与 StatusTooltip 不同配方**：bar tooltip 走 ControlCenterGlass，dock tooltip 走 ThemeService 纯色 Rectangle（冲突⑥） |
| **ActionFeedbackToast** | WT `shell/desktop/modules/common/ActionFeedbackToast.qml:5-66` | **LiquidGlassPanel** 子类 | `radius:height/2`(:28)、material regular(:29)、scrimLevel "readable"(:31)、timeout 2600ms(:10，悬停暂停/离开按剩余继续)、opacity 150ms / scale 180ms OutCubic(:40-41)、字号 12 Medium(:57-58)、spacing 7(:46)、高 36 宽=内容+28(:24-25)、`scale: shown?1:0.96`(:38) | `AppearanceTokens.surface.usesBackdrop/usesKwinBlur/paintInQml`(:30-33) | — |
| **NotificationHistoryCard** | WT `shell/desktop/modules/bar/NotificationHistoryCard.qml` (201 行) | ControlCenterGlass 宿主内卡片 | 卡片 `radius:24`(:78,93)、图标底 22×22 r7(:101)、字号 11(:129)/13(:155)/17(:187)/10(:199)、spacing 4(:135) | ControlCenterGlass（`git grep` 确认） | — |
| **NotificationHistoryEntry** | WT `…/NotificationHistoryEntry.qml` (168 行) | 列表项 | `radius:18`(:66)、字号 9(:108)/12(:135)/11(:144)/18(:164)、spacing 4(:114)、内 pill radius 14(:154) | — | 字号 9 与 HIG 最小 10pt 相悖 |
| **NotificationHistoryGroup** | WT `…/NotificationHistoryGroup.qml` (212 行) | 分组头 | 字号 11(:121,135)、`radius:18`(:159)、spacing 6(:176) | — | — |
| **NotificationHistoryPane** | WT `…/NotificationHistoryPane.qml` (403 行) | 面板体 | `radius:16`(:202)、行高 pill `height/2`(:212)、字号 11(:237)、空态 12(:387)、外层 radius 24(:358,380) | — | — |
| **NotificationHistoryPanel/Toggle** | WT `…/NotificationHistoryPanel.qml` (179 行)、`…/NotificationHistoryToggle.qml` (76 行) | 容器/RoundedBlurRegion(:141)、小圆点 6×6 r3(:55) | — | — | — |

**结论**：通知族实际是 **6 个文件**（Card/Entry/Group/Pane/Panel/Toggle），任务书写的 8 个未找到多出的 2 个（已列 `ls` 结果）。Tooltip 双配方（玻璃 vs ThemeService Rectangle）是本类最大冲突。

## 5. Menu / ContextMenu

| 组件 | 来源 | 实现方式 | 关键参数 | 不一致 |
|---|---|---|---|---|
| **ContextMenu**（listenfree 通用菜单） | 四源一致 `apps/listenfree/music_player_desktop/components/ContextMenu.qml:53-132` | QML `Menu`，background = **GlassSurface** | `padding:0`(:53)、item 字号 13(:132)、item 高亮 radius 8(:117) | — |
| **SongContextMenu** | `…/SongContextMenu.qml:5` (33 行) | ContextMenu 薄子类 | — | — |
| **MusicMenu / MusicMenuItem** | `apps/music/qml/MusicMenu.qml:5-11`、`MusicMenuItem.qml:10-33` | `Menu` + Rectangle 背景 | padding 6(:7)、`radius:AppTheme.mediumRadius`(:11)；item leftPadding 12/topPadding 6(:10-12)、spacing 10(:16)、`radius:AppTheme.smallRadius`(:33) | 背景=AppTheme Rectangle，与 listenfree GlassSurface 配方不同（冲突⑦） |
| **WallpaperValueMenu** | `apps/settings/WallpaperValueMenu.qml:41-119` (182 行) | 自绘弹层 | spacing 9(:41)、字号 13 Medium(:45-46)、`padding:6`(:67)、外层 radius 19(:81)、内层 17-19(:92-119) | — |
| **SessionMenu** | `apps/lockscreen/contents/lockscreen/SessionMenu.qml:138-286` (298 行) | 自绘卡片 | `padding:8`(:138)、卡片 radius 14(:147)、item radius 9(:269)、item 字号 = `Math.round(itemHeight*0.34)`(:286) | **字号随高度比例算**，无固定档位（冲突⑧） |
| **GlobalMenu** | WT `shell/desktop/modules/bar/GlobalMenu.qml:9-290` (330 行) | KDE AppMenu 的 QML 原生渲染器（DBusMenu→QML 数据） | 字号 13 DemiBold(:39-40)、spacing 1(:182)、radius 8(:206,262)、内部复用 listenfree `ContextMenu`(:290) | — |

**结论**：菜单背景四种来源——GlassSurface（listenfree/GlobalMenu）、AppTheme Rectangle（music）、自绘（settings/lockscreen）；padding 0/6/8；item radius 8/smallRadius/9。收敛方向见 SPEC v1 GlassMenu。

## 6. Dialog 全量（11 个）

| 文件 | 来源 | 行数 | 模态/按钮 | 关键参数 |
|---|---|---|---|---|
| `apps/calendar/qml/EventEditorDialog.qml` | cal | 370 | `modal:true`(:21)、standardButtons Save\|Cancel(:25) | spacing 12(:170)、`radius:AppTheme.smallRadius`(:256)、字号 11(:204,281) |
| `apps/calendar/qml/CalendarTaskEditorDialog.qml` | cal | 222 | modal(:19)、Save\|Cancel(:23) | spacing 12(:97)、smallRadius(:102)、字号 11/10(:114,196) |
| `apps/todo/qml/TodoEditorDialog.qml` | todo | 274 | modal(:22)、Save\|Cancel(:26) | spacing 12(:135)、smallRadius(:140)、字号 11(:153) |
| `apps/music/qml/MusicDialog.qml` | music | 35 | modal(:8) | `padding:20`(:7)、`radius:AppTheme.largeRadius`(:10)、字号 19(:20)、内 padding 14(:27) |
| `apps/listenfree/.../AlertDialog.qml` | 四源 | 173 | opacity 驱动显隐(:22) | 字号 21(:78)/12(:87)、spacing 12(:71)/7(:96)、option pill radius 11(:106) |
| `apps/listenfree/.../SettingsTransferDialog.qml` | 四源 | 80 | — | 字号 12(:43,55)、spacing 8(:25,27)/6(:33) |
| `apps/listenfree/music_player_desktop/pages/MusicEditorDialog.qml` | 四源 | 505 | `visible: open || opacity > .01`(:61) | radius 16(:131)/24(:231)/20(:241)、字号 24(:173)/18(:182)、spacing 5-7 |
| `apps/settings/WallpaperOptionsDialog.qml` | WT | 120 | modal(:35) | radius 22(:21)/18(:55)、字号 16(:29)/12(:116)、spacing 8(:51) |
| `shell/Kos/Ui/foundation/KosDialog.qml` | WT | 33 | foundation 封装（薄） | — |
| `shell/Kos/Ui/foundation/KosSettingsDialog.qml`、`KosWorkspaceDialog.qml` | WT | — | foundation 家族 | — |

**冲突⑨（生命周期三模型）**：calendar/todo 用 QML `Dialog` + standardButtons；listenfree 用 opacity/`visible: open || opacity>.01` 自绘窗口；shell 用 foundation `KosDialog`。圆角六种：smallRadius / 11 / 16 / 20 / 22 / largeRadius。

## 7. 控件补全

| 控件 | 来源 | 关键参数 | 不一致 |
|---|---|---|---|
| **SettingsCheckBox** | 四源 `apps/listenfree/music_player_desktop/components/SettingsCheckBox.qml:10-35` | 20×20(:10-11)、`radius:5`(:23)、label 字号 14(:35) | 与 KosCheckBox 并存；**KosCheckBox 还有两份**：`shell/Kos/Ui/foundation/KosCheckBox.qml` 与 `shared/qml/foundation/KosCheckBox.qml`（同名三份，冲突⑩） |
| **KosCheckBox** | WT `shell/Kos/Ui/foundation/KosCheckBox.qml`、`shared/qml/foundation/KosCheckBox.qml` | — | — |
| **LiquidSelect**（ComboBox·liquid） | WT `shell/Kos/Ui/controls/LiquidSelect.qml:16-232` | 高 36(:17)、`fieldRadius:height/2`(:35)、字号 13(:200,211)、弹层高 `min(360, 内容+12)`(:232)、accent `#0a84ff`(:26)、sheetColor 深 `#262b31`/浅 `#f6f8fb`(:29)、outline α .16 深/.12 浅(:30)、菜单偏移 5(:92-96) | — |
| **KosComboBox**（foundation） | WT `shell/Kos/Ui/foundation/KosComboBox.qml:6-38` | 高 `AppTheme.controlHeight`(:6)、indicator 文字 "⌄" 字号 16(:15)、radius `AppTheme.smallRadius`(:18)、popup padding 6(:35)、高 `min(内容+12, 300)`(:34) | 与 LiquidSelect 三份并存（music 版，冲突⑪） |
| **MusicComboBox** | `apps/music/qml/MusicComboBox.qml:7-62` | 高 `AppTheme.controlHeight`(:7)、radius smallRadius(:11)、popup padding 6(:51)、高 `min(内容+12, 280)`(:52)、popup `radius:AppTheme.mediumRadius`(:62) | — |
| **ScrollBar** | 无统一组件：calendar 用原生 `ScrollBar.*.policy`（`CalendarScheduleView.qml:227` 等 3 处）；listenfree 内联 `Basic.ScrollBar`（`EqualizerPopup.qml:64` 等）+ 局部 `StableScrollBar`（`LyricsMatchPopup.qml:223`，policy AlwaysOff）；shell 侧滚动由 `KosKineticScroll.qml` 提供 | — | 四种做法，无 token（冲突⑫） |
| **SegmentedTabBar**（listenfree，参数补全） | 四源 `apps/listenfree/music_player_desktop/components/SegmentedTabBar.qml:8-79` | cellWidth 72、cellHeight 40、`cellRadius:cellHeight/2`(:12)、outerPadding 2(:13)、字号 13(:79)、hoverBackground `#24ffffff`(:17)、**有 `reduceMotion` 属性（默认 false，:19）** | 与 LiquidSegmentedControl（比例半径 0.38/0.42/0.34）口径不同；且这是全库唯一自带 reduceMotion 属性的控件，shell 侧无人读取（见 §10.4） |

## 8. 字阶与间距（实测）

### 8.1 字号 → 用途归类（本轮扫描到的全部值）

| 用途 | 出现过的值（出处示例） | HIG 归并 |
|---|---|---|
| 大标题/弹层标题 | 24（MusicEditorDialog:173）、21（AlertDialog:78）、19（MusicDialog:20） | Title1 22±（26/32 为 LargeTitle） |
| 列表强调/数字 | 18（NotificationHistoryEntry:164）、17（NotificationHistoryCard:187）、16（WallpaperOptionsDialog:29）、15（BundledIcon 尺寸，非字） | Title2/Title3 17/15 |
| 正文/菜单项 | 13（ContextMenu:132、LiquidSelect:200、SegmentedTabBar:79、GlobalMenu:39、NotificationHistoryCard:155）、14（SettingsCheckBox:35）、12（StatusTooltip:63、ActionFeedbackToast:57、NotificationHistoryPane:387） | Body 13/Headline 13 Bold；12≈Callout |
| 次要文本 | 11（DockAppNameTooltip:85、NotificationHistory:121,135,144、dialogs 多处）、10（StatusTooltip:70、NotificationHistoryCard:199） | Subheadline 11 / Footnote·Caption 10 |
| 微标注 | 9（NotificationHistoryEntry:108） | **低于 HIG 最小 10pt** |
| 权重 | Font.DemiBold（StatusTooltip:63、DockAppNameTooltip:87、GlobalMenu:40）、Font.Medium（ActionFeedbackToast:58、WallpaperValueMenu:46、StatusTooltip:70）、其余默认 | Headline 用 Bold；DemiBold/Medium 未区分档位 |
| 字族 | `"Noto Sans CJK SC"`（StatusTooltip:63、DockAppNameTooltip:84）硬编码两处；其余默认 | 未进 token |
| 异常 | SessionMenu 字号=`itemHeight*0.34`（:286）；NotificationHistory 无 letterSpacing 命中 | 比例字号应废除 |

### 8.2 padding / spacing / margins 常用值

| 类别 | 值 | 场景 |
|---|---|---|
| padding | 0（ContextMenu:53）、6（MusicMenu:7、WallpaperValueMenu:67、KosComboBox:35）、8（SessionMenu:138）、14（EventDetailsPopover:31、MusicDialog:27）、20（MusicDialog:7、KosFloatPanel contentPadding:20） | 弹层内边距 4 档并存：0/6/8/14（+20） |
| spacing | 1（GlobalMenu:182）、3（StatusTooltip:57）、4（NotificationHistoryCard:135）、5-7（MusicEditorDialog/AlertDialog/Toast）、8-10（dialogs/MusicMenuItem）、12（dialogs 表单） | 1..12 连续值，无档位收敛 |
| margins | +4（tooltip 贴边正间隙，StatusTooltip:40-43、DockAppNameTooltip:67-69；原 -6 负 margin 经 G7 裁定 B 改为 +4）、12/16（KosFloatPanel shadowOffset） | 贴边保留正间隙，不再压进锚点 |

## 9. 深浅主题 tint 实测对照表（代码值）

### 9.1 listenfree AppTheme（`apps/listenfree/music_player_desktop/components/AppTheme.qml:106-120`，`darkMode ? 深 : 浅`）

| 角色 | 深色 | 浅色 | 备注 |
|---|---|---|---|
| card | `#e629323a`（α≈0.90） | `#dff7f8f9`（α≈0.87） | :115 |
| cardStrong（GlassSurface tint） | `#f02d3740`（α≈0.94） | `#f2ffffff`（α≈0.95） | :116 |
| control | `#b937424c`（α≈0.73） | `#c8f6f6f6`（α≈0.78） | :117 |
| controlHover | `#e0495661`（α≈0.88） | `#efffffff`（α≈0.94） | :118 |
| tabSelected | `#d4434f59`（α≈0.83） | `#d9f7f8fa`（α≈0.85） | :119 |
| selected | `#30ffffff` | `#22000000` | :120 |
| sidebarSurface | `#1f141c24`（α≈0.12） | `#24ffffff`（α≈0.14） | :80 |
| textPrimary / Secondary / Muted | `#f3f6f8` / `#bdc6cd` / `#89959f` | `#20262b` / `#68747c` / `#858d93` | :112-114 |

### 9.2 shell 玻璃基底

| 项 | 值 | 出处 |
|---|---|---|
| LiquidGlassSurface/Panel `baseColor` | `rgba(0,0,0,0.1)` —— **深浅同值**，深浅差异交给环境光混合与 scrim | LiquidGlassSurface.qml:16、LiquidGlassPanel.qml:115 |
| clear 档 materialOpacityScale / ReflectionScale | 0.58 / 0.62 | LiquidGlassSurface.qml:60-62 |
| mac 平台 tint | 浅 `#F5F5F7` / 深 `#1D1D1F` | AppearanceTokens.qml:496-497 |
| Material 表面不透明度 | 0.60（非 Material 1.0） | AppearanceTokens.qml:548 |
| Material 描边不透明度 | 0.30（非 Material 0.16） | AppearanceTokens.qml:549 |
| glass 卡片前景 | `rgba(1,1,1,0.78)`（玻璃形态恒白） | AppearanceTokens.qml:333 |
| 形状档位 | small 10/12、medium 14/17、large 20/23、extraLarge 26/30（非 Material/Material） | AppearanceTokens.qml:249-252 |
| cornerExponent | 3.0（全局） | AppearanceTokens.qml:281 |
| 动效档位 | fast 135/100/120、normal 200/220/180、slow 360/300/260（glass/Material/windows12） | AppearanceTokens.qml:553-557 |

**结论**：shell 侧「深色 tint」不是一个色值，而是 `baseColor 黑 10%` + 环境光混合（`baseColor×0.72 + ambient×0.28`，LiquidGlassSurface.qml:69-71）+ scrim；AppTheme 侧才是逐角色深浅对照。SPEC v1 的材质表需按这两个来源分别立档。

## 10. 工程可查项关闭（原 §3 四项）

1. **KWin 折射默认值**（已解决）：`kwin/glass-effect/src/blur.kcfg:122-147` —— `RefractionStrength 0.0`、`RefractionNormalPow 2.0`、`RefractionEdgeSize 20.0`、`RefractionRGBFringing 1.0`、`RefractionOffsetStrength 0.0`、`MaterialSoftness 0.0`、`MaterialReflectionStrength 0.0`。加载换算在 `settings.cpp:89-95`（strength/20、normalPow/2、edgeSize 原值、fringing/20、offset/2）。同文件其余默认：`BlurStrength 15`、`NoiseStrength 5`、`BlurSaturationCompensation true`、`OnlyQuickshell true`、`WindowClasses "quickshell"`、`CornerExponent 3.0`、`MenuCornerRadius/DockCornerRadius 0.0`（blur.kcfg:11-59）。**折射默认关闭（strength 0）**；blur.cpp:2204-2208 只做 uniform 下发。
2. **PageMotion.qml**（已解决）：仅 5 行——`Foundation.KosPageMotion` 薄包装，`exitDuration: AppearanceTokens.motion.fastDuration`、`enterDuration: motion.normalDuration`（`shell/desktop/modules/common/PageMotion.qml:1-5`）；真身在 `shell/Kos/Ui/foundation/KosPageMotion.qml`。
3. **bar 面板是否都走 ControlCenterGlass**（已解决，**否**）：走 ControlCenterGlass 的只有 `ControlCenterCard.qml`、`NotificationHistoryCard.qml`、`NotificationHistoryPane.qml`、`StatusTooltip.qml`、`SysTray.qml`（`git grep -l ControlCenterGlass HEAD -- shell/desktop/modules/bar`）；`BatteryPanel/BluetoothPanel/NetworkPanel/NetworkTrafficPanel/StatusCollectionPopup/TemperatureSensorPopups` 直接用 `LiquidGlassPanel/KosFloatPanel`（grep 命中）。即 ControlCenterGlass 是「部分面板的配方」，不是 bar 统一入口。
4. **liq 分支动效实验**（已解决）：`git diff --stat origin/main...origin/codex/liquid-animation-experiment` = 19 文件 +821/−95，主体在 **KWin 侧** `kwin/dock-window-animation/`（`liquidmotion.h` 新增 54 行、`dockwindowanimationeffect.cpp` +321、两个测试），加 `kwin/kos-bridge/windowappearance/continuousclip.cpp`（+14）与 QML 侧 `DockIcon.qml`（40 行）、`DockWindowAnimationTargetService.qml`（45 行）小改；`apps/settings` 仅 WindowSettings.cpp/main.qml 微调。**结论：liq 的实验是合成器侧 dock 窗口动画（liquid motion 曲线 + continuous clip），不是 QML 组件动效改造，对 QML 动效 token 体系无直接影响。**

## 11. §3 结算后的剩余清单（仅人工判断项）

- ~~KWin 默认值~~ / ~~PageMotion~~ / ~~bar 面板配方~~ / ~~liq 差异~~ → 已关闭（§10）。
- ~~weather `Main.qml` 的 tint/模糊具体公式~~ → 已关闭（§12.5）。
- ~~LiquidGlassPanel `scrimEnabled/scrimLevel` 下发到合成器的路径~~ → 已关闭（§12.5）。
- ~~纯视觉项（需人工）：tooltip 贴边 -6px 手感、Toast 1600ms 时长是否合适、SessionMenu 比例字号在极端高度下的可读性（对应 SPEC §7 ①②③）~~ → 已关闭（G7 裁定：① Toast B 2600ms + 悬停暂停；② Tooltip B +4px 正间隙；③ SessionMenu A 固定 Footnote 10、生产不改）。

---

# R5 补全（Slider / Switch / NavBar + 两项工程项关闭）

> 以下为本轮追加，行号基于工作树 WT。
> 事实更正：任务书所称「LiquidSwitch」实名 **LiquidGlassSwitch**（qmldir 中无
> LiquidSwitch，`shell/Kos/Ui/controls/qmldir`）；`shell/Kos/Ui/controls/` 与
> `shared/qml/controls/` 逐文件 diff 一致（`diff -rq` 无输出），下文只记一处，
> 两处同源。foundation 侧对应物为 KosSlider / KosSwitch（`shell/Kos/Ui/foundation/`
> 与 `shared/qml/foundation/` 各有同名副本）。

## 12. Slider / Switch / NavBar 盘点

### 12.1 Slider

| 组件 | 来源 | 实现方式 | 关键参数 | 主题适配 | 不一致 |
|---|---|---|---|---|---|
| **LiquidSlider** | WT `shell/Kos/Ui/controls/LiquidSlider.qml`（549 行） | 双形态：iOS 玻璃（默认）/ Material 3，由 `ControlForm.materialForm` 切换（:41），互斥不混绘（:178,:236,:428） | implicit 240×44（:13-14）；`trackHeight 6` r=height/2（:27,:187）；thumb 32×16 六层玻璃：环境阴影→磨砂底 pill→折射渐变→顶部镜面→内沿 rim→accent 溢染（+可选 chromatic，:252-418）；accent `#0a84ff`（:18）；trackColor `rgba(.5,.5,.55,.35)`（:19）；thumbColor 深 `rgba(1,1,1,.38)`/浅 `.72`（:24）；M3 形态：`m3Scale=min(1,h/44)`（:430）、inactive 4/active 16/handle 4×44（:431-434）、state layer hover .10/pressed .16（:465） | 深浅由 `SystemPalette.window` 亮度 <0.5 判定（:20-23），色值组件内双分支硬编码，不走 AppearanceTokens/AppTheme | 时长 270/460/200（:66-67,:247）不在 `AppearanceTokens.motion` 三档内；accent 硬编码同 LiquidSelect 但未进 token；悬停 expansion 0.40（:507）与按钮 0.3（`LiquidGlassButton.qml:25`）不同值 |
| **KosSlider**（foundation，非玻璃） | WT `shell/Kos/Ui/foundation/KosSlider.qml`（103 行） | QtQuick.Controls `Slider` 薄封装 | 220×`AppTheme.controlHeight`（:7-8）；track 高 6 r3 色 `AppTheme.mix(button,mutedText,.12)`（:76-78）；handle 20×20 r10 色 windowRaised、focus 边 3（:88-96）、pressed scale 1.08（:97）；Ctrl+滚轮同协议，`wheelStep` 别名 `stepSize`（量程/100，:19-20）、pixel 10（:22） | AppTheme | 与 LiquidSlider/ColorRampSlider 三份 slider 并行；动效 `AppTheme.motionFast` |
| **ColorRampSlider** | WT `shell/Kos/Ui/controls/ColorRampSlider.qml` | 渐变坡道专用 slider（rampColors 由宿主传） | 250×26（:9-10）；track 8 r=height/2（:22,:101）；thumb 18（:21）；Ctrl+滚轮同协议 wheelStep 0.01/pixel 10（:31-33） | 自定 thumbColor `#ffffff`（:14） | 特殊用途单点使用，不进通用 slider 收编 |

**结论**：通用 slider 收编目标 = LiquidSlider（双形态契约完整：preview/commit/canceled、
Ctrl+滚轮、提交去抖 180ms（:153）、提交后 400ms 屏蔽 x 动画防异步写回跳变（:50-54））；
KosSlider 保留为 foundation 非玻璃形态；ColorRampSlider 维持专用。

### 12.2 Switch

| 组件 | 来源 | 实现方式 | 关键参数 | 主题适配 | 不一致 |
|---|---|---|---|---|---|
| **LiquidGlassSwitch** | WT `shell/Kos/Ui/controls/LiquidGlassSwitch.qml`（393 行） | iOS 玻璃（默认）/ Material 3 双形态（:21），玻璃 thumb 按下溶解为透镜 | implicit 74×32（:29-30）；thumb 44×26 r13（:56-59）；`travel = width-44-6`（:58）；track 色 trackColor→accent 按 progress 渐变（:63-68）r=height/2（:112）；accent `#0a84ff`（:13）；M3 形态 handle 16dp off/24dp on、`m3Scale=min(1,h/32)`（:323-324）；layer 门控仅 expansion>0 或半透明时开 FBO+OpacityMask（:42-49） | 无深浅分支（track 只看 progress，:63-68）；handleOn/Off 色固定（:24-25） | 与 KosSwitch 尺寸/动效两套（74×32 vs 48×28）；disabled opacity 0.5（:96）vs LiquidSlider 0.45（:163） |
| **KosSwitch**（foundation，非玻璃） | WT `shell/Kos/Ui/foundation/KosSwitch.qml`（71 行） | 纯 Rectangle 双态 | 48×28（:10-11）；track r=height/2 色 checked?accent:mix（:34-35）；knob=height-6 圆、边距 3（:44-48）；`motionNormal`/`motionFast` 动效（:41,:56）；无障碍完整（:15-20） | AppTheme | 同名副本在 `shared/qml/foundation/` |

### 12.3 NavBar

| 组件 | 来源 | 实现方式 | 关键参数 | 主题适配 | 不一致 |
|---|---|---|---|---|---|
| **LiquidNavBar** | WT `shell/Kos/Ui/controls/LiquidNavBar.qml`（512 行） | 自 vue-web-liquid-glass 移植（:5-6）；玻璃/白色 pill thumb ↔ 透镜切换，弹簧滑动 | **判定：导航容器**（model/currentIndex/selectionChanged 契约，:21-23,:50），非表单控件，但表面做法属玻璃控件家族（与 LiquidGlassSwitch 同款 lens）。5 档 size presets：tiny 34/small 42/medium 54/large 67/XL 80，thumbScale 1.3（:56-62）；track r=height/2 色 `white@0.10`（:38,:233）；thumb 白 pill `#ffffff/#f5f5f7/#e8e8ed`（:344-346）↔ glass lens（chromatic ±0.5px α.25（:372-387）、edge glow .30（:436）、accent 溢染 .10（:443-445））；accent `#ff453a`（:32）；itemColor `#ffffff`（:37）；item 选中 scale 1.05 / 未选 opacity .6（:464-465）；tooltip delay 600（:278） | 前景硬编码白系（itemColor #ffffff :37），无深浅分支——只适合深色玻璃底 | accent 与 Slider/Switch 的 `#0a84ff` 两个硬编码 accent 并存；label 字号由 preset 算（7/8/9/11/13，:57-61），低于 HIG 最小 10；物理层 16ms Timer（:135-143）是全库唯一帧驱动动画控件 |

### 12.4 controls 目录终查（未进矩阵的文件）

- `ControlForm.qml`（singleton）：`materialForm: false`（:15）——全部 Liquid* 控件双形态总开关。
- `SelectionHighlight.qml`：玻璃选中板（hovered/selected/pressed/dark，cornerRadius=w×0.30、fade 140/press 80，:9-15），自述无模糊/无 shader（:3-5）——玻璃控件家族辅助件。
- `VectorIcon.qml`：纯路径图标绘制（:3-15），非玻璃件。
- `LiquidGlassButton / LiquidSegmentedControl / LiquidTextField / LiquidSelect`：已在 §2/§7。
- 其余（README/qmldir）无组件。

## 12.5 两项工程项关闭（原 §11 前两条）

### weather tint/模糊公式（已解决）

来源 `origin/claude/weather-app:apps/weather/qml/Main.qml`：

- **卡片 tint 公式**（:33-35，拟合依据注释 :30-32）：白天
  `cardGlassRgb = rgb(0, 0.376, 0.824)`（≈深蓝玻璃 (0,96,210)，由 ref-main 截图
  逐像素实测拟合），`cardGlassAlpha` 白天 0.30 / hover(hot) 0.36；**夜间白玻璃**
  α 0.16 / hot 0.21。描边 `white@0.22`（hot 0.32）（:468-469）。`tileRadius 16`
  （:36）。圆片按钮 GlassCircleBg：`white@0.14`（selected 0.27）、border
  0.22/0.30（:41-52）。
- **模糊**：全文件仅两处 `MultiEffect`（:1330-1337、:1362-1369）——上下滚动边缘
  效果：`blurMax 32 / blur 1.0 / saturation 0.2`，26px 高渐变遮罩渐隐到
  `AppTheme.sidebar@0.9`（HIG Materials 滚动边缘模式，注释 :1324-1325）。
- **判定：卡片可迁，滚动边缘不迁**。卡片 = Rectangle+tint+描边，参数
  （tint / tintStrength / radius 16=card 档）一一映射 GlassSurface 契约；但 tint
  是**场景驱动**（白天按天空像素拟合的深蓝、夜间白），不是主题深浅角色，须作为
  显式 tint 传入，不能走 token 默认深浅。滚动边缘 MultiEffect 模糊的是**自身内容**
  （`source: savedLocations`，:1332），不是 backdrop，与 GlassSurface/B 层机制不同类，
  保留为独立「滚动边缘」模式（后续可立项 GlassScrollEdge）。

### LiquidGlassPanel scrim 下发链路（已解决）

链路逐跳（全为 WT 工作树）：

1. 声明：`LiquidGlassPanel.qml:132-181` —— `scrimEnabled`（默认 false）、
   `scrimOpacity 1.0`、`scrimLevel`（默认 "transparent"）→ preset 表（:170-177）：
   readable cap .72/decay 1.0、balanced .47/.75、transparent .22/.5、subtle .15/.45；
   `scrimTint` 黑/白由 `glassFollowsAppearanceMode`+`isDarkTheme` 定（:161-165）；
   `scrimFixed/scrimGraphite/scrimPearl` 变体（:158-160）。
2. 转发：`LiquidGlassPanel.qml:239-246` —— 无条件交给内部 `KosRoundedBlurRegion`
   （cap×scrimOpacity；decay：pearl 4 / graphite 3 / fixed 2 / 普通=presetDecay×opacity）。
3. 协议声明：`KosRoundedBlurRegion.qml:58-61,77-83` —— 交给 `SurfaceShape`
   （`Kos.SurfaceShape 1.0`，插件在 `shell/native/surface-shape/`）。
4. Wire：Wayland 协议 v3 `set_scrim` —— `kwin/glass-effect/src/surfaceshapemanager.h:29-34`
   （SurfaceShape 结构体字段 scrimEnabled/scrimTint/scrimCap/scrimDecay）。
5. 消费：`kwin/glass-effect/src/blur.cpp:195-199` —— scrimMode/scrimCap/scrimDecay/
   scrimLuma* shader uniform 下发。**adaptive 模式**（decay≤1.0）按背景亮度采样
   （scrimLuma framebuffer 链，blur.cpp:1972-2056）；**fixed 模式**（decay>1，
   2/3/4 编码 fixed/graphite/pearl，老合成器安全降级为 adaptive 1，
   `LiquidGlassPanel.qml:155-157` 注）。

**判定：scrim 是合成器侧 shader 机制，不是 QML 背板。** QML 侧另有两条独立变暗
路径，触发条件不同：

- `LiquidGlassSurface.adaptiveDarkScrim`（`LiquidGlassPanel.qml:127` 声明、:283 转发；
  `LiquidGlassSurface.qml:38` 声明、:86 消费）——默认 false，仅宿主显式开启。
- tonal/QML fallback 形态（`paintInQml`，:106-111；body visible :260）自绘表面：
  此时 `shapeEnabled=false`（:237-238）不发布 SurfaceShape，但 scrim 参数仍转发——
  「合成器 frost+scrim × QML 自绘」同开是该组件唯一的潜在双重变暗组合。

SPEC §3.2 的「scrim 单一来源」契约成立：默认路径单一（compositor），双重变暗需
显式 opt-in，无需重议。

## 13. Shell 场景采样组件

Gallery 已迁至 [nextkdeAppDemo](https://github.com/NextKde/nextkdeAppDemo)。下列是
主项目仍保留的 Shell 实现，不是独立 Demo 仓库的组件清单。

| 组件 | 位置 | 作用 | 关键契约 |
|---|---|---|---|
| **GlassBackdrop** | `shell/desktop/modules/common/GlassBackdrop.qml`（`qmldir` singleton） | 宿主声明主窗口内的隐藏采样源 | `sourceItem: Item`；`null` = 所有表面走旧行为。另提供 `scrimCap(level)` / `scrimDecay(level)` / `defaultScrimTint`，是 QML 与 KWin 共用的 preset 表 |
| **scene_liquid.frag** | `shell/desktop/shaders/scene_liquid.frag(.qsb)`（`compile.sh` 烘焙） | 无 KWin 时的采样着色 | 1/6 捕获 + 9 tap 模糊；`adaptiveScrim` 逐式移植；`scrimEnabled/scrimCap/scrimDecay/scrimTint` uniform |

`LiquidGlassSurface` 新增 `backdropItem`（默认 `GlassBackdrop.sourceItem`）、
`scrimEnabled/scrimCap/scrimDecay/scrimTint/scrimLevel`、`sceneSampling` 与
`sceneSourceRect`；场景采样开启时本体 `color` 透明、自适应 scrim 矩形关闭，
由 `ShaderEffect` 一次画完采样 + 着色 + SDF 裁剪。`LiquidGlassPanel` 只转发
有效 preset（`scrimLevel` 默认 `"custom"` 保持旧调用零变化）。

`LiquidGlassPanel.backdropItem` 默认接 `GlassBackdrop.sourceItem`，宿主可显式覆盖。
`sourceItem` 为 `null` 时不启用场景采样。Shell 的原有 KWin 接入保留；独立 Demo
仓库的纯 QML 组件尚未自动替换这些实现。
