# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ18c spec 回归 13/N：**D12 弹框关闭唯一性 PASS（一处产品改动）**。1100×692 light：
  - 设置面板（`KosSettingsDialog`，日历/任务/天气共用）：原头部有 `×`
    （Accessible "Close settings"）+ footer `完成` 两个关闭口 → **删除头部 `×`**，
    现在唯一关闭是 footer `完成`（Esc 亦关，`closePolicy: CloseOnEscape`）；
    `恢复默认设置` 非关闭。卡面/圆角/内容/footer 布局零变化（`r059-settings.png`）。
  - 事件编辑器：编辑态 footer 保存/取消/删除日程，确认态取消/删除日程，
    卡内无 `×`；删除确认是**同卡内状态切换**（footer 列替换），不是第二个 Popup
    → 无 sheet 套 sheet（`r059-event-edit.png` / `r059-event-confirm.png`）。
  - 任务编辑器 New task：保存/取消，无 `×`（`r059-task-new.png`）；编辑/确认态
    沿用同结构（D05/D07 已实证）。
  - Import/Export：独立顶层系统 FileDialog，打开/取消单一关闭口，背后无日历弹框
    （`spectacle -a`：`r059-import.png`，R46 口径）。
  - 浮层→编辑器：Edit 先 `root.close()` 再 `editRequested()`（`EventDetailsPopover.qml:239-240`），
    不会两层瞬时玻璃叠放。玻璃预算不变 2/2、1/1；日志无 error。

## 上一轮
- LQ18c spec 回归 12/N：**D11 窄窗完整性/自身滚动 PASS（无产品改动）**。
  760×540 事件编辑器卡 380×508、表单 262↔418 由内部 Flickable 滚到上限 156，
  footer 三钮固定完整；任务编辑器编辑态 380×428、243=243 免滚动、New task
  380×436 两行 footer 完整。卡高恒 = min(620/560, parent−32/−64)。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：light week 1100×720 / 760×540；日志无启动回归。
- [x] LQ02 工具栏：`LiquidSurface`(regular) + `LiquidOuterShadow`；持续玻璃 1/2。
- [x] LQ03 分段控件：`LiquidSegmentedControl` materialForm，228×28、pill 231。
- [x] LQ04 工具栏按钮：`LiquidActionButton` + host-owned plain 行；无叠玻璃。
- [x] LQ05 侧栏表面：`LiquidSurface`(regular)，合成 237（持续 2/2）。
- [x] LQ06 侧栏分类：`LiquidCheckBox` 12×12/r3 视觉。
- [x] LQ07 事件编辑器：`LiquidDialog` + `LiquidTextField`，r24/.25 scrim/D05 几何不变。
- [x] LQ08 任务编辑器：同上 + 标签列对齐、组合框 plain、备注外环；D05 三行按钮已验。
- [x] LQ09 详情浮层：`LiquidSurface`（plain α .06、禁叠玻璃）+ `LiquidOuterShadow`，r16。
- [x] LQ10 右键菜单：`MenuActionRow` 行高 30/图标 16/左内 10、plain + hoverFill、1px 分隔线；
  r16 regular E3 卡片、36px 阴影边；light/dark 已拍。O04–O07（O09 未做）。
- [x] LQ11 tooltip：实心卡 + 发丝 + E1、r12/11px/6×10、1000ms、单实例、下方定位 +
  水平 clamp；light/dark 与出现/消失连续帧均已拍，右缘 clamp 生效；上方翻转在当前布局
  不可达（见外推 O09）。
- [x] LQ12 月视图：连续网格/V04 去 agenda 卡/V05 day 共用/V02/M04 已实拍通过；
  V03 跨天连续条未做（见仍差 #4）。
- [x] LQ13 全天条：A01–A04（最小 28、行 24×1.33、gap 2、inset 2、连续跨天、`+N` 溢出）；
  light 实拍通过，dark 未验。
- [x] LQ14a 事件块 E01–E03/E05 + N02：tint 预混同全天条、stripe 3/3、顶部 1px、now 线/pill。
- [x] LQ14b E04：timed 块按真实起点/时长绘制、重叠簇分道（≤3）、短块 30min 可读；light 实拍通过。
- [x] LQ15 窄窗：760×540 回归完成；timed 网格整数列宽 + 宽度随 resize 同步，窄窗不再溢出。
- [x] LQ16 空/密/深色：X04/X05/X03 回归通过；timed 网格改整数列宽 span，1100 右缘余量
  1x 不可辨。
- [x] LQ17 底色与 chrome：S01/S04/C05 通过——侧栏 237/画布 255（dark 41/30）、
  分类行勾选/未勾选可辨 + hover 227/按下 220、圆点 hover/press 与 settings 同为不变，
  工具栏 chrome hover/press 有连续帧；inactive 按代码证据（见外推）。
- [x] LQ18a X06 日历/settings 同尺度对照：PASS（仅取证）。
- [x] LQ18b X07 弹框/浮层/菜单/tooltip 同尺度对照：PASS（仅取证）。
- [x] LQ18c 收尾 5/N：**V03b 续接块预混不透明**——4x 边界 Δ1（原 (205,220,231) 已消），
  单日块复拍未变。V03 线全部结清。
