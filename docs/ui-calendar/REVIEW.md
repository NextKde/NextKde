# 日历 app 代码 review + HIG 优化点

第二轮全量代码 review（分支 `codex/calendar-ui-iter-20261016`）。
finding 格式：`- [P0|P1|P2] file:line — 事实（含实测数值）。影响。建议：…`
区域划分与轮次记录见 `tmp/ui-acceptance/calendar/state.md`（不入库）。

## R1 — `Main.qml:1-1400`（tokens、日期/文案 helper、基础组件）

### 已复核的既有线索
- 线索 3（`Main.qml:1315` formatClock12 硬编码 AM/PM）：**成立**，见 F1。
- 线索 13（动画是否有 `AppTheme.reduceMotion` 守卫）：**部分成立**。`AppTheme`
  本身有降级通道（`shared/qml/foundation/AppTheme.qml:26,179-182`：
  `motionFast/motionNormal` 在 reduceMotion 下为 0，`hoverScale/pressScale` 为 1），
  凡走 `AppTheme.motionFast` 的动画自动守卫（如 `Main.qml:392` 的开关滑块）。
  但 R1 区间内 GlassSurface 的三处 Behavior 用**硬编码** `pressDuration: 150`
  （`Main.qml:248, 675-677, 802-803`），不经过任何守卫。1955/2104 行留待 R2。

### Findings
- [P1] `Main.qml:120-123` — 浅色腿 `labelSecondary`（`#3C3C43 @60%`）实测对比度：
  白色内容面上合成色 (138,138,142) → **3.44:1**；侧栏 `#E4E4E4` 上 → **3.14:1**；
  搜索框 `#D2D2D2` 底上 → **2.91:1**（python 按 WCAG 合成+公式算）。全部低于
  ≤17pt 文本要求的 4.5:1，而这些 secondary 标签的字号是 13–15px。深色腿单独验
  过：`#F2F2F2 @58%` 在 `#1E1E1E`/`#282828` 上为 5.85/5.44:1，达标——**只有浅色
  腿不达标**。影响：占位符、行尾 detail、分组标题等浅色模式下可读性不足。
  建议：浅色腿把 alpha 提到 ~0.78（合成后 ≈4.6:1）或提供 Increase Contrast 变体。
- [P1] `Main.qml:1309-1319` — `formatClock12` 无条件 12 小时制且 `suffix = "PM" : "AM"`
  硬编码英文（1336 行同理判 `"AM"/"PM"`），完全不走 `Qt.locale()`，也不看系统
  12/24 偏好。影响：24 小时制 locale（含中文环境）的 chip 副标题全部显示英文
  AM/PM；与 app 内 24 小时制的其它文案冲突（见 R4 线索 2、R2 线索 16）。
  建议：按 locale 12/24 偏好分流，meridiem 用 `Qt.locale().pmText/amText`。
- [P1] `Main.qml:421-423` — `CategoryRow` 设了 `Accessible.role: Accessible.CheckBox`
  却**从未设 `Accessible.checked`**（全仓 grep `Accessible.checked` 0 处命中）。
  选中态只靠 12px 方块填色表达。影响：VoiceOver 用户听到"复选框"但永远听不到
  勾选状态；也违反"不许只靠颜色传达信息"（这里连形状都变了但无障碍层不知道）。
  建议：`Accessible.checked: row.checked`。
- [P1] `Main.qml:281-407` — `SidebarRow`（含 `showSwitch` 的开关行）没有任何
  `Accessible.role` 覆盖：AbstractButton 默认 role 是按钮，开关视觉（42x26 track
  + 滑块）对辅助技术不可见，`checked` 状态也不暴露（无 `Accessible.checked`）。
  影响：日历/任务列表开关的开关状态对 VoiceOver 完全不可知。建议：
  showSwitch 行改 `Accessible.role: Accessible.CheckBox` + `Accessible.checked`。
- [P1] `Main.qml:527-560` — `SidebarSearch` 的 `TextInput` 无 `Accessible.name`
  也无 role；唯一能读到的信息是旁边的占位符 Label。影响：VoiceOver 聚焦该输入
  框时无可读名称，搜索入口被阻断。建议：`Accessible.name: qsTr("Search")`、
  `Accessible.role: Accessible.EditableText`（同类的 1968 行 R2 复核）。
- [P2] `Main.qml:1126` — `handleActivation` 的 `--view` 只接受
  `["month", "week", "day"]`，而 `activeView`（:256）支持 4 个视图。`--view year`
  被静默忽略。影响：与线索 8（Year 无快捷键）同源——第四视图既无键盘路径也无
  激活路径。建议：数组补 `"year"`。
- [P2] `Main.qml:675-677, 802-803` — GlassSurface hover/press 的 Behavior 用硬编码
  `pressDuration: 150`（:248），且 pressScale 0.97 是缩放动画；不经过
  `AppTheme.reduceMotion`。HIG Reduce Motion：缩放/位移动画应退化为淡入淡出。
  建议：时长改绑 `AppTheme.motionNormal` 类 token，或按下缩放直接乘
  `reduceMotion ? 1 : pressScale`。
- [P2] `Main.qml:1393-1404` — `itemDetailsRange` 对当日计时事件返回
  `dateLine · itemTime(item)`，而 `itemTime`（:1353）返回 24 小时制 `HH:MM` 原串；
  同一 app 的 chip 副标题（itemSecondary）是 12 小时制。影响：详情浮层与 chip
  两套时间制式并存。建议：浮层时间统一走 locale 格式化（与 F1 一并修）。
- [P2] `Main.qml:531, 533, 544` — `SidebarSearch` 内部边距硬编码 47，而
  `searchInsetLeading/Trailing`（:124-127）token 已存在却未被引用。影响：token
  改值时该字段不跟（漂移风险，纯维护性）。建议：由 icon 宽 + gap 推导。
- [P2] `Main.qml:565-583` — 搜索框右端的"听写"图标是纯手绘装饰件，不可交互、
  无任何行为，视觉上却伪装成 macOS 原生的功能性听写按钮。影响：虚假可供性。
  建议：删除，或 `需人工判定` 是否按参考实现保留为装饰。

### 本轮已排除
- 线索 20（`CalendarMonthView.qml:97`）、线索 14/15（MonthView 字号与 opacity）：
  属 R5 区域，本轮未读该文件，不做判定。
