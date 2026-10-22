# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ18b `X07` 弹框/浮层/菜单/tooltip 同尺度对照：**PASS（仅取证，无代码改动）**。
  - 同一 light 会话、1100×692、day view 2026-04-02，按面逐张实拍（瞬态玻璃 ≤1，不能真同屏）：
    `openItem "Morning"` → 详情浮层；浮层「编辑」(679,438) → 事件编辑弹框（取消 557,596）；
    More (1070,50) → 菜单；hover toolbarAdd ≥1s → tooltip。四张再 1:1 拼版。
  - 实测卡面/边/圆角/字级/阴影（像素值）：
    - Dialog：面 **255**、无描边、r24、标题 **20 DemiBold**、自定义大阴影（spread 52、
      softness 20、α .32）。
    - Popover：面 **240**、亮色描边透明、r16、标题 **15 DemiBold**、E3。
    - Menu：面 **255**（regular 玻璃压白纸无可见色偏）、玻璃 rim、r16、行字 **13**、E3。
    - Tooltip：面 **242**、发丝 **217（黑 .10 压 242）**、r12、字 **11**、E1。
  - 节奏判定：圆角 24 > 16 = 16 > 12、字级 20 > 15 > 13 > 11、阴影 E1–E3 + 弹框更大一档，
    四个面是同一套梯子；描边策略（弹框/浮层无、菜单 rim、tooltip 发丝）与参考一致。
  - 两个色调层：白卡（弹框/菜单 255）与中性卡（浮层 240 / tooltip 242）。参考自身同样
    分层——sheet 255、popover 壳 246 + 内部白行、tooltip 226、菜单为染色玻璃——按角色分层
    不构成“两套设计语言”，判 PASS。
  - 残留（已记仍差/外推，不在本轮改）：浮层是单张中性卡（参考壳内还有白行），与菜单的
    面差 Δ15（参考 Δ9）；亮色菜单无磨砂色偏（LQ10 既有）；tooltip 242 比参考 226 浅，
    按 O02 token 优先。
  - 取证：`X07-base-day.png`、`X07-dialog.png`、`X07-popover.png`、`X07-menu.png`、
    `X07-tooltip.png`、`X07-tooltip-8x.png`、`X07-surfaces-1x.png`（1:1 + 5x 角 + 色板）；
    入库副本 `docs/ui-calendar/x07-surfaces-light.png`。
  - 日志：仅既有 `Main.qml:1655` TypeError 两条（打开弹框时，非本轮引入）。
  - Bash ~20/25（启动 + 4 组驱动 + PIL 量测/拼版两次）。

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
  上方翻转 + 水平 clamp；light 已拍。**右侧 clamp 未生效、dark/翻转分支未验证**（见仍差）。
- [x] LQ12 月视图：连续网格/V04 去 agenda 卡/V05 day 共用/V02/M04 已实拍通过；
  V03 跨天连续条未做（见仍差 #1）。
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
- [ ] LQ18c spec 全量 PASS 回归：D01–D13 → O01–O09 → 其余 PENDING 逐条复拍/代码核对，
  落 PASS/仍差并把 PENDING 清零。

## 已改
- LQ18b：**无代码改动**；产出四个 L2 面的同尺度取证与判读。
- LQ18a：**无代码改动**；settings 以仓库源码跑起（`KOS_SHELL_DIR`），产出同尺度并排证据。
- LQ17：`Main.qml:368-370` `SidebarRow`、`:492-493` `CategoryRow` background 增加
  `row.down → rowPressFill`（原只有 hover；菜单行早已有按下态，本轮补齐侧栏两类行）。
- LQ16：`CalendarScheduleView.qml:866-875` timed 网格宽 = `gutter + dayCount*dayColumnWidth`
  （1100→1095），不再把右缘余量摊进列；header/all-day/timed 三区边界逐像素一致。
- LQ15：`CalendarScheduleView.qml:47-55` 整数列宽（`Math.floor`）；`:866` 宽度随 root 变化。
- LQ14b：`CalendarScheduleView.qml` `minutesOfDay/timedSpan/timedLayout/timedBlocksFor` 区间
  布局（簇内 lane、≤3、最短 30min）；hour cell 改用 `timedBlocksFor`；delegate 按 segment
  给 y/height、首段顶场/末段贴线、标题仅首段、stripe 跨行连续、外角 r3 接缝方角、+N 由隐藏
  lane 决定。细节移入 rounds.md。
- LQ14a：`CalendarScheduleView.qml:987-999` chipHost 上 2/下 0；`:1035-1044` timed 填充改为
  全天条同款 `mix(allDayBackdrop, itemColor, .17/.32)`（E05 同色）。细节移入 rounds.md。