- [x] LQ18c 收尾 6/N：**编辑器组合框 plain 化**——四处 combo 填充 240，与旁侧字段同面，
  1px 边消失。
- [x] LQ18c 收尾 7/N：**事件编辑器备注框焦点环外扩**——聚焦时 r12 环外扩 4px，失焦
  无描边，与任务编辑器逐像素同构。
- [x] LQ18c 收尾 8/N：**N01 补拍**——今天红盘（22×22 红/白字）与选中日灰盘
  （22×22 #E5E5E5/暗字）同屏可辨；now 线 261–262 红、gutter 01:53 pill 可读，
  选中灰不压 now 红。N01 PASS。
- [x] LQ18c 收尾 9/N：**E06 完成态勾标 PASS**——数据链根因是 fixture link 属性前缀写错
  （`X-KOS-` → `X-KDE-KOS-`）；改 fixture 后 timed/全天两种 chip 均 ✓ + strikeout 实拍通过。
- [x] LQ18c 收尾 10/N：**R32 三枚纯黑 chip 修复**——`start` 空串未回退 `due`（落 00:00）
  + `listColor` 返回字符串致混合路径 NaN 变纯黑；改后任务回到 due 时刻并正常着色。
- [x] LQ18c 收尾 11/N：**O09 菜单腿结清**——唯一触发点（工具栏 More）在 1100/760 两档都完整
  落在窗内（卡右 = 窗口−36/−40，阴影槽未被裁切）；垂直翻转不可达，项目顺序翻转 N/A。
- [x] LQ18c 收尾 12/N：**day 视图 TypeError 清零**——`itemColor`/`itemCompleted`/`itemTodoId`
  加 undefined 早退；day/week 往返 5 次日志 0 条 TypeError，两视图目视不变。
- [x] LQ18c 收尾 13/N：**任务编辑器高度内容自适应**——编辑态 560→464，备注→保存
  95→16px；footer 固定高度不变，D05 三行未压。
- [x] LQ18c 收尾 14/N：**菜单 hover 圆角结清**——实测水平内缩 8 ⇒ r_inner 8，原 r8 正确，
  无产品改动；light hover 帧已拍（前：开菜单无 hover；后：首行 hover 244）。
- [x] LQ18c spec 回归 2/N：**D02 弹框圆角 PASS**——四角 r≈24 = `AppTheme.largeRadius`，
  无直角；边缘单层 AA 无内描边。仅取证，无产品改动。
- [x] LQ18c spec 回归 3/N：**D03 双层阴影 PASS**——ambient+key 双层 token 阴影，
  light 近/中/远 174/183/191（目标 170/180/191），卡面 255 不变；cardSurface/1px border
  两条待裁决（见仍差 #1）。
- [x] LQ18c spec 回归 4/N：**D04 弹框文字层级取证**——标题 20 DemiBold 左内 24 PASS；
  正文 13 常规 PASS；字段标签 11px 但 **Normal 非 DemiBold**（spec 不符，见仍差 #3）。
- [x] LQ18c spec 回归 5/N：**D04 标签字重修正**——7 个主字段标签加 DemiBold，墨量翻倍、
  三级层级保持；light/dark 实拍通过。内联 Todo list/Priority 未纳入（见仍差 #3）。
- [x] LQ18c spec 回归 6/N：**D06 按钮高亮/胶囊 PASS**——主按钮实心 accent + 白字、
  次按钮浅灰 + 深/亮字；两枚 349×31、同 r=h/2 胶囊、文字水平零偏、垂直 ≤0.5px；
  light/dark 同构。仅取证，无产品改动（详见 rounds.md R43）。
- [x] LQ18c spec 回归 7/N：**D07 按钮权重 PASS**——编辑态仅保存为实心 accent，取消/删除同 227,229,230；确认态仅取消为实心 accent，删除保持弱权重 + 红字（#d83b3b 色族）。仅取证，无产品改动（详见 rounds.md R44）。
- [x] LQ18c spec 回归 8/N：**D08 按钮三态 PASS**——五枚按钮 hover/pressed 填充各一档
  （保存 69,152,204/85,161,208；中性 215,216,217/204,205,206）、2px focusRing
  (123,182,219) 四边可见、Esc 在编辑/确认两态均关闭。仅加 `objectName`（零视觉改动）。
- [x] LQ18c spec 回归 12/N：**D11 窄窗完整性/自身滚动 PASS**——760×540 事件编辑器卡
  380×508、表单 262/418 由内部 Flickable 滚到 contentY 156，footer 三钮固定完整；
  任务编辑器编辑态 380×428、243=243 免滚动，三行 footer 完整；无产品改动。
- [x] LQ18c spec 回归 13/N：**D12 关闭唯一性 PASS**——设置面板头部重复 `×` 已删
  （footer `完成` 为唯一关闭口）；事件/任务编辑器无 `×`，删除确认是同卡状态非套弹框；
  Import/Export 系统对话框单关闭口。
