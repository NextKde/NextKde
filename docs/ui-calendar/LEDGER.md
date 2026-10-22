# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ03 ✓ Day/Week/Month/Year 分段改 materialForm 平铺形态：胶囊 228×28 居中主区（center 550），
  4 段各 57，pill 52×24 内缩 2；track α .025 over 白（实测 252）、pill `#E7E7E7`（实测 231）、
  4 个标签统一 `labelPrimary`（选中仅 pill + DemiBold 标记），与参考一致。
- 关键修正：原控件默认 `materialForm:false` 会在工具栏 L1 玻璃上再画一层 `LiquidSurface`（叠玻璃且
  选中 pill 被镜片洗成白色）。现 `materialForm:true`，不再有第二层玻璃/LiquidSurface。
- 新增 `LiquidSegmentedControl.borderColor`（默认 `AppTheme.border`，其它调用点不变）；日历传
  light α .05 / dark 白 α .10。原因：默认 α .14 描边在白底上是一圈清晰灰环，参考顶边实测 249..253
  （无线），只有圆头两端因 AA 到 ~222。
- 实拍：`LQ03-1100-light.png`、`LQ03-toolbar-zoom.png`、`LQ03-compare.png`、`LQ03-1100-light-v2.png`、
  `LQ03-compare-v2.png`；dark `LQ03-1100-dark.png`、`LQ03-dark-zoom.png`（tmp，不入库）。
- 量测（v2）：pill 231 / track 252 / 描边 244..247；dark pill (60,60,60)、track (42,42,43)。
  交互走控件既有 `selectionRequested`（映射不变），app + pim 日志 **0 error / 0 warning**。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：在新组件树上启动 light week，截 1100×720 与 760×540；记录 runtime log 的 error/warning，确认无启动回归。
- [x] LQ02 工具栏：`Main.qml` 顶部工具栏换 `LiquidSurface`(regular) + `LiquidOuterShadow`；保留 L02–L04 的 40 高、按钮 28–30、分段居中几何；持续玻璃 1/2。
- [x] LQ03 分段控件：Day/Week/Month/Year 换 `LiquidSegmentedControl`，高 28、胶囊、pill 当前视图；宽度随 4 段重算并保持主区域居中。
- [x] LQ04 工具栏按钮：prev/Today/next、侧栏开关、搜索、添加、更多换 `LiquidActionButton` / `LiquidNavigationButton`（iconOnly/specificationForm）；命中区与 tooltip 不退化；**host-owned plain 行，消除叠玻璃**。
- [ ] LQ05 侧栏表面：侧栏换 `LiquidSurface`(regular)（持续玻璃 2/2）；分隔线、行高 30、选中行 tint α .13 保持。
- [ ] LQ06 侧栏分类：`KosCheckBox` → `LiquidCheckBox`，16×16、圆角 4、选中 accent + 白勾；复验 S03/S04。
- [ ] LQ07 事件编辑器：`EventEditorDialog` 换 `LiquidDialog`（圆角 24、E4、scrim .25）+ `LiquidTextField`；保持 D05–D12。
- [ ] LQ08 任务编辑器：`CalendarTaskEditorDialog` 同上，按钮竖排通栏等宽、主次仅填充区分。
- [ ] LQ09 详情浮层：`EventDetailsPopover` 用 `LiquidSurface`（上层 fill α .06，禁叠玻璃）+ `LiquidOuterShadow`；P01/P02 不回归。
- [ ] LQ10 右键菜单：菜单项换统一 plain 行 + hoverFill，项高 28–32、图标 16；O04–O07。
- [ ] LQ11 tooltip：统一深色实心 `rgba(0,0,0,.85)`、11/14、内边距 6×10、延迟 500ms、靠边翻转；O01–O03/O09。
- [ ] LQ12 月视图：V01–V05 + M04（today 红圈、其他选中灰/描边、外月 muted、事件条不裁切）。
- [ ] LQ13 全天条：A01–A04（最小 28、行 18、gap 2、inset 2–3、连续跨天、`+N` 溢出）。
- [ ] LQ14 事件块：E01–E06 + N01–N02（tint、左侧 2–3 stripe、inset 4、列 gap 2、今日红线/徽标）。
- [ ] LQ15 窄窗：X01/X02/P03/D11 在 760×540 回归，弹框不裁切、按钮不换行。
- [ ] LQ16 空/密/深色：X04/X05/X03 回归；L0 区域无玻璃，深色无霓虹事件块。
- [ ] LQ17 底色与 chrome：S01/S04/C05，画布与侧栏层级、窗口圆点 hover/pressed/inactive。
- [ ] LQ18 最终对照：X06（日历/设置并排）+ X07（弹框/浮层/菜单/tooltip 同屏），
      以及 spec.md 全量 PENDING 清零、所有 PASS 重新回归。

