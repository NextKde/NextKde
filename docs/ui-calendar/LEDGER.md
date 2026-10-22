# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ17 底色与 chrome（S01/S04/C05）：
  - S01 light：侧栏玻璃合成 **237**（参考侧栏实测 237，逐像素相等）、画布 **255**，
    R==G==B、上下无渐变/无蓝偏；seam 单发丝。dark：侧栏 41、画布 30（侧栏比画布亮 11，
    层级与 light 反向正确，无参考图、按既有外推）。
  - S04 light：`CategoryRow` 勾选=实心+白勾、未勾=彩色空心边框（同屏实拍可辨）；
    hover 背景 227（Δ10），按下背景 220（Δ17）；参考选中行为 226（Δ11），
    hover 比选中亮、按下比选中暗，三级次序成立；圆角沿用既有 r6。
  - S04 本轮补的差：`CategoryRow`/`SidebarRow` 原来只有 hover，按下无任何反馈
    （与菜单行不一致）。两处 background 增加 `down → rowPressFill`。
  - C05 窗口圆点：hover/press 帧圆点颜色逐像素不变（255,119,112），无浮起/描边；
    与 `apps/settings/main.qml:947-961` 一致（settings 也无 hover/press 视觉）。
    无第二组胶囊/重复窗口控件；工具栏仍是单胶囊。
  - C05 工具栏 chrome（shared liquid 按钮）：dark 常态 34 → hover 47 → press 59，
    三段连续帧；press 有缩小位移（shared 控件）。
  - inactive 腿：单窗口环境无法失焦实拍；源码两侧都无 `active` 绑定，语义上与 settings
    一致，按代码证据记入 spec，不打实拍 PASS。
  - 证据：LQ17-light-sidebar / LQ17-row-hover / LQ17-row-press / LQ17-row-after /
    LQ17-dots-hover-6x / LQ17-dots-press-6x / LQ17-dots-hp / LQ17-dark-row-hp /
    LQ17-dark-sidebar / LQ17-dark-chrome-hover / LQ17-dark-chrome-press。

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
- [ ] LQ18 最终对照：X06 + X07；spec 全量 PENDING 清零、PASS 回归。

## 已改
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
6. tooltip：右缘 clamp 无效、卡右 ~4px 杂散笔画未定位；dark 腿、上方翻转、出现/消失
   连续帧未验证。不要第三次原样重试。
7. 浮层/菜单：详情阴影偏弱、菜单亮卡无磨砂色偏/hover r8 偏小、O09 翻转未做；任务编辑器
   固定 560 高留白 151px。归 LQ15/LQ18。
8. 密集 08:00 簇（4 事件/3 道）：每道约 45px，标题只剩 "O…/M…"（有意 ellipsis、无交叠）；
   若要求可辨识需窄道减 padding/字号，未做。dark 右缘 5px 画布条 1x 不可辨（见外推）。

## 外推待确认
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
LQ18 最终对照：X06 + X07，并做 spec 全量 PASS 回归与 PENDING 清零（E06/N01/V03/编辑器
色差/tooltip 右缘/浮层阴影等仍差按序处理或明确外推）。先跑一遍全量视图与 light/dark
1100/760 四组合，逐条回填 spec 状态；只做其中第一条，不打包。