- [ ] LQ18c spec 全量 PASS 回归：第 1 组 D01–D13（**D01–D12 已取证**；D13 未做，
  D03 的 token/描边待裁决）、第 2 组
  O01–O09（O09 已结清）、
  X01–X05 + P02/P03、tooltip 剩余腿、V03/V03b 月跨天连续条已完成
  → 其余 PENDING 逐条核对清零（N01、E06 已结清）。

## 已改
- LQ18c spec 回归 13/N（D12）：`shared/qml/foundation/KosSettingsDialog.qml:108-116`
  删除 header RowLayout 末尾的 `KosToolButton { text:"×" … onClicked: root.close() }`，
  以注释说明 footer `完成` 是唯一关闭口。头部仍为 ⚙(36)+标题列，`implicitHeight 72`、
  左右 margin、分隔线、内容区、footer（恢复默认设置/完成）、宽度/高度全部零改动。
  该组件为 calendar/todo/weather 共用，三处同时失去重复 `×`。其余弹框零改动：
  事件/任务编辑器的 footer 与删除确认、`EventDetailsPopover` 的 Edit 先关浮层、
  Import/Export 的 FileDialog 声明均未动。
- LQ18c spec 回归 12/N（D11）：**无产品改动**。只驱动/量测：`EventEditorDialog.qml:31-33`
  `height: min(620, parent−32)`、`:503-533` Flickable 与 `:550-563` 轮滚 MouseArea、
  `:388-390` footer 固定高；`CalendarTaskEditorDialog.qml:32-39` `maxDialogHeight =
  min(560, parent−64)` 与 `:434-470` Flickable(`objectName editorScroll`)、`:94-97`
  footer。证据：`probeDialog`（卡 w/h）、`scrollInfo`（Flickable h/contentHeight/contentY）、
  轮滚于空白行间（x350 y240，避开字段）/TASK 直接 `openForTodo(record)` 进三行态。
  帧 `r058-narrow-event-editor3.png`、`r058-ne-scrolled.png`、`r058-narrow-task-edit.png`
  （2x 裁切同名 +2x）；light 760×540。
- LQ18c spec 回归 11/N（D10 退出）：**无产品改动**。只把 harness 的 `probeDialog` 探针
  从 `children` 视觉树改为遍历声明式 `data` 列表——Popup 是 Window 的 QObject 子项，
  不在 contentItem 视觉树中，故 R056 读不到；改后成功直读四个 dialog 的
  `visible/revealProgress/opacity/scale`，以 8ms 采样录得退出曲线。产品 QML、token、
  几何、`KosDialog.qml` 的 reveal 声明零改动。harness 在 tmp，不入库。
- LQ18c spec 回归 10/N（D10 进入）：**无产品改动**。只录进入连续帧并量卡片宽与面亮度；
  `KosDialog.qml:1-33` 的 enter/exit 声明未动（enter: motionNormal 220 OutCubic，
  exit: motionFast 120 InCubic，reduceMotion 时 0）；退出腿本轮已定性。
- LQ18c spec 回归 9/N（D09）：**无产品改动**。审计 `EventEditorDialog.qml:36/410-442/474-492`、
  `CalendarTaskEditorDialog.qml:41/117-148/178-194` 的 保存/取消/删除 与确认态配对，
  以及 `Main.qml:2412-2429` 三个省略号项的 `onTriggered`（`taskEditor.openForTodo(null)` /
  `importDialog.open()` / `exportDialog.open()`）。实点三项均进入下一层，未删任何省略号。
  文件选择器是独立顶层窗口，`captureClient` 截不到，改用 `spectacle -a` 拍活动窗口取证。
- LQ18c spec 回归 8/N（D08）：`EventEditorDialog.qml:411/424/434/476/488` 五枚 `KosButton`
  各加 `objectName`（`eventEditorSaveButton`/`Cancel`/`Delete`、`eventEditorConfirmCancelButton`/
  `ConfirmDeleteButton`），仅供 `pointerObject` 定位，不参与绑定、样式或布局；其余零改动。
  （旧识别文本「保存/取消/删除日程」照常，视觉帧与 R43 逐像素同值。）
- LQ18c spec 回归 7/N（D07）：**无产品改动**。只启动编辑态/确认态实拍并量测
  `EventEditorDialog.qml:410-492` 的既有按钮声明（保存 highlighted+flatPrimary+lightLabel；
  取消 secondary；删除 destructive+secondary），未动任何行。
- LQ18c spec 回归 6/N（D06）：**无产品改动**。`EventEditorDialog.qml:410-429` 已是
  `KosButton{buttonRadius: height/2; highlighted: true; flatPrimary: true; lightLabel: true}`
  + `KosButton{secondary: true}`，填充走 `AppTheme.accent`/`buttonNeutral`，文字用
  `whiteSeed`/`text`；本轮只裁切量测（`R42-d06-btn-*-3x.png`），未动任何行。
- LQ18c spec 回归 5/N（D04）：`EventEditorDialog.qml` 七个主字段标签（`text: qsTr("Title")`
  :584、Start :628、End :664、Location :700、Repeat :784、Reminder :808、Notes :833）
  各在 `font.pixelSize: 11` 后加 `font.weight: Font.DemiBold`。字号、`AppTheme.mutedText`、
  `Layout.preferredWidth: root.labelColumnWidth`、对齐方式、间距、卡面、字段控件、
  按钮组全部零改动。