- `Main.qml:1-1400` 内未发现 <10pt 字号（rowFontSize 15 / categoryFontSize 13 /
  dateNavTextSize 13 / GlassButton 16 / glyph 12px 为图形非文本）。
- `buildItemsByDate`（:246, 1160+）的全量重建是注释写明的意图（一次失效一次
  扫描，格子只查 key），不判为性能问题；年视图 504 次 `itemsForDate`（线索 19）
  留待 R3 按实际调用形态判定。

## R2 — `Main.qml:1400-2500`：工具栏、搜索、侧栏、迷你月（2026-10-18）

### Findings
- [P1] `Main.qml:1724-1751` — 自绘窗口圆点 delegate 是 14×14px `Rectangle` +
  裸 `MouseArea`：命中区 14×14 < HIG 最小 20×20；无 `Accessible.name`/role，
  `MouseArea` 不可键盘聚焦。影响：VoiceOver 与 Full Keyboard Access 均无法关闭/
  最小化窗口。建议：包一层 ≥20×20 的 `AbstractButton`，补 Accessible.name
  （"Close"/"Minimize"/"Zoom"），给 hover 提亮反馈。
- [P1] `Main.qml:1582-1586` + `:1570-1591` — 状态条由 `statusTimer` 3500ms 定时
  清空（HIG：尽量少用定时自动消失的界面元素），且 `showStatus` 无任何
  Accessible 播报（无 `Accessible.announcement`/live region）。影响："Event
  removed" 等破坏性操作的确认信息 3.5s 后无声消失，屏幕阅读器用户既听不到也
  看不到结果。建议：至少对状态文本挂 `Accessible.announcement`（或 role=Alert）；
  消失时长可配或 hover 时暂停。
- [P1] `Main.qml:1995-2013`（toolbarSearch 内 `TextInput`）— 搜索输入框无
  `Accessible.name`；占位符是独立 `Label`，VoiceOver 聚焦时读不出"Search"用途。
  影响：线索 18 成立。建议：`Accessible.name: qsTr("Search")`，或把占位符文本
  也设为 input 的 name。
- [P2] `Main.qml:1724-1751` — 圆点排列左→右为 green(max)/yellow(min)/red(close)，
  与 macOS 红黄绿惯例（close 在左）相反，close 落在最右。需人工判定：是否刻意
  按 Linux 摆位；作为 macOS 复刻与肌肉记忆冲突。建议：若保持右侧摆位，至少
  恢复 红/黄/绿 顺序。
- [P2] `Main.qml:2350` — 迷你月非本月日期整格 `opacity: 0.42`。实测合成
  （alpha 0.42 over 平面色）后数字对比度：浅色 `#000`→rgb(132) on `#E4E4E4` =
  **2.93:1**，深色 `#F2F2F2`→rgb(125) on `#282828` = 3.57:1；11px 文本 <4.5，
  浅色腿连 3:1 都不到。相邻月变暗是日历惯例，但建议浅色腿 alpha ≥0.5 或改用
  显式 `labelSecondary` 色而非透明度。
- [P2] `Main.qml:2374-2383` — 迷你月 todayRed `#E5484D` 圆盘上的 11px DemiBold
  白字对比 3.91:1，selectionDisc `#8E8E93` 白字 3.26:1，均 < 4.5（小号文本）。
  形状通道（实心圆盘）已传达状态，故降为打磨：加深盘色或提高字重/字号。
- [P2] `Main.qml:2127` vs `:2374` — "今天"色不一致（线索 4 的 R2 部分）：侧栏
  Today 行 marker 用 `tahoe.accent`，迷你月 today 圆盘用 `AppTheme.todayRed`，
  年视图/月视图还有第三套（R3/R5 复核）。同一语义三种颜色，违反"别用同一个
  颜色表达两件事"的对称律。建议：统一收敛到 todayRed。
- [P2] `Main.qml:1524-1538` — `headerTitle()` 周区间拼装 `"MMM d" + " – " +
  "d, yyyy"` 的**元素顺序与分隔符硬编码**（线索 17 成立，但比线索更细）：
  `AppTheme.formatDate` 本身走 `uiLocale`（AppTheme.qml:10-13），但 zh 等语序
  不同的 locale 会得到 "10月12 – 18, 2026" 这类非本地结构。建议：周区间整体
  走 locale 模板（如 `I18n.trPattern`），或至少对 zh 腿给出专案格式。
- [P2] `Main.qml:1668-1670` — 快捷键只有 Ctrl+1..3（线索 8 成立）；第 4 段
  Year（viewIndex=3，:1830 注释自认）无快捷键。建议：补 Ctrl+4，并在菜单/
  tooltip 中可见。
- [P2] `Main.qml:675-677, 802` + `:248` — GlassSurface hover/press/镜片提亮动画
  时长来自 `tahoe.pressDuration = 150`（硬编码常量），不在
  `AppTheme.motionFast/motionNormal`（AppTheme.qml:179-181，reduceMotion 时归 0）
  守卫链内。影响：Reduce Motion 开启时这三处仍做 150ms 动画（opacity 类，HIG
  允许淡入淡出，故降为 P2）。建议：`pressDuration` 也随 reduceMotion 归 0。
- [P2] `Main.qml:1424-1432` — `listColor()` 内 `Qt.darker(color, 1.0)` 是恒等
  变换（factor 1.0 = 原色），疑似残留的死操作；且 id 未命中时回落 `accent`，
  未知列表会与强调色同色。建议：删掉 darker 包装；回落色改为按 id 哈希的
  稳定色板。

### 本轮已排除
- 线索 13 的 1955/2104 两处（搜索框、侧栏宽度动画）：**不成立为违规** —
  时长走 `AppTheme.motionFast/motionNormal`，`AppTheme.qml:179-181` 在
  reduceMotion 时将两 token 归 0，动画被隐式禁用。守卫缺口只在上表
  `pressDuration` 一条。
- 迷你月单元命中区 21×21 ≥ 20 最小值，达标不写 finding；月标题/箭头 28×28 达标。
- `SidebarRow`/`CategoryRow` 内部（:280-340）本轮已看过 Accessible 结构，
  CategoryRow 可勾选态、nested 的 "Show completed" 有显式 Accessible.name，
  不重复 R1 的 finding。