## 已改
- LQ03 `apps/calendar/qml/Main.qml:1889-1912`：`viewSegment` 加 `materialForm: true`（L0/L1 上不再叠
  LiquidSurface），track/pill 使用既有 `segmentTrack`/`segmentPill`，并新增 `borderColor`（light α .05 /
  dark 白 α .10）。
- LQ03 `shared/qml/controls/LiquidSegmentedControl.qml:23-28,109`：新增 `property color borderColor`
  （默认 `Foundation.AppTheme.border`，其它调用点行为不变），material 容器描边改读它。
- LQ04 `apps/calendar/qml/Main.qml:955-993`：`ToolbarButton` 改为继承 `LiquidActionButton`，
  `materialForm: true` / `iconOnly: true` / `surfaceColor: "transparent"`，自带 `hint`、TabFocus、
  tooltip；background 换成 host-owned plain Rectangle（r=height/2，hover=`rowHoverFill`，
  press=`selectionFill`，focus 1px 内描边）。删除已无用的本地 `CalendarToolbarIcon`。
- LQ04 `apps/calendar/qml/Main.qml:1875-1906`、`1948-1958`、`2095-2106`：侧栏开关/添加/搜索/更多
  去掉 `lensBackdrop`/`lensBackdropWindow`/`lensActiveOverride`；更多按钮由手写三点 `AbstractButton`
  + `GlassSurface` 改为 `ToolbarButton { iconName: "more" }`。
- LQ02 `apps/calendar/qml/Main.qml:215-223`、`1841-1873`：工具栏浮动胶囊（inset 16、float 8、r 20，
  `LiquidOuterShadow` L2 + `LiquidSurface` regular）。
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件（LiquidStyle/LiquidSurface/LiquidBackdrop/
  LiquidCard/LiquidActionButton/LiquidNavigationButton/LiquidCheckBox/LiquidDialog/
  LiquidOuterShadow/VectorIcon 等及 shaders）。

## 仍差
1. 侧栏仍是旧平面，未用 `LiquidSurface`(regular)（LQ05）。
2. 编辑器/详情浮层/菜单/tooltip 仍是旧组件（LQ07–LQ11）。
3. 工具栏胶囊是静态材质，无背景采样；其下没有可折射内容（外推，见下）。
4. 窄窗列宽约 77px，事件块标题截断到 4–5 字；是否属预期留待 LQ15 判。
5. 月视图、全天条、事件块的 tint/描边细节尚未对照（LQ12–LQ14）。
6. tooltip 仍是旧样式（白底方角），悬停验证只确认「会出、文案对」，样式归 LQ11。
7. 分段描边为折中值：参考只有圆头两端 ~222、顶边无线，单一描边无法同时满足；现取 α .05（244..247）。

## 外推待确认
- 工具栏玻璃按「整条浮动胶囊」解释：参考图顶部是透明窗面 + 独立玻璃圆钮，没有整条玻璃带；
  但队列与预算把工具栏记为 1 组 L1 持续玻璃，故按 liquid-spec 浮动工具栏（高 40、r 20、浮 8、E2）执行。
  其下为不透明平面且无内容滚入，故**不挂 backdrop**，材质由 bezel/rim/外阴影承担；light 下右半边白上白，
  主要靠阴影与边缘辨认。若需要更强可见度，后续可加 α .06 的 plain 填充或 1px 内描边。
- 工具栏按钮的 hover/press 填充刻意不用 LiquidActionButton 自带的 materialForm 背景（其颜色取自
  `Foundation.AppTheme`，与日历 tahoe 调色板不同源），改由宿主 plain 行提供，确保 light/dark 与侧栏行一致。
- LQ03 分段容器描边：token 表只有输入框 border α .14；参考实测顶边 249..253（≈无线）、圆头两端 ~222，
  故日历取 light α .05 / dark 白 α .10（表外值）。若后续拿到深色参考再定。
- LQ03 dark 分段色为外推：track 白 α .06、pill `#3C3C3C`（实测 42,42,43 / 60,60,60），无深色参考。
- 日历侧栏用 `LiquidNavigationButton` 还是保留分类勾选行：按参考图为勾选行，暂定保留行结构，
  仅换表面与复选框；LQ05/LQ06 实拍后确认。
- 1100×720 在 VM 内实际内容高 692；基线以 692 记录，不视为布局差异。

## Next round
LQ05 侧栏表面：侧栏换 `LiquidSurface`(regular)（持续玻璃 2/2）；分隔线、行高 30、选中行 tint α .13 保持。