- LQ13：`CalendarScheduleView.qml:56-97` 全天带 gap/inset 2、一行 28、三行 80；
  `:220-245` `lastCoveredDay` = 含当天 end；`Main.qml:1419-1434` all-day 末天不再减一
  （timed 不变），`:1574-1590` 全天日期范围同步。细节移入 rounds.md。
- LQ12：`apps/calendar/qml/CalendarMonthView.qml:56-70` 网格无间距 + `lineColor` hairlines；
  `:69-90` 表头底边线；`:255-280` 每格右/下 1px 线；`Main.qml` 月页删除底部 agenda
  `KosCard`（原 145/170 高）。细节移入 rounds.md。
- LQ11：`Main.qml:40-43` help tag 状态；`:245-262` tooltip token；`:924/:1000/:1033`
  三个组件的 hover/press 钩子（移除 attached ToolTip）；`:1090-1136` 自绘 Popup
  （卡/发丝/E1/r12/11px/6×10）；`:1137-1173` 延迟 1000ms、`TextMetrics`、arm/disarm/open；
  `:1178-1205` 定位（下方优先、越界翻转/clamp）。light 证据见 rounds.md。
- LQ10：`Main.qml` 菜单 token、`rowPressFill`、`MenuActionRow`/`MenuGroupSeparator`、触发定位 +
  自绘 `Menu`（卡片/阴影/玻璃、四项图标、分组）。细节移入 rounds.md。
- LQ08：`apps/calendar/qml/CalendarTaskEditorDialog.qml:8,26-46,53` 基类/标题/内边距；
  字段 `:500-590`；备注 `:621-670`；`shared/qml/foundation/KosComboBox.qml:4-21` 新增外观参数。
- LQ07：`EventEditorDialog.qml:8` 基类 `LiquidDialog`；`LiquidTextField.invalid` 新增。
- LQ02–LQ06 详见 rounds.md（工具栏/分段/按钮/侧栏/勾选）。
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件与 shaders。

## 仍差
1. E06 未验证：completed timed 项只有 strikeout + opacity .5，没有独立完成勾标；
   参考图没有 todo 事件，需按 HIG/task 行语言补勾标后再判。
2. N01 部分验证：今天红圈与 now 线同屏已拍；"今天 + 另一选中日"同时出现的灰/描边
   对比未重拍（本轮未改选中样式）。
3. 月视图 V03：跨天事件仍是每格独立 chip（相邻列间断口），月格连续条未做；留 LQ18。
4. 切到 day 视图时 `Main.qml:1653 itemColor` 对 undefined item 报两次 TypeError（瞬时，
   渲染无异常；疑似 delegate 拆除时序，非本轮引入）。待 LQ15 回归时消掉。
5. 事件编辑器：组合框仍是 250 底 + 1px 边（与旁边 plain 240 有色差）；备注框焦点环仍是
   2px 内嵌，未换 task editor 的外扩环。LQ18 前统一。
6. tooltip：右缘 clamp 自 LQ11 起仍无效（本轮未复验）；卡右 ~4px“杂散笔画”本轮已定位为
   下方页面大标题字头/字尾在 62px 小卡两侧露出，**不是描边错误**；dark 腿、上方翻转、
   出现/消失连续帧未验证。
7. 浮层/菜单：详情浮层为**单张中性卡**（参考是 246 壳 + 内部白行），面 240 与菜单 255
   差 Δ15（参考 Δ9）；阴影偏弱、菜单亮卡无磨砂色偏/hover r8 偏小、O09 翻转未做；任务编辑器
   固定 560 高留白 151px。归 LQ18c。
8. 密集 08:00 簇（4 事件/3 道）：每道约 45px，标题只剩 "O…/M…"（有意 ellipsis、无交叠）；
   若要求可辨识需窄道减 padding/字号，未做。dark 右缘 5px 画布条 1x 不可辨（见外推）。

## 外推待确认
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
LQ18c `spec 全量 PASS 回归`第 1 组：D01–D13（弹框）。同一 light 会话按
`openItem → 编辑` 打开事件编辑弹框，逐条核对：scrim 可辨、圆角 token、表面/描边/双层阴影、
标题/正文/标签字级、按钮竖排等宽同高、主/次/破坏性层级、hover/press/focus、Esc、
窄窗 760×540 不裁切、无 sheet 套 sheet、父窗仍可辨。每条落 PASS 或写清仍差；不做新实现
（除非是零成本 token 偏差）。之后再做 O01–O09 与其余 PENDING。