## R3 — Main.qml:2500-2884（内容带、页面装配、年视图）

覆盖：状态条渲染端、KosPageCache 装配、月页议程卡（2552-2680）、
周/日页装配（2684-2746）、年视图（2748-2878）。

### Findings

- [P1] `Main.qml:2506` — 状态条文本色浅色模式不达标：positive `#34C759` 在
  contentPlane `#FFFFFF` 上 **2.22:1**，warning `#FF8D28` 上 **2.31:1**
  （13pt 文本需 4.5:1；python3 WCAG 计算）。深色平面 `#1E1E1E` 上 7.51:1 /
  7.22:1 达标——**仅浅色模式失败**。这是"保存成功/出错"反馈，越重要越不能看不清。
  建议：浅色腿用加深变体（systemGreen 浅色腿 Apple 用 #248A3D 档），或提供
  Increase Contrast 变体。
- [P1] `Main.qml:2864-2869` + `:2826` — 年视图日格是无障碍/键盘黑洞：
  纯 `MouseArea`（无 focus、无 `Accessible.name`/role、无键操作），
  `Layout.preferredHeight: 18` 低于 20×20 最小命中区。键盘用户在年视图只能
  整月跳转（2777-2781 的月格 ItemDelegate），**无法选中具体某天**；事件点
  （2840-2849）也不进无障碍树，VoiceOver 读不出"这天有几个事件"。
  建议：日格改 ItemDelegate 或给 MouseArea 配 `Accessible.name`（日期+事件数）、
  支持键盘聚焦，格高 ≥20。
- [P1] `Main.qml:2673`、`:2859` — 9pt 字号低于 macOS 最小 10pt（线索 14 成立）。
  2859 是年视图日期数字（9pt，白/黑 DemiBold），2673 是议程行 TASK/EVENT 标签。
  建议：统一 ≥10pt；年视图日格改 10 后需同步核 18px 格高是否容纳。
- [P2] `Main.qml:2646` — 议程行时间恒为 24 小时（线索 16 成立）：
  `itemTime()`（1353-1358）用正则直接取存储 ISO 的 `HH:MM`，不走 Locale；
  而 chip（12h `formatClock12`）同一屏另一侧是 12 小时——两套格式并存。
  建议：itemTime 走 Locale.ShortFormat；注意与下一条联动。
- [P2] `Main.qml:2645` — 时间列固定 `preferredWidth: 58`。若 itemTime 按
  上一条改 locale 化，"10:30 AM"（11pt）约需 55-62px，临界截断。
  建议：改格式时同步改该宽度或改 `implicitWidth` 自适应。
- [P2] `Main.qml:2821-2824` — 年视图 12×42=504 个 `itemsForDate` 绑定
  （线索 19 成立但**降级**）：实测 `itemsForDate`（1281-1283）是字典查找
  而非全量扫描，单次调用廉价；真实成本是 `itemsByDate` 任何变更触发 ~504 个
  绑定重算，每次重建 2 个 `Date` + `dateKey` 字符串拼接。当前量级可接受，
  但月视图新增条目时年视图白算。建议：eventCount 按月聚合一次（每格查月级
  预汇总），或至少缓存 dateKey。
- [P2] `Main.qml:2599-2604` — 议程行完成勾选钮 24×24，低于 macOS 默认命中区
  28×28（≥20 达最低线不违规）。有 `Accessible.name`（2607-2608，随 checked
  切换文案，好）。建议放大到 28 或留注释说明取舍。
- [P2] `Main.qml:2672` — kind 标签（TASK/EVENT，2668-2671）颜色取
  `itemColor`（数据驱动的分类色）：非交互文本用分类色，对比度不受控
  （色值来自 PIM 数据，无法静态测量）。**需人工判定**：抽样真实分类色的
  浅/深两腿对比度。同色也用于左条纹 2642 与勾选圆 2617，语义一致（都表示
  分类），不算"一色两义"。
- [P2] `Main.qml:2515-2517` — 注释 "Retaining all three would only defer"
  与现实不符：pages 有 **4** 个（2518）。过期注释易误导后续维护。
  建议顺手改掉。
- [P2] `Main.qml:2501` — `pim.errorMessage` 仅在 `pim.ready` 时才显示
  （`&& pim.ready`）。连接失败期的错误被静默吞掉。需人工判定：是否为
  有意设计（连接期错误确实无意义）还是遗漏。
- （并入 R2）`Main.qml:2503-2508` — R2 发现的状态条 3.5s 自动消失 + 无播报，
  本轮确认渲染端 Label 也无 `Accessible.name`/announcement 属性，两条合并为
  一项修复。

### 本轮已排除
- 周页/日页 viewport 同步（2705-2712、2737-2744）：`onVisibleChanged` 与
  `Component.onCompleted` 双守卫 + 同一性检查（`root.scheduleViewport === ...`）
  正确处理了页缓存销毁/重建与切换竞态，不写 finding。
- 白字 on todayRed 圆盘（2856-2857）**3.91:1**：DemiBold 适用 3:1 粗体阈值，
  达标；不单独成 finding（字号问题已由 2673/2859 的 9pt finding 覆盖）。
- 白字 on selectionDisc `#8E8E93`（2856）**3.26:1**：同样过粗体阈值，
  仅在 9pt 修复后复核常规字重场景。
- 议程行（2590，KosItemDelegate）是标准 ItemDelegate：可键盘聚焦、有
  activeFocus 描边（KosItemDelegate.qml:11-12），不写 finding。
- 线索 20（CalendarMonthView.qml:97 魔数）不在本行段 → 留给 R5。

## R4 — `CalendarScheduleView.qml` 全文（周/日网格、chip、全天条、gutter）

复核日期 2026-10-18。全文 1088 行通读完毕。线索 1/2/3/14 逐条核实如下，
另含新发现。对比度均用 WCAG 相对亮度公式实测（python3，算式见各项）。

### 线索复核

- [P1] `CalendarScheduleView.qml:856-857,880-881` — 线索 1 成立。chipHost
  `anchors.margins: 3` → 内高 `40-6=34`；timedChip 高
  `Math.round(40*0.96)=38` → chip 在宿主内 y=3..41，**超出宿主 4px、
  超出 40px 小时格 1px**，侵入下一小时行。下一行 delegate 在 Repeater 中
  靠后、z 序更高：周末列的 weekendField 色块（713-718）与下一行顶部
  1px gridLine（808-814）会盖在 chip 最后 1px 上。同时宣告的 3px 底部
  inset 实际不成立。建议：chip 高改 `hourHeight-2*3-2`（=32）或 margins
  改 1，二者取一并保持与 ref 0.96 占比论证一致。