- LQ18c spec 回归 4/N（D04）：**无产品改动**。只量测 `R40-d03-shadow(.dark).png` 的文字
  bbox/墨高/横笔/墨色，并核对 `EventEditorDialog.qml:42-52` 标题 20 DemiBold、
  `:575/:632/:668/:704/:743/:788/:837` 七个标签均 11px 且无 `font.weight`。
- LQ18c spec 回归 3/N（D03）：`shared/qml/controls/LiquidDialog.qml:17-33` 背景层由单只
  `LiquidOuterShadow`（`#606064`/`#000000`、α .32、softness 20、spread 52、offset 0）
  改为 `shadowAmbient`（softness 24、spread 52、opacity 1）+ `shadowKey`（softness 10、
  spread 28、opacity 1），offset 均 0。α 由 token 自带（light .105/.13、dark .24/.34），
  经 shader 边缘 falloff ×.5 后 light 合计 ≈.1175（旧 .16），实测落点吻合目标梯度。
  `dialogFill`、r24、`LiquidBackdrop`、header/footer 全部零改动。
- LQ18c spec 回归 2/N（D02）：**无产品改动**。`LiquidDialog.qml:18-22` 的 r24 与
  `AppTheme.largeRadius` 一致，本轮只做 4x 角部取证（`R39-d02-*-4x.png`，由 D01 帧裁切）。
- LQ18c spec 回归 1/N（D01）：**无产品改动**。scrim 为 `LiquidDialog.qml:16`
  `Overlay.modal: Rectangle { color: Qt.rgba(0,0,0,0.25) }` 的既有实现，本轮只取证。
- LQ18c 收尾 14/N（菜单 hover 圆角）：**无产品改动**（试改 r12 → 量得水平内缩 8 → 撤回）。
  `Main.qml:1243-1246` 只把旧注释补成实测口径：行 x 已含 `menuSurfaceInset` 4 + `menuRowInset`
  4 = 水平内缩 8，故 `r_inner = max(6,16−8) = 8`。行背景仍 `x: menuRowInset / radius: 8`。
- LQ18c 收尾 13/N（任务编辑器高度）：`CalendarTaskEditorDialog.qml:22-39` 新增
  `maxDialogHeight`（min(560, parent−64)）与 `measuredDialogHeight`（24 + header
  implicit + footer implicit + formLayout implicit），`height =
  Math.min(maxDialogHeight, Math.max(implicitHeight, measuredDialogHeight))`；
  `bottomPadding: 0`（footer 自带上 16 下 16，默认 24 会在备注与按钮间留死白）；
  header Label 加 `id: headerLabel`、footer Item 加 `id: footerBar`；Flickable 加
  `implicitHeight: formLayout.implicitHeight` 供 Dialog 求 implicitHeight。宽度、
  左右/上内边距、背景/阴影、所有行内尺寸零变化。
- LQ18c 收尾 12/N（R35 TypeError）：`Main.qml` `itemColor`/`itemCompleted`/`itemTodoId` 开头
  各加 `if (!item)` 早退（accent / false / ""）。只挡 delegate 拆除窗口，调用方与颜色路径零变化。
- LQ18c 收尾 11/N（O09）：**无产品代码改动**。曾给 `actionsMenu` 加 `objectName` 想用
  `inspectGeometry` 读窗口坐标，实测 Popup 在 overlay 层、`objectNamed` 遍历不到
  （返回 `available:false`），已撤回该行；判定改为靠实拍像素（卡右与窗口右缘距离）。
- LQ18c 收尾 10/N（R32 黑 chip）：`CalendarScheduleView.qml:306-312` timedSpan 起点
  `String(record.start ?? record.due ?? "")` → `String(record.start || record.due || "")`
  （todo 的 start 是空串）；`Main.qml:1640-1666` 新增 `parseListColor()` 并把 `listColor()`
  的两条返回路径都解析为 QColor（6/8 位 hex，非法回退 accent），不再返回字符串。
  其余零改动；事件 chip、月视图事件 chip 实拍不变。
- LQ18c 收尾 9/N 续（E06 数据链）：**无产品代码改动**。fixture
  `profile/pim/calendar.ics` 三条 link 属性前缀 `X-KOS-` → `X-KDE-KOS-`
  （`LINKED-EVENT-ID` ×1、`LINKED-TODO-ID` ×2；tmp 不入库）。证据走私有 D-Bus
  `org.nextkde.Kos.Pim1.eventsForRange`：改前两类事件 `linkedTodoId=""`/`completed=false`，
  改后均指向对应 VTODO 且 `completed=true`。渲染侧零改动。
- LQ18c 收尾 9/N（E06）：`CalendarScheduleView.qml` 全天 chip（ring 之后、标题之前）与
  timed chip（标题行改为 Row）各加 `VectorIcon{name:"check";size:10}`，x 随连续条的
  `allDayJointOverlap` 走、标题左/宽随勾标让 13px；颜色 `chipInk`，勾标随 chip 的 `.5`
  completion opacity 变淡。strikeout 保留，未新增颜色/emoji。**取证未通过（数据链）**。
