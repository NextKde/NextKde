# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ15 窄窗 760×540 回归（X01/X02/P03/D11）：
  - 发现：timed GridLayout 的列宽 `(760-52)/7=101.14` 被 QQuickGridLayout 逐列向上取整
    为 102，网格实际 766 宽 > 窗口，最后一列右缘与 chip 被裁出窗口（1100 下同样 +2px，
    只是不明显）；且 `width: timelineScroll.availableWidth` 在实时 resize 后不更新
    （900 宽时网格仍 766，而表头已 121/列），窄→宽会整片错位。
  - 修复：`CalendarScheduleView.qml:47-55` `dayColumnWidth` 取 `Math.floor`（整数列宽）；
    `:858-868` 网格宽度改绑 `root.width`，resize 后与表头/全天带同拍。
  - 实拍：760 网格线 x=52/153/254/355/457/558/659/759（pitch 101，不再溢出），最后一列
    chip 右内缩 3px 完整可见；工具栏/大标题/星期行/分段（266..494，中心 380）无碰撞裁切；
    侧栏折叠时画布自 x=0 铺满、无接缝。详情浮层与编辑器在 540 高内完整可见（上下边距 27），
    按钮单行不换行。geometry 日志：网格宽 760→900 随 resize 同步。
  - 证据：`LQ15-week-760-light-v5.png`、`LQ15-week-760-light-v4.png`（修复后窄窗）、
    `LQ15-details-760-light.png`、`LQ15-editor-760-light.png`。
  - `LQ15-week-900-light.png` 因 grabWindow 在 resize 中取到旧 760 缓冲而无效，已保留但不作
    证据；900 宽只以 geometry 日志确认列宽 121/网格 900。
  - LQ14b 细节已移入 rounds.md 尾部。

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
- [ ] LQ16 空/密/深色：X04/X05/X03 回归；L0 无玻璃，深色无霓虹事件块。
- [ ] LQ17 底色与 chrome：S01/S04/C05，画布/侧栏层级、窗口圆点三态。
- [ ] LQ18 最终对照：X06 + X07；spec 全量 PENDING 清零、PASS 回归。

## 已改
- LQ15：`CalendarScheduleView.qml:47-55` 整数列宽（`Math.floor`）；`:858-868` timed 网格宽度
  绑 `root.width`。窄窗下 7 列 + 52 gutter 恰好 ≤ 视口，表头/全天/timed 共用同一整数列宽。
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
6. tooltip：右缘 clamp 无效、卡右 ~4px 杂散笔画未定位；dark 腿、上方翻转、出现/消失
   连续帧未验证。不要第三次原样重试。
7. 浮层/菜单：详情阴影偏弱、菜单亮卡无磨砂色偏/hover r8 偏小、O09 翻转未做；任务编辑器
   固定 560 高留白 151px。归 LQ15/LQ18。
8. LQ15：D11 的“长内容/内部滚动”分支本轮未重测（现有 fixture 无长备注）；整数列宽在
   1100/900 会留 ≤5px 右缘画布色（无裁切），需在 LQ18 宽窗全量回归时确认是否可接受。

## 外推待确认
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
  列跟着变宽；余数留在最右画布（760 下 1px、1100 下 5px），不可见。

## Next round
LQ16 空/密/深色：X04/X05/X03 回归——空日历保留完整网格/时间标尺且无占位大图；密集日
标题不交叠、全天/timed 边界清楚；dark 下 L0 无玻璃、事件块无霓虹。顺带确认整数列宽在
1100 宽窗的右缘 5px 不留可见白条。