- [P2] `CalendarScheduleView.qml:982` — 线索 1 尾成立：`timedChip.height
  >= 34` 中 height 恒为 38，条件恒真，是死守卫。若意图是"矮 chip 隐藏
  副行"，该意图从未生效。建议：删掉或改为 `>= hourHeight-8` 之类的
  真实阈值。
- [P1] `CalendarScheduleView.qml:173-175` vs `:757-771` — 线索 2 成立。
  nowPill 文案 `nowLabel` 恒 24 小时零填充（"09:05"），同一屏幕 gutter
  刻度是 12 小时 + AM/PM（"9 AM"）。同视图两套时间格式。建议：二者
  统一走同一 helper（并见线索 3 的 locale 问题）。
- [P1] `CalendarScheduleView.qml:757` — 线索 3 成立且比原线索更重：
  `text: hourCell.rowIndex < 12 ? "AM" : "PM"` 硬编码英文；`:766-769`
  数字部分 `(h === 0 ? 12 : h)` 把 12 小时制写死——**24 小时制 locale
  （如 zh-CN）的 gutter 也只会显示 12 AM/PM**。与 `Main.qml:1315
  formatClock12` 同病。建议：按 `Qt.locale().timeFormat` 长度判定 12/24h，
  24h locale 直接显示 `rowIndex` 且去 meridiem。
- [P1] `CalendarScheduleView.qml:457,620,647,1042` — 线索 14 本文件部分
  成立：四处 `font.pixelSize: 9`（"all-day" 标签、全天 chip 标题、两个
  "+N"），低于 macOS 最小 10pt。**新发现同族：`:759` meridiem 文字
  `font.pixelSize: 8`，更小**。9px 在 24px 全天行内尚可排版，但 8px
  AM/PM 与 11px 数字同屏阅读吃力。建议：全部提到 ≥10，meridiem ≥9
  且考虑 24h locale 下直接消失（见上条）。

### 新发现

- [P0] `CalendarScheduleView.qml:525-528,550` — 全天条 "+N" 溢出判据
  差一：`allDayOverflow = max(0, columnItems.length - allDayMaxRows + 1)`
  在 `length == allDayMaxRows == 3` 时 = 1，于是该列**只渲染
  `slice(0, bandRows-1)` = 2 个 chip + 一行 "+1"**——而 band 此刻有
  3 个槽、3 个 item 全放得下，"+1" 是不存在的隐藏数的假计数，第 3 个
  事件被无端藏起。算式：3−3+1=1>0 ⇒ allDayVisible=3−1=2。当内容行数
  ≤3（band 未触顶）时必然误报。建议：`allDayOverflow = max(0,
  columnItems.length - allDayBandRows)`，仅当真的放不下时才让 "+N"
  占用最后一槽。
- [P1] `CalendarScheduleView.qml:792-797` — nowPill 文案白字
  `#FFFFFF` on `todayRed #E5484D` = **3.91:1**（实测），而该 Label
  `font.pixelSize: 11` 且**未设字重（常规体）**——适用 4.5:1 阈值，
  不达标。R3 的"白 on todayRed 已排除"只覆盖日头部 12px **DemiBold**
  数字（粗体 3:1 过线），不适用此处。建议：pill 文字加
  `Font.DemiBold`（一并更贴 ref 的加粗胶囊字），或加深 todayRed 在
  pill 这一处的底色。
- [P1] `CalendarScheduleView.qml:414,625,838,1024` — 键盘与 VoiceOver
  双阻断：日头部 cell 用裸 `TapHandler`、全天 chip（551 起）与 timed
  chip（867 起）用裸 `TapHandler`、小时格用裸 `MouseArea`（840 单击
  选中、841-844 双击建事件）。四者均不可聚焦、无
  `Accessible.name`/`Accessible.role`。影响：Full Keyboard Access 下
  无法选中任何日期/时段/事件，也无法发起"双击空白建事件"；VoiceOver
  读不出任何 chip。建议：chip 换 `Accessible.role: ListItem` +
  name = 标题+时间，网格 cell 给 `TapHandler` 之外补键盘路径（如
  空格/回车激活、方向键移动选中格）。
- [P2] `CalendarScheduleView.qml:278-286,682-692` — 网格 24×
  (dayCount+1) 格，每格 `cellItems` 绑定调一次 `hourItems`（内部再调
  `itemsForDate` 拷贝全日数组过滤）。周视图 = 192 次/轮，且
  itemsByDate 任一变更触发整片重算。日历数据量小、可接受，但建议把
  per-date/per-hour 过滤结果在 C++ 侧或 root 缓存一次（与 R3 年视图
  504 次同类，合并处理）。
- [P2] `CalendarScheduleView.qml:580-581,599-608` — 多日全天条左延
  `allDayJointOverlap=4` 是不透明覆盖：若相邻两列同一行有**两个不同**
  的多日 item，右侧 chip 的左延会盖掉左 chip 右端 4px（含可能的省略
  号）。单日与多日混排时可复现。需人工判定：实机看两个重叠多日事件
  的并排显示是否可接受；不可接受则把左延改为只画到本列左缘
  （`clip` 或减窄）。
- 需人工判定：`CalendarScheduleView.qml:745-751` hourLabel 避让
  nowPill 的 `nowLabelClearance: 14` —— 数值上 pill 半高 10 + 数字墨
  半高 ~4.5 ≈ 14.5，14 略紧但量级正确；是否真有 1px 碰撞需实机确认。

### 已排除（本轮实测，免下轮重疑）

- chip 墨色对比度全部达标：timedChip 墨（色相对半取极，`:270-276`）
  on 填充（浅 `alpha 0.19` / 深 `alpha 0.36`）——accent：7.80 / 5.37，
  红 (235,76,70)：7.98 / 5.35；全天 chip（mix 0.17/0.32）：8.0 / 5.36
  与 8.19 / 5.33。两腿、两种代表色均 > 4.5:1。R089/R079 的半值墨规
  在对比度上站得住。