- LQ18c 收尾 8/N（N01）：**无代码改动**（只取证/量测/判读；选中态用 `date`
  命令设置，未改选中样式）。
- LQ18c 收尾 7/N（备注框焦点环）：`EventEditorDialog.qml:848-865` `KosSurface(focused)`
  换为填充 Rectangle(r10/fieldFill) + 外扩环 Rectangle(margins -4/r12/2px/focusRing/
  visible: descriptionField.activeFocus)，与 `CalendarTaskEditorDialog.qml:665-679` 同式。
- LQ18c 收尾 6/N（组合框 plain）：`EventEditorDialog.qml:23-27` 新增 `fieldFill`
  （light 黑 α.06 / dark 白 α.06，与任务编辑器同式）；`:748/:757/:779/:800` 四个
  `KosComboBox` 传 `fillColor: root.fieldFill`、`cornerRadius: 10`、`strokeWidth: 0`。
  实测四处同框填充 240，与 LiquidTextField 面一致。其余零改动。
- LQ18c 收尾 5/N（V03b）：`CalendarMonthView.qml:232-243` 续接 chip color 改
  `AppTheme.mix(AppTheme.neutralPlane, itemColor, dark?.30:.16)`（不透明预混，止住列发丝
  透出）；单日 chip 仍 `withAlpha`。其余零改动。

## 仍差
1. D03 弹框卡片结构：双层阴影已改为 `shadowAmbient`+`shadowKey`（本轮 PASS）；剩两条
   待裁决——① 面仍硬编码 `#ffffff` / `#29292d` 而非 `cardSurface`（该 token 在玻璃会话下
   α .54 半透明，会透出弹框背后内容且合成 ≠255，见外推）；② 无 1px `border`
   （`alert-macos.png` 无可见描边，字面要求与之冲突）。
2. 浮层/菜单：详情浮层为**单张中性卡**（参考是 246 壳 + 内部白行），面 240 与菜单 255
   差 Δ15（参考 Δ9）；阴影偏弱、菜单亮卡无磨砂色偏。（O09 菜单翻转不可达，见外推；
   tooltip 翻转同理。hover 圆角 r8 已于本轮实测结清，不再列。）
3. D04 内联标签字重：联动待办行的 `Todo list` / `Priority`（`EventEditorDialog.qml:752/:764`）
   仍为 11px Normal，仅在勾选“同时将此日程显示为待办任务”时出现；D04 要求标签 11 DemiBold，
   下轮同步并复拍勾选态。（主字段七标签本轮已改并 PASS。）
（tooltip 各腿已结清：dark、出现/消失连续帧通过；上方翻转在当前布局不可达，见外推；
密集 08:00 簇 45px 道 + 标题 ellipsis 为参考同款外推，已移入 rounds.md，不再列。
V03/V03b 月跨天连续条已结清，细节见 rounds.md R153–R154。）

## 外推待确认
- D12 设置面板删除 `×` 后，标题文本仍从卡内 x≈415 起（图标右缘+间距应为 345），
  实测既不贴图标、也不在卡/列中心；删 × 只能让居中元素右移 ~20px，解释不了 70px，
  判为既有头部布局/字体度量问题，本轮未动（D12 只要求关闭唯一性）。
- `KosSettingsDialog` 是 calendar/todo/weather 共用组件：本轮删 `×` 三处同时生效；
  本轮只实拍 calendar，todo/weather 未复拍（视觉上仅少一个按钮，风险低）。
- D10 reduceMotion 腿未实拍：`AppTheme.qml:72` `reduceMotion: false` 无赋值入口，本环境
  无法切换；按 `:239-241` 的 `motionNormal/Fast = 0` 与 `KosDialog.qml:10` 的
  `scale: reduceMotion ? 1 : …` 判「不动」，仅代码证据。
- D10 退出时 scrim 先于卡片消失：`Overlay.modal` 跟随 popup.opened（close 起点即 false），
  卡片随后仍按 120ms InCubic 淡出（帧 0012 无 scrim、卡 α≈.68）。spec D10 只约定卡片
  scale/时长/曲线，参考图无动效帧，故未改产品。若要求 scrim 与卡片同步淡出，需先裁决：
  自绘遮罩会动到 D01/D03 已 PASS 的层级与点击阻挡。
- D10 抓帧延迟：nativeRecord 的 `pointerDriver.capture` 单帧耗时可达 ~20–100ms，120ms 的
  退出动画可能整段落在两次抓帧之间（R056 的 32 帧未拍到中间帧即此因）；本轮改用 8ms
  属性探针 + 4 帧像素佐证。此后 <150ms 的动效一律配属性采样，不以抓帧缺帧判失败。
