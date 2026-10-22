# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ18c 收尾 13/N：**任务编辑器高度内容自适应**。固定 560 → `height =
  min(560, max(implicitHeight, 测值))` 且 `bottomPadding: 0`；编辑态卡片 560→464，
  备注框底到保存条 95→16px（两轮实拍量得：改前卡 78..637、表单止 405、保存条 517；
  改后卡 123..588、表单止 451、保存条 466）。标题行/字段/备注/三行 footer 行内尺寸
  零变化，footer 高度固定故 D05 不被压。light 实拍 `R36-before-editor.png` /
  `R36-final-editor.png`（1100×692，2026-04-01 day，openItem todo → 编辑）。
  New task 两行 footer / 删除确认态未复拍。

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
- [ ] LQ18c spec 全量 PASS 回归：第 1 组 D01–D13（D03 仍差）、第 2 组 O01–O09（**O09 已结清**）、
  X01–X05 + P02/P03、tooltip 剩余腿、V03/V03b 月跨天连续条已完成
  → 其余 PENDING 逐条核对清零（N01、E06 已结清）。

## 已改
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
1. D03 弹框卡片结构：面为硬编码 `#ffffff`（非 `cardSurface`）、无 1px `border`、阴影是单只
   `LiquidOuterShadow`（E4 自定义）而非 `shadowAmbient`+`shadowKey` 双层。视觉无硬边，但三条
   只中“软阴影”一条；改机制不是 token 级，需先定是否保留 LQ07 的 E4 方案。
2. 浮层/菜单：详情浮层为**单张中性卡**（参考是 246 壳 + 内部白行），面 240 与菜单 255
   差 Δ15（参考 Δ9）；阴影偏弱、菜单亮卡无磨砂色偏/hover r8 偏小。（O09 菜单翻转不可达，
   见外推；tooltip 翻转同理。）
（tooltip 各腿已结清：dark、出现/消失连续帧通过；上方翻转在当前布局不可达，见外推；
密集 08:00 簇 45px 道 + 标题 ellipsis 为参考同款外推，已移入 rounds.md，不再列。
V03/V03b 月跨天连续条已结清，细节见 rounds.md R153–R154。）

## 外推待确认
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
菜单 hover 高亮圆角结清（仍差 #2 的最后一小块）：量 `MenuActionRow` 的 hover 矩形 inset
（state 旧记 8/r8）：若 inset 确为 8，按 r_inner = max(6, 16−8) = 8 判**已正确**、只补记录；
若实际为 4，则改为 r12。light 下 `pointerObject` move 到菜单某行拍 hover 帧（用
`toolbarMore` 开菜单），不重排菜单几何。D03 需产品裁决、浮层内部白行需数据模型确认，均不动。