- "+N" 墨 on 场地：浅 9.83–10.17、深 8.59–8.90，达标。
- `allDayContentRows`/`allDayBandRows` 的槽位记账（除上述 P0 差一外）
  自洽：cap 3、min 1、overflow 行占 1 槽，总数恒等于 bandRows。
- `lastCoveredDay` 的"end 独占 −1 天"用本地日期分量回滚，跨月/跨年
  正确；`isoDay` 字符串比较格式固定 4-2-2，字典序安全。
- `usefulStartHour`（288-310）：含今日时 `max(0, now-2)`，边界 6..21
  之外回落最早事件−2 或 7，逻辑无死区。
- nowLine/nowDot 只在 `rowIndex === nowRow` 渲染，`columnIndex-1 ===
  todayColumn` 判定与 gutter 不画的声明（1051 注释）一致，无越界。

## R5 — `CalendarMonthView.qml` + `EventDetailsPopover.qml`（2026-10-18）

### 线索复核（TASK.md 4/5/6/14/15/20）
- 线索 4 成立 — `CalendarMonthView.qml:117` 月格 today 圆片用 `AppTheme.accent`；
  `Main.qml:2374` 迷你月、`:2834` 年视图用 `AppTheme.todayRed`；`:2127` 侧栏 Today 又用 accent。
  同一语义（"今天"）在四个位置分裂成两种色。且 `AppTheme.qml` M04 注释自述
  "the mini month's today disc all read this (todayRed)" —— 月视图的实现与 token 自身的文档矛盾。
  建议：月格 today 圆片改用 `AppTheme.todayRed`。
- 线索 5 成立 — `CalendarMonthView.qml:141` `visible: dayButton.hovered && inVisibleMonth`。
  纯悬停入口：hovered 不会被键盘聚焦置位，Tab 进入日格后"+"按钮不可见也不可激活。
  建议：补 `dayButton.activeFocus` 条件，或改为 focus/hover 双触发。
- 线索 6 成立 — `CalendarMonthView.qml:188` chip 仅裸 `TapHandler`：不可聚焦、无
  Accessible.role/name；且 chip 高 18px（:161）低于 macOS 20×20 最小命中区。事件条
  是月视图除日格与"+"外唯一的条目入口，键盘与 VoiceOver 双阻断。
- 线索 14 成立 — `CalendarMonthView.qml:133`（"+N"）与 `:182`（chip 标题）均
  `font.pixelSize: 9`，低于 macOS 10pt 最小值。chip 标题是正文信息不是 caption。
- 线索 15 成立 — `CalendarMonthView.qml:102` `opacity: 0.42` 作用于整格。
  alpha 合成实测：浅色 (23,32,51)@0.42 over card(251,253,255) → (155,160,169)，
  CR=2.57:1；深色 (244,247,251)@0.42 over card(33,42,58) → (121,128,139)，CR=3.63:1。
  11px 文本两模式均 < 4.5:1。副效应：out-month 格里的 chip 底 alpha 0.16×0.42≈0.067，
  事件条几乎不可见。
- 线索 20 成立 — `CalendarMonthView.qml:97` `Math.floor((height-5-5-26)/20)` 的
  26/20 是魔数：26=日期圆片 24+spacing 2，20=chip 18+spacing 2，与 :61-66 的 30、
  :161 的 18 隐式耦合，改任一处会静默错位。建议提为具名常量或由布局推导。

### 新发现
- [P1] `CalendarMonthView.qml:122` — today 圆片文字硬编码 `"white"` 于 accent 底上。
  实测 WCAG：白 on 蓝 #3478f6 = 4.07:1、on 紫 #8b5cf6 = 4.23:1、on 橙 #d66a20 = 3.53:1
  （accent 可被用户切换，11px DemiBold 需 4.5:1，全部不达标；on 绿 #16875f = 4.50 临界）。
  黑字 on 蓝 = 5.16:1。影响：四种 accent 三种不达标。建议：改用现成的
  `AppTheme.accentText`（AppTheme.qml:157 已按对比度自动选黑/白）。
- [P2] `CalendarMonthView.qml:134` — "+N" 的 Accessible.name 写在非交互 Label 上
  （"select this date to view all"），交互载体是外层 dayButton。VoiceOver 用户聚焦
  日格时听不到溢出信息。建议：把条目数并入 dayButton 的 Accessible.name。
- [P2] `CalendarMonthView.qml:51` — `height - 30 - 6*rowSpacing` 的 30 与 :64-66
  表头固定高重复硬编码，同线索 20 一类魔数。建议：引用表头常量。
- [P2] `EventDetailsPopover.qml:127-128,207` — closeButton 22×22、editButton 高 26：
  ≥20 最小值合法但低于 macOS 28×28 默认命中区，且两者是弹窗内仅有的操作目标。
- [P2] `EventDetailsPopover.qml:20-25` — 中性灰硬编码（#262626/#F5F5F5/
  rgba(0,0,0,0.55) 等）绕过 AppTheme 语义色，不随 accent/系统调色板适配，也没有
  Increase Contrast 变体；与 HIG"语义色三套都要成立"存在张力（注释声明是刻意选择）。
- 需人工判定：`EventDetailsPopover.qml:262-282` `openAt(point)` 把弹窗左上角直接放在
  点击点并 clamp 进窗口，无箭头、无"附着并指向源"的锚定形态（与线索 10 同源）。
  当前注释表明是刻意的 app-owned 设计，是否需补 macOS 原生 popover 形态留人工判断。
- 需人工判定：`CalendarMonthView.qml:188` chip TapHandler 默认 DragThreshold 被动
  抓取，点击 chip 是否会同时触发外层 dayButton.onClicked（dateSelected 双发）？
  需运行时确认。
- 已排除：popover 次要文本对比度达标 — secondaryColor 实测浅色 (110,110,110) on
  #F5F5F5 = 4.66:1、深色 (164,164,164) on #262626 = 6.06:1，12px 需 4.5:1，两模式通过。
- 已排除：chip 墨色达标 — `AppTheme.text` on 半透明 accent 底实测浅色 13.11:1、
  深色 9.35:1（与 R4 对 ScheduleView chip 的结论一致，跨视图可复用）。
- 已排除：`EventDetailsPopover.qml` 标题 15px/20px 行高、时间/位置/备注 12px 均在
  HIG 内置档位（Title3 15、Callout 12）内，无字号违规。