- 760×540 + 模态弹框开启时，`captureClient` 的缓冲顶部 ≈148px 是陈旧/翻转内容带
  （R056 窄窗退出帧同款，见 `r056-exit760-0020.png`）。本轮 resize 抖动、重复抓帧均
  不能刷新；改由 `probeDialog` 卡 w/h + 像素量卡底/左右缘 + footer 位置取证，把该
  顶带记为无效区，不据此判产品缺陷。任务编辑器新开/编辑两态均可取到 footer 与表单。
- D10 进入录制的 f22（838ms）先于 f23 呈全显白卡、随后 f23 才回到 alpha .54，判为
  grab/合成器时序伪影（同一 popup 不可能先全显再淡入），不据此改产品。
- D09 的「完成必须有取消」对设置面板不适用：`shared/qml/foundation/KosSettingsDialog.qml:447-451`
  只有 `Done`（关闭）。设置项即时生效（无暂存/提交两态），`Done` 是关闭而非保存，配一个
  “取消”会暗示可回滚却无快照实现。故按语义判不冲突；若要求字面满足，需先裁决是否给设置
  加快照/回滚（产品语义变更）。
- 文件选择器（Import/Export）是独立顶层窗口：主窗 `captureClient` 只含日历窗口，整屏
  `spectacle` 在无人值守 VM 下返回空白（输出被blank），活动窗口 `spectacle -a` 可用。
  故 D09 ② 的 Import/Export 证据是活动窗口截图，不是合成桌面截图。
- D03 的 `cardSurface`：`AppTheme.qml:192-193` = `withAlpha(card, glassActive ? .54/.46 : 1)`。
  评审 VM 是有合成器模糊的玻璃会话，玻璃激活时弹框面会变成 α .54/.46，背后的窗口内容
  与 scrim 会透出，和参考 `alert-macos.png` 的不透明白卡、以及 D01 已实测的 255 冲突；
  即使 `glassActive=false`，`card = mix(windowRaised, accent, .018)`（`:159`）也带 accent
  微染色，不等于 255。故 D03 的“face = cardSurface”按参考图与既有 PASS 行为优先，
  **保留硬编码卡面**。若产品要字面满足 spec，应先裁决“弹框允许半透明/微染色”。
- D03 的 1px `border` 同样按参考图（无可见描边）判为可豁免；两条都需人工裁决，
  不代表实现缺陷。
- 任务编辑器高度：编辑态（三行 footer）实测卡 464、备注→保存 16px；New task（两行 footer）
  与删除确认态未复拍。高度公式随 footer implicitHeight 联动，两态只会更矮（760×540 下限
  476 仍高于 464，不触发滚动），风险低。
- V03 用“每格独立判左右接”而非整周 span 层：只有跨日项在相邻格恰好同一行时才视觉连续。
  fixture 的跨日项都是全天（排序恒在首行）故成立；若一条非 all-day 跨日事件与当天其他
  事件排序交错，相邻格会不同行。整周 span 层数据模型可支撑，但属结构性改动，未做。
- 跨月格连续条在非本月格随整格 0.5 压暗（April 行实测 Mar 30–Apr 1 淡、Apr 2 全亮），
  与 macOS“非本月整格压暗”一致，不是新缺陷。
- 760×540 复拍：`resize` 延迟一次重绘才落地，命令后立即 grab 仍返回 1100×692 缓冲；
  本次以随后的 April / October 两张窄窗实拍为准（内容 760×540 画在缓冲左上）。
- O06：动作菜单里没有破坏性项，故“破坏性项置底 + destructive + 不重复快捷键”按 **N/A**
  判 PASS（无快捷键文本为实拍）；若后续加入“删除日历”类项，必须置底并染 destructive。
- O09 菜单：全仓只有一个 Menu 触发点（工具栏 More；box 1100 下 x1056..1084、760 下 x716..744），
  菜单恒向下展开，卡右缘 = 窗口−36（1100）/ −36..−40（760），36px 阴影槽在窗内，不越界。
  垂直翻转需要“锚点下方空间 < 卡高（≈248）”的生产者，当前布局（工具栏在顶部、min 高 540）
  不存在；水平方向用右对齐 + clamp 而非翻转（卡始终向左生长）。项目顺序翻转仅在翻转发生时
  才需要，判 N/A。未为验证新增底部触发点。
- O09：右缘水平 clamp 已验证（tooltip 卡右停在窗口内 ~10px）；tooltip 垂直翻转**当前布局
  不可达**：带 hint 的锚点只有工具栏（y36–64）与日期组（y81–107），卡底 ≤145；最靠底的
  mini 月箭头（heading y510–536）无 hint，且 540 min 高下该块被 `bottomMargin 12 +
  fixedHeight 170` 钉在底部、heading 底距窗底恒 156 > 28+10+8，故任何允许窗高都不触发。
  代码保留但未实证；不为此新增 hint 或违规缩窗。菜单/浮层仍只做右对齐/内缩，无方向翻转。
- O07：菜单 hover (244,244,245) = 白 255 + `rowHoverFill` α.04；侧栏 237 + 同 token = 227。
  同一 token、不同底，判同一视觉语言；不是新 token。
- D13 的“应用其他窗口仍可交互”：评审 VM 只有一个窗口，无法实拍。按 HIG 语义（modal 只
  冻结本窗口）与 `Dialog.modal: true` 的实现判 PASS，不声称有跨窗口实拍。
