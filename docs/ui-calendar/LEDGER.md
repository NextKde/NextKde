# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ14a 事件块（light 1100×692；fixture：今天 10-22 的 09:00–11:00 2h + 09:30–10:15
  重叠 + 10:15–10:30 短会）：
  - E02 垂直内缩：参考 chip 在 27px pitch 内 26 高——顶部 1px 场、底部贴小时线；
    原来 host 上下 margin 3 让 38 高 chip 压进下一行。改为 top 2 / bottom 0（cell 内
    y=2 ⇒ 顶部留 1px，底部 38px 贴线），`CalendarScheduleView.qml:987-999`。
  - E05 一致性：timed 原 `withAlpha(accent,.19)`（216,234,245，且在周末底上二次合成），
    改为与全天条同款 `mix(allDayBackdrop, accent, .17/.32)` 不透明预混；实测填充
    (220,235,245)，与全天条逐像素一致。
  - E01/E02 stripe：参考条 x491–493 = 2.4px、距 fill 边 2px，×1.33 → 3/3，现有值
    不动（R-SCALE）；两侧 inset 2 ref px ×1.33 = 3，现有 margin 3 不动（E02 的
    "about 4" 以参考实测为准）。
  - E03：标题 11 Medium、顶部对齐、ElideRight；10:15 短会两行仍可读。
  - N01/N02 实拍：今天 10-22 红圈；23:28 红 pill、today 列满强红、其余列 α.10、
    今日左规则红点，y=23*40+18.7 正确。
  - 实拍：`LQ14-week-light-v3.png`、`LQ14-chip-crop-v3.png`、`LQ14-now-light-v1.png`、
    `LQ14-now-crop-v1.png`。日志仅既有 Main.qml:1653 TypeError 两条。

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
- [ ] LQ14b E04：timed 块按开始分钟偏移、按时长跨行（当前所有 chip 固定 38 高）。
- [ ] LQ15 窄窗：X01/X02/P03/D11 在 760×540 回归，弹框不裁切、按钮不换行。
- [ ] LQ16 空/密/深色：X04/X05/X03 回归；L0 无玻璃，深色无霓虹事件块。
- [ ] LQ17 底色与 chrome：S01/S04/C05，画布/侧栏层级、窗口圆点三态。
- [ ] LQ18 最终对照：X06 + X07；spec 全量 PENDING 清零、PASS 回归。

## 已改
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
1. E04：timed 块仍固定 38 高、只画在开始小时那一格——09:00–11:00 的 2h 事件不跨行，
   09:30 开始与 09:00 同样贴小时线；时长与半小时起点都未反映。下一轮 LQ14b。
2. E06 未验证：completed timed 项只有 strikeout + opacity .5，没有独立完成勾标；
   参考图没有 todo 事件，需按 HIG/task 行语言补勾标后再判。
3. N01 部分验证：今天红圈与 now 线同屏已拍；"今天 + 另一选中日"同时出现的灰/描边
   对比未重拍（本轮未改选中样式）。
4. 月视图 V03：跨天事件仍是每格独立 chip（相邻列间断口），月格连续条未做；留 LQ18。
5. 切到 day 视图时 `Main.qml:1653 itemColor` 对 undefined item 报两次 TypeError（瞬时，
   渲染无异常；疑似 delegate 拆除时序，非本轮引入）。待 LQ15 回归时消掉。
6. 事件编辑器：组合框仍是 250 底 + 1px 边（与旁边 plain 240 有色差）；备注框焦点环仍是
   2px 内嵌，未换 task editor 的外扩环。LQ18 前统一。
7. tooltip：右缘 clamp 无效、卡右 ~4px 杂散笔画未定位；dark 腿、上方翻转、出现/消失
   连续帧未验证。不要第三次原样重试。
8. 浮层/菜单：详情阴影偏弱、菜单亮卡无磨砂色偏/hover r8 偏小、O09 翻转未做；任务编辑器
   固定 560 高留白 151px。归 LQ15/LQ18。

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

## Next round
LQ14b E04：让 timed 块反映开始分钟与时长——先加 item 起止分钟访问器，单列内按区间给
chip y/height（跨行用 z 压住后续行的发丝线），重叠用区间分道；只动 timed 块，不碰全天带
与 N02。若必须整列 interval 重排（跨行重叠会让当前逐格 Repeater 打架），先记录再拆轮。