## R6 — `EventEditorDialog.qml`（590 行）+ `CalendarTaskEditorDialog.qml`（411 行）

线索复核：

- [P1] `EventEditorDialog.qml:240-250`、`CalendarTaskEditorDialog.qml:98-108` —
  线索 11 **成立**。Delete 按钮 onClicked 直接 emit `deleteRequested`，调用方
  `Main.qml:1649/1657` 直接 `pim.removeEvent(uid)` / `pim.removeTodo(uid)`，随后
  `root.close()`。全链路无确认弹层、无撤销（仅 `Main.qml:1572-1573` 一条
  "Event removed" 状态文本，3.5s 自动消失且无无障碍播报，见 R2）。删除不可恢复
  却零摩擦、零告知后果。建议：删除改为二次确认（macOS 惯例为附着的 alert，
  说明不可恢复 + Cancel 为默认按钮），或提供有限时间的 Undo 通道。
- [P2] `EventEditorDialog.qml:191-201/208-214`、`CalendarTaskEditorDialog.qml:43-53/66-72`
  — 线索 12 **成立，判为脆弱但当前可用**。隐藏 `DialogButtonBox` 当"文案源"，
  在 `Component.onCompleted` 里拷贝 `standardButton(Dialog.Save).text`。风险点：
  ① 文案是**一次性拷贝的普通字符串**，运行时切换系统语言/locale 不会更新；
  ② 依赖 footer 在 onCompleted 前已完成实例化——若创建顺序变化（footer 懒加载
  等），`save`/`cancel` 为 null，静默回落到硬编码英文 `qsTr("Save")/qsTr("Cancel")`；
  ③ 同一弹框两套 i18n 来源：其余全部走 qsTr，这两个按钮走 Qt 平台主题串，
  翻译可能互相不一致。注释自己也承认是非标接线。建议：直接用 qsTr + 平台
  主题对齐（或 QPlatformTheme::standardButtonText 语义封装成绑定而非拷贝），
  至少把回落文案与拷贝时机写进契约。

新问题：

- [P1] `CalendarTaskEditorDialog.qml:18` — 标题硬编码 `qsTr("Edit task")`，无
  New/Edit 区分（对照 event 编辑器 `EventEditorDialog.qml:24` 有 `editing ?`
  三元）。而 `Main.qml:2066` `taskEditor.openForTodo(null)` 是**新建任务**入口，
  新建时弹窗标题仍显示 "Edit task"，文案错误肉眼可见。建议：加
  `editingId.length > 0` 分支，新建显示 "New task"。
- [P1] `EventEditorDialog.qml:149-171`、`CalendarTaskEditorDialog.qml:157-172` —
  保存前零校验：日期/时间是自由文本（`startDateField.text.trim()` 等直接拼进
  ISO 串），输入 "abc" 或 "25:99" 会原样存成 `"2026-10-18T25:99:00"` 损坏记录；
  空 Title 静默保存；end 可早于 start（`endDateField` < `startDateField`、
  `endTimeField` <= `startTimeField` 均无检查，allDay 切换只处理 end==start 的
  情形，`EventEditorDialog.qml:332-338`）。HIG：可能丢输入/产生坏数据时必须
  阻止并说清后果。建议：onAccepted 前解析校验（Date parse + 区间比较），非法
  字段描边 + 行内错误文案，阻止 accept。
- [P1] `EventEditorDialog.qml:433-444` — "取消关联任务"警告标签 `AppTheme.warning`
  浅色模式实测 **3.89:1**（#b96800 on 弹窗面 #F7F7F7，11px 非粗体需 4.5:1），
  不达标；深色 #ffb340 on #262626 = 8.48:1 通过。浅色模式要么提亮前景
  （如 #a05c00 不够，需 ≤ #8f5300 一档），要么加深底色/加粗（粗体 3:1 档
  可过）。建议：浅色 token 换深一档或对该标签用 `font.weight: Font.DemiBold`。
- [P1] `CalendarTaskEditorDialog.qml:271-284`、`374-382` — VoiceOver 名称缺失：
  `listBox`、`priorityBox` 两个下拉与 `notesField` 备注区均无 `Accessible.name`，
  旁边的 "List"/"Priority"/"Notes" 是普通 Label，未与控件关联；而 event 编辑器
  的同类控件全部有名（`EventEditorDialog.qml:452-459/461-468/559`）。同一 app
  两编辑器无障碍水平不一致。建议：补 `Accessible.name`（Task list / Task
  priority / Task notes）。
- [P1] `EventEditorDialog.qml:203-252`、`CalendarTaskEditorDialog.qml:61-110` —
  自定义 footer 后无默认按钮：`defaultButton` 未设置，且 Dialog 自带
  buttonBox（会把 Save 标准钮标记为 default 并接 Return）被 footer 覆盖后
  永不创建；`shared/qml/foundation/KosDialog.qml`/`KosWorkspaceDialog.qml`
  全文无 Keys/Enter 处理。聚焦在 Title 输入框按 Return 无动作，键盘用户必须
  Tab 到 Save。需人工判定：实机确认 Return 行为（理论推断 QQC2 Dialog 不
  自行处理 Return）。建议：Save 按钮设 `default: true` 并在弹框层接
  `Keys.onReturnPressed`。
- [P2] `EventEditorDialog.qml:359/366/387/394`、`CalendarTaskEditorDialog.qml:296/304` —
  日期/时间 placeholder 硬编码 ISO `"YYYY-MM-DD"`/`"HH:MM"` 且未 qsTr：格式
  本身 locale 无关尚可，但配合零校验（上条），DD/MM 地区用户没有任何关于
  输入顺序的提示或纠错。建议：至少在占位符层走 locale（`Qt.locale().dateFormat`
  / `timeFormat`），并在校验失败时给出格式说明。
- [P2] `EventEditorDialog.qml:269-280`、`CalendarTaskEditorDialog.qml:201-213` —
  表单滚动条 thumb `blackSeed` α=0.30/0.40 合成后对比度实测：浅色 #ADADAD on
  #F7F7F7 = **2.09:1**、深色 #171717 on #262626 = **1.18:1**，低于非文本 UI
  组件 3:1 一档（macOS overlay 滚动条本身偏含蓄，判打磨项而非违规）。
  建议：dark 模式至少 α 0.55+（合成 ≈ #1f1f1f 仍不够，需向中性灰走，
  如 #8a8a8a 系）。