- D03 与参考冲突：`alert-macos.png` 卡面没有可见描边，D03 字面却要求 1px `border`。本轮保留
  “无描边 + E4 大软阴影”（贴合参考图），把 D03 记为仍差；若必须满足字面，需裁决描边可见度
  是否可接受。
- X07 色调分层：浮层 240（plain α .06 over neutralPlane）与菜单 255（regular 玻璃压白纸）
  同屏可辨。参考自身也分层（sheet 255 / popover 壳 246 / tooltip 226 / 菜单染色玻璃），
  故按“角色分层”判同一语言；但参考浮层壳内有白行，我们是单卡，观感更平。是否给浮层加
  内部白行需产品/数据模型确认。
- X07 tooltip 面 242 vs 参考实测 226：沿用 O02 的 smallRadius/中性卡 token 优先，不按
  参考图像素改（与 LQ11 外推一致）。
- X07 圆角：参考 popover/menu 角按 2x 约 20pt，我们按 liquid-spec §4 取 16；token 优先。
- X06：settings 以仓库源码（session checkout）启动，橙条“开发者热更新模式”为 dev HUD；
  生产安装副本无此条。chrome/材料对照不受其影响，但截图里它占据内容区。
- X06：settings 的 QML 无窗口圆角自遮罩（app-only 截图直角），calendar 自遮罩 r30；
  KOS 会话里 settings 的圆角应由合成器负责。composited 桌面同屏圆角逐角本轮未拍，
  故只把“圆点/顶带/尺寸/调色”记为 PASS，不把直角截图当作圆角差异。
- C05 inactive 腿未实拍：评审环境只有一个窗口，无法让主窗失焦；`Main.qml` 圆点与
  `apps/settings/main.qml:947-961` 均无 `active` 绑定（失焦外观不变），按“与实际 settings
  相同”判为不变，而非新增灰化。若后续有多窗口评审环境，可补一张失焦帧坐实。
- S04 的“selected row gray r6”按 R096 口径落在 `CategoryRow`：我们的数据模型没有“选中
  日历行”语义（`pim.lists` 只是图例、无选中态），参考图 Personal 行的 226 灰仅作
  hover/按下的 ΔL 标尺；不新造选中语义。
- 本轮 dark 侧栏 41（light 237）为既有 LQ05 玻璃合成值 + 深色外推，无深色参考图。
- tooltip 旧计划“深色实心 rgba(0,0,0,.85)”与 spec O02 / 参考图冲突：参考是中性浅卡 + 轻边框 +
  柔阴影，已按 spec 执行（light `#F2F2F2`、dark `#3C3C3C`、边框 .10/.12）。
- tooltip 延迟按 O01 的“约 1 秒”取 1000ms（旧计划的 500ms 作废）。
- E1（spread 8）作为 tooltip 阴影；9px gutter、可视卡与控件间距 10，保证弹窗不覆盖锚点、
  不抢 hover。参考实测间距约 9–10。
- r12 直接取 spec O02 的 smallRadius；参考图角约 6（2x 角 10–12px），按 token 优先。
- 水平方向用 clamp 而非翻转；O09 的翻转仅实现垂直分支，未验证。
- tooltip 为实心（非玻璃），瞬态玻璃预算仍为菜单 1/1。
- 浮层 r16 取自 liquid-spec §4「弹出框」；参考图实测约 22（2x 图角 45px），按 token 取 16。
- 阴影 level 3（E3）取自 §4；Popup 边界预留 36 = spread 32 + offset 3 + 1。
- 浮层底色 = `neutralPlane` + plain α .06（沿用任务编辑器 `fieldFill` 的 .06 语法）：
  浅色合成 240、深色 43。未改成参考图纯白卡（参考是白卡 + 内部灰 chip，本项目浮层为单卡）。
- 浅色浮层删除 1px 边框（参考浮层无边）；深色保留 white .12 仅作暗底分离。
- 任务编辑器标签列 56、字段填充 240 直接复用事件编辑器实测值；标题上方 12px 间距沿用。
- 任务编辑器保留 560 固定高（与事件编辑器 620 同策略）：内容更短导致留白较大，未擅改。
- `KosComboBox` 新参数默认值 = 旧渲染；仅任务编辑器传 plain 值，其它调用点零变化。
- 菜单数值：菜单宽 220、行高 30、r16、E3、行/卡内边距 4、图标 16、文字 13、悬停内缩 8/r8
  均取 liquid-spec §4「菜单」与 O04；参考图为 2x 风格化示意（卡片 ~358pt、项距 ~39pt），
  未按其绝对尺寸。高亮圆角 8 为表外外推（参考示意约 12）。
- 菜单阴影预留 36 与 LQ09 浮层同法；菜单贴右缘时卡片右缘停在窗口内 36，未做 O09 翻转。
- 1100×720 在 VM 内实际内容高 692，基线按 692。
- 月视图无外部参考图（`.loop/refs/macos-calendar.png` 只含 week；年/月无图）：网格发丝取
  `AppTheme.text` α .085（light）/.13（dark）为表外值；连续网格、表头底线按 macOS 月视图常识外推。
