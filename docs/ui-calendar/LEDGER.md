# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ12 月视图 ✓（V03 跨天连续条除外）：`CalendarMonthView.qml:56-70` 行列间距 3→0，
  新增 `lineColor`（`AppTheme.text` α .085 light /.13 dark），表头底边 + 每格右/下 1px
  拼成连续 7 列网格；`Main.qml` 删除月视图底部常驻 agenda `KosCard`（145/170 高），
  网格填满主区（V04）。
- 实拍 light 1100×692：`LQ12-month-light.png`（连续网格、today 22 红圈白字、选中 15
  蓝描边淡填充、外月 muted、事件条 "bad" 18px 不裁切）；`LQ12-day-light.png`（day 与
  week 共用表头/时间轴/全天条/事件语言，V05）；`LQ12-crops.png`（mini today 红圈 18
  + 选中灰盘 + 外月 muted，M04）。日志 0 条 QML error/warning。
- V03 跨天事件仍是每格独立 chip（相邻列 12px 断口），连续条未做，见仍差 #1。

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
- [ ] LQ13 全天条：A01–A04（最小 28、行 18、gap 2、inset 2–3、连续跨天、`+N` 溢出）。
- [ ] LQ14 事件块：E01–E06 + N01–N02（tint、左侧 2–3 stripe、inset 4、列 gap 2、今日红线/徽标）。
- [ ] LQ15 窄窗：X01/X02/P03/D11 在 760×540 回归，弹框不裁切、按钮不换行。
- [ ] LQ16 空/密/深色：X04/X05/X03 回归；L0 无玻璃，深色无霓虹事件块。
- [ ] LQ17 底色与 chrome：S01/S04/C05，画布/侧栏层级、窗口圆点三态。
- [ ] LQ18 最终对照：X06 + X07；spec 全量 PENDING 清零、PASS 回归。

## 已改
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
1. 月视图 V03：跨天事件仍是每格独立 chip（相邻列间 12px 断口），未做连续跨天条；
   "+N" 溢出提示已就位但未用密数据实拍。留 LQ13 全天条时一并定。
2. 事件编辑器的组合框（重复/提醒/列表/优先级）仍是 250 底 + 1px 边，与旁边 plain 240
   字段并排有色差（任务编辑器已对齐）；LQ18 前统一。
3. 事件编辑器备注框焦点环仍是 `KosSurface` 内嵌 2px，未换成 task editor 的外扩环。
4. 详情浮层阴影在白底上偏弱；菜单亮卡纯白无参考磨砂色偏、hover r8 偏小、O09 翻转未做；
   与 LQ18 一起复核。
5. 任务编辑器卡片固定 560 高，备注底到保存条留白 151px（事件编辑器 77）；D11 窄窗一并定。
6. tooltip：右缘 clamp 无效（More 标签越过 1100 被裁）、卡右缘外 ~4px 杂散笔画未定位；
   dark 腿、上方翻转、出现/消失连续帧未验证。不要第三次原样重试，改 `contentItem` 绝对
   坐标或 attached ToolTip 方案。
7. P03 的 point 分支、760×540 浮层、出现/消失连续帧未验证（P02 未触及）。
8. 侧栏接缝 224 略清晰、勾号笔画偏细（r3 vs 参考 ~4）；归 LQ17/LQ18。

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

## Next round
LQ13 全天条：A01–A04（最小 28、行 18、gap 2、inset 2–3、连续跨天、`+N` 溢出）。
只改 `CalendarScheduleView.qml` 的全天带；先量参考 week 图里 all-day 行的条高/间距，
不要回头动月视图网格。