已排除 / 需人工判定：

- 已排除：两编辑器正文标签 11px/10px 字号 — HIG 最小 10pt，`font.pixelSize: 10`
  （`CalendarTaskEditorDialog.qml:321`）与 11px（多处）均达标；10px 处于下限，
  仅在 `mutedText` 对比度不足时会放大影响。
- 需人工判定：`AppTheme.mutedText` 标签 on 弹窗自绘面（#F7F7F7/#262626）——
  token 是动态混色（`AppTheme.qml:154`，依赖 paletteText/window），R5 在近似
  中性面实测 4.66/6.06 通过，但弹窗面亮度略有差异，建议随 Increase Contrast
  一并实机复测。
- 已排除：Save 必配 Cancel — `standardButtons: Dialog.Save | Dialog.Cancel`
  且 footer 显式提供 Cancel 按钮与 Esc reject 通道，符合 HIG 弹框规则。
- 备注（R7 横切）：隐藏 DialogButtonBox 偷文案的模式在
  `apps/todo/qml/TodoEditorDialog.qml` 同样存在，跨 app 修复时一并处理。

## R7 — 横切汇总（2026-10-18）

### 横切 grep 实测

- **裸 TapHandler/MouseArea 全量清单**（合并为全局 finding A1）：
  `CalendarScheduleView.qml:414,625,838,1024`（日头 cell、全天 chip、小时格、timed chip）、
  `CalendarMonthView.qml:188`（chip）、`Main.qml:1728`（窗口圆点，R2 F 已单列）、
  `Main.qml:2864`（年视图日格，R3 已单列）。共 8 处，全部不可键盘聚焦、无 role/name。
- **Accessible 覆盖率**：`CalendarScheduleView.qml` 全文 1088 行 **0 处 Accessible 属性**
  ——整个周/日网格视图对 VoiceOver 是空树，是覆盖率最差的文件。其余文件均有
  部分覆盖（Main 12 处 name、EventEditor 11、MonthView/TaskEditor/Popover 各 2-3），
  缺口已逐条列于各轮（A2/A3/A4）。
- **动效守卫（判据 = 是否走 motionFast/motionNormal，R2 修正）**：全 app 动画点
  grep 完毕，唯一不经过守卫链的是 `Main.qml:248` 的 `pressDuration: 150`
  （消费点 :675-677、:802-803）；`Main.qml:1955`、`:2104` 的宽度动画走
  `AppTheme.motionFast/motionNormal`（reduceMotion 时归 0），**已排除**。
- **字号 <10pt 全量清单**（合并为一条）：`CalendarMonthView.qml:133,182`、
  `CalendarScheduleView.qml:457,620,647,759(8px),1042`、`Main.qml:2673,2859`
  —— 共 9 处 8-9px。
- **时间格式分裂全量清单**：12h 硬编码腿 = `Main.qml:1309-1336 formatClock12`
  （含 `:1336` "AM"/"PM" 判断）、`CalendarScheduleView.qml:757-769` gutter；
  24h 腿 = `Main.qml:1353 itemTime`（消费点 :2646、:1393-1398 详情串）、
  `CalendarScheduleView.qml:173 nowLabel`。同一 app 三个视图两套制式、
  两处硬编码英文 meridiem。
- **"今天"色分裂全量清单**：`CalendarMonthView.qml:117`（accent）、
  `Main.qml:2127`（accent）、`Main.qml:2374`（todayRed）、`Main.qml:2834`
  （todayRed）、`CalendarScheduleView.qml:398/790/1059`（todayRed，一致）。
  4 个月历形态里月视图是唯一偏离 token 自述（todayRed）的实现。
- **硬编码 "white" on accent/todayRed**：`CalendarMonthView.qml:122`（on accent，
  R5 已判）、`CalendarScheduleView.qml:405,795`、`Main.qml:2384,2857`（on todayRed，
  R3 已按 DemiBold 3:1 阈值排除）。前者待修（accentText），后者达标不动。

### 本轮新发现

- [P2] `CalendarScheduleView.qml:135,143` — 中性腿 `#1E1E1E`/`#FFFFFF` 直接硬编码，
  绕过 AppTheme 语义 token；与 R5 的 `EventDetailsPopover.qml:20-25` 同病，
  合并为一项修复（浅/深腿色值散落多文件，改主题时必漏）。
- 已排除：R6 备注"同模式在 `apps/todo/qml/TodoEditorDialog.qml`"**不成立**——
  该文件只有 `standardButtons: Dialog.Save | Dialog.Cancel`（:26）、无自定义
  footer、无隐藏 DialogButtonBox，且标题有 `editing ?` 区分（:20，恰是日历任务
  编辑器缺的东西）。跨 app 修复清单删除该条。
- 已排除：`EventEditorDialog.qml:282,571`、`CalendarTaskEditorDialog.qml:218,393`
  四处 MouseArea 均 `acceptedButtons: Qt.NoButton`（纯滚轮转发），不构成
  交互阻断，不并入 A1。

### 三组合并清单（R1-R6 去重）

**组 1：无障碍 / 键盘（VoiceOver + Full Keyboard Access）**
- A1 [P1] 裸 handler 全局清单（8 处，见上）——事件/日期/时段全不可键盘触达，
  ScheduleView 整文件无 Accessible。修法：chip 换 Accessible.role+name，网格补键盘路径。
- A2 [P1] `Accessible.checked` 全仓 0 处（`Main.qml:421-423` CheckBox 无 checked、
  `:281-407` 开关行无 role/checked）。
- A3 [P1] 搜索输入框无 Accessible.name（`Main.qml:527-560`、`:1995-2013` 两处同病）。
- A4 [P1] 任务编辑器 listBox/priorityBox/notesField 无 Accessible.name
  （`CalendarTaskEditorDialog.qml:271-284,374-382`）。
- A5 [P1] 状态条 3.5s 定时消失 + 无播报（`Main.qml:1582-1586`）。
- A6 [P1] 删除零确认零撤销（`EventEditorDialog.qml:240-250`、
  `CalendarTaskEditorDialog.qml:98-108` → `Main.qml:1639-1658`）。