- 月视图选中样式保留整格圆角描边 + 淡蓝填充（既有行为，非本轮引入）；参考无月视图区域，
  未改成“日期圆盘”式选中。
- V04 直接删除底部 agenda 卡：月视图无法再查看“选中日列表”，日程入口保留为格子 chip 与
  悬停 `+` 按钮；如需列表应回 week/day 视图。
- A01 的 “row 18” 按参考 1:1 数值保留为 24：本窗口 hour pitch 是 40 而参考 27，全表统一
  ×1.33 缩放（同 T01）；inset/gap 取 spec 的 2，于是单行带恰为 28，与 “min about 28” 一致。
- KCalendarCore 的 all-day `end` 是**含当天**（实测 Design sprint DTEND 10-17 → end
  10-16）：week 覆盖与详情范围均按含当天处理；timed end 仍为 exclusive。

- 事件 chip 垂直内缩按参考实测：顶 1 ref px、底 0（26 高 / 27 pitch），×1.33 取 1/0；
  水平 fill 距列规则 2 ref px ×1.33 = 3，未按 E02 "about 4" 的字面值。
- timed 填充 α 由 .19 统一到全天条的 .17（light）/.32（dark），E05 一致性优先；与参考
  fill (222,237,254) 的差别来自 accent 色相（项目 accent 偏青），本轮不改全局 accent。
- fixture 只写隔离 profile 的 `calendar.ics`（3 个 10-22 事件），不入库。
- harness 指针限制（R30 发现）：`pointer` press/release 在本 harness 下**不触发
  `TapHandler`**——日期头与全天 chip 两处实测均无响应，而同驱动下分段按钮
  （MouseArea/Button 路径）正常切视图。故不能据此判产品缺陷；选中态改用 `date`
  命令（handleActivation→selectedDate）设置，与点选后视觉状态相同。真机鼠标点选
  日期头仍未实拍。

- R33：`listColor` 改返回 QColor 后，月视图/详情浮层的 todo 着色走同一路径（此前对 todo 的
  `withAlpha`/`mix` 同样拿到 NaN）；月视图本周的 todo chip 被 `+N` 收起，未单独复拍，
  但事件 chip 与前一版逐像素同值。仅直接证据为 timed chip。
- R33：只有 “有 DUE 但无 start 的 todo” 走 due 回退；date-only 的 due 若 `allDay` 为 false
  仍会得 00:00 一小时块（KCalendarCore 对纯日期 DUE 置 allDay，当前 fixture 无此组合）。
- E04 不再需要跨行 z 序：每个小时格只画本格区间的切片，跨行块在相邻格上下相接（上行
  底部贴线、下行 y=0 起），不跨越 delegate 边界，因此不会压到后续行的发丝线。
- E04 短块最短可读 30min（fill 18px）为表外外推：参考图无 <1h 事件；E03 要求"短块一行
  可读"，11px 标题 + 2px 顶场约需 18px；visualEnd 仍被同 lane 下一块起点截断。
- E04 小时接缝按"整体块"处理：首段上角、末段下角 r3，中间方角；同 lane 首尾相接的两块
  之间保留下一块的 2px 顶场（实测 10:15 前留 2px 白）。
- E04 重叠块按簇内 lane 数平分宽度：单独块仍满宽，只有真正重叠的时段才分道；lane 上限 3
  与既有 +N 规则一致。标题/时间行只画首段，跨行后段为纯填充（参考多小时块同形）。
- LQ15 整数列宽是表外修正：分数列宽被 QQuickGridLayout 向上取整，760 下 7×102+52=766
  会溢出 6px。选 floor 而非“把余数塞给最后一列”：GridLayout 各列等宽，加宽末列会让所有
  列跟着变宽；余数留在最右画布（760 下 1px、1100 下 5px）。
- LQ16：1100 下右缘 5px 为画布色（light 255 vs 周末 field 249；dark 30 vs 37），
  1x 实拍不可辨、4x 裁切可见。若 LQ18 判不可接受，只有两条路：末列吸收余量（七列不再
  等宽、牵动 16 处 geometry）或逐列宽度函数（同上）；本轮不选。
- LQ16：密集簇 3 道时标题只余 3 字 + ellipsis 属参考同款行为（参考无重叠密集图，按 macOS
  窄事件惯例外推），不算 X05 的“unintended overlap”。

## Next round
LQ18c spec 回归 14/N：**D13 弹框出现时父窗口内容可辨认（变暗而非被覆盖）**。事件编辑器
打开时量 scrim 合成（参考：父窗内容仍是可辨认的灰、非纯黑）与卡周边梯度，复用 D01 的
scrim 帧口径；同时用代码证据结“应用其他窗口仍可交互”（VM 单窗口，`Dialog.modal: true`
只冻结本窗口，按外推判 PASS，不声称实拍）。不动 D12 刚改的 `KosSettingsDialog` 头部结构，
不动 D11 的卡高/Flickable/footer。若 scrim 合成与之前 D01 实测不一致，只取证不改。