- A7 [P1→需实机确认] 编辑器无默认按钮，Return 无法提交
  （`EventEditorDialog.qml:203-252`、`CalendarTaskEditorDialog.qml:61-110`）。
- A8 [P1] 月视图 "+" 纯 hover 暴露（`CalendarMonthView.qml:141`）。
- A9 [P1] 年视图日格 18px + 9pt + 无障碍黑洞（`Main.qml:2864,2859`）。

**组 2：i18n / locale / 数据正确性**
- I1 [P1] formatClock12 + gutter 硬编码 12h/AM/PM，24h locale 全错
  （`Main.qml:1309-1336`、`CalendarScheduleView.qml:757-769`）。
- I2 [P1] 两套时间制式并存（itemTime 24h vs chip 12h，`Main.qml:1353,2646`、
  `CalendarScheduleView.qml:173`）——修 I1 时一并统一。
- I3 [P1] 任务编辑器新建也显示 "Edit task"（`CalendarTaskEditorDialog.qml:18`）。
- I4 [P1] 保存零校验（自由文本直拼 ISO、空标题、end<start 放行；
  `EventEditorDialog.qml:149-171`、`CalendarTaskEditorDialog.qml:157-172`）。
- I5 [P2] headerTitle 拼死英文语序（`Main.qml:1524-1538`）。
- I6 [P2] 隐藏 DialogButtonBox 偷文案（i18n 一次性拷贝 + 实例化顺序脆弱；
  `EventEditorDialog.qml:191-214`、`CalendarTaskEditorDialog.qml:43-72`）。
- I7 [P2] 日期/时间占位符 ISO 硬编码不 qsTr（`EventEditorDialog.qml:359-394`、
  `CalendarTaskEditorDialog.qml:296,304`）。

**组 3：对比度 / 色 token / 动效 / 性能**
- C1 [P1] `labelSecondary` 浅色腿 2.91-3.44:1（`Main.qml:120-123`）。
- C2 [P1] 状态条 positive/warning 浅色 2.22/2.31:1（`Main.qml:2506`）。
- C3 [P1] nowPill 白 on todayRed 3.91:1 常规体（`CalendarScheduleView.qml:792-797`）。
- C4 [P1] 月视图 today "white" on accent 3.53-4.23:1（`CalendarMonthView.qml:122`，
  建议 accentText）。
- C5 [P1] 取消关联警告浅色 3.89:1（`EventEditorDialog.qml:433-444`）。
- C6 [P2] 非本月 opacity 0.42 → 2.57/3.63:1（`CalendarMonthView.qml:102`、
  `Main.qml:2350`）。
- C7 [P2] 硬编码中性灰绕过 AppTheme（`CalendarScheduleView.qml:135,143`、
  `EventDetailsPopover.qml:20-25`）。
- C8 [P2] "今天"色分裂 accent/todayRed（`CalendarMonthView.qml:117` vs
  `Main.qml:2374,2834`）。
- M1 [P2] `pressDuration:150` 不走 reduceMotion（`Main.qml:248,675-677,802-803`）。
- S1 [P2] 9 处 8-9px 字号（清单见上）。
- F1 [P2] 年视图 504 次 `itemsForDate` / 周 192 次 `hourItems` 绑定重算
  （`Main.qml:2821-2824`、`CalendarScheduleView.qml:278-286,682-692`）——
  R3/R4 均判当前量级可接受，降级保留。

## 建议修复顺序

**P0（正确性，先于一切）**
1. `CalendarScheduleView.qml:525-528,550` — 全天条 "+N" 差一：3/3 满列时隐藏
   真实第 3 个事件并显示假 "+1"。一行公式修复。

**P1（同一优先级内按影响面排序：影响全部用户 > 影响无障碍/键盘用户 > 影响浅色模式）**
1. I1+I2 — 时间格式统一走 locale（12/24 偏好 + locale meridiem）。影响
   所有 24h 制 locale 用户的正确性，且是 C3 之外唯一"肉眼即错"的文案问题。
2. I3 — 任务编辑器 New/Edit 标题（一行修复，新建弹窗标题肉眼错误）。
3. I4 — 编辑器保存校验（防坏数据落库，与 I7 占位符 locale 化联动）。
4. A6 — 删除加确认或 Undo（破坏性操作，HIG 弹框规则）。
5. A1 — 裸 handler 无障碍/键盘改造（8 处、覆盖全部四个视图的交互主体，
   是工作量最大的一条，建议按视图分批：ScheduleView 四处 → MonthView →
   年视图 A9 合并处理）。
6. A9 — 年视图日格（与 A1 同批，命中区+字号+Accessible 一起修）。
7. A2 — Accessible.checked（两处，几行修复）。
8. A3+A4 — Accessible.name 补齐（搜索框两处 + 任务编辑器三控件）。
9. A8 — "+" 按钮 hover→focus/hover 双触发（一行）。
10. C1 — labelSecondary 浅色 alpha 0.60→~0.78（一处 token，点亮全部浅色
    secondary 文本）。
11. C2 — 状态条 positive/warning 浅色加深一档。
12. C3 — nowPill 文字加 DemiBold（顺带贴 ref 的加粗胶囊）。
13. C4 — MonthView today 文字改 accentText。
14. C5 — 取消关联警告浅色加深或加粗。
15. A7 — 编辑器默认按钮/Return 提交（实机确认后修）。

**P2（打磨，可攒一批做）**
1. S1 — 9 处字号提到 ≥10（与 A9 的 18px 格高联动）。
2. C6 — 非本月 opacity 0.42 提到 ≥0.5 或改 labelSecondary。
3. C8 — "今天"色统一到 todayRed（月视图一处改动）。
4. C7 — 硬编码中性灰收敛进 AppTheme。
5. I5 — headerTitle 周区间 locale 模板。
6. I6 — DialogButtonBox 偷文案改绑定（防 locale 热切换/实例化顺序回归）。
7. I7 — 占位符 locale 化（随 I4 一并）。
8. M1 — pressDuration 纳入 motion token 守卫链。
9. 其余单点：Ctrl+4 快捷键、`--view year`、窗口圆点顺序（需人工判定）、
   迷你月 todayDisc 白字、议程勾选钮 28px、魔数提常量（MonthView:97,51、
   ScheduleView:982 死守卫、`Main.qml:2515` 过期注释、`listColor` 恒等
   darker）、F1 绑定重算缓存。
