# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ02 ✓ 工具栏换成 1 组浮动 regular 玻璃胶囊 + E2 外阴影（`calendarToolbarMaterial`：左/右浮 8、
  高 40、r 20）；内容左右缩进 12/14→16，即按钮距胶囊内缘 8。1100 light/dark 实拍 + 760×540 窄窗实拍：
  分段仍精确居中于主区，按钮 28 不变，pim/app 日志 **0 error / 0 warning**。
- 量测：light 胶囊 tint w .58、dark #1C1C1E .52（liquid-spec §3 regular）；rim 亮 .45 / 暗 .30；
  外阴影 L2（opacity .16 / spread 16 / offsetY 2）。
- 胶囊无可采样背景（其下是不透明平面、无内容滚入），材质走静态 bezel+rim+阴影，不注册 backdrop；
  记入「外推待确认」。
- 遗留：胶囊内的旧 GlassSurface 圆钮仍是玻璃，形成叠玻璃——已列为 LQ04 首要修复，故下一轮先做 LQ04。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：在新组件树上启动 light week，截 1100×720 与 760×540；记录 runtime log 的 error/warning，确认无启动回归。
- [x] LQ02 工具栏：`Main.qml` 顶部工具栏换 `LiquidSurface`(regular) + `LiquidOuterShadow`；保留 L02–L04 的 40 高、按钮 28–30、分段居中几何；持续玻璃 1/2。
- [ ] LQ03 分段控件：Day/Week/Month/Year 换 `LiquidSegmentedControl`，高 28、胶囊、pill 当前视图；宽度随 4 段重算并保持主区域居中。
- [ ] LQ04 工具栏按钮：prev/Today/next、侧栏开关、搜索、添加、更多换 `LiquidActionButton` / `LiquidNavigationButton`（iconOnly/specificationForm）；命中区与 tooltip 不退化；**host-owned plain 行，消除叠玻璃**。
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
- `apps/calendar/qml/Main.qml:215-222`：toolbarInsetLeft 12→16、toolbarInsetRight 14→16，新增
  `toolbarFloat: 8` / `toolbarRadius: toolbarHeight/2`。
- `apps/calendar/qml/Main.qml:1840-1876`：新增 `toolbarMaterial`（z:-1）＝ `LiquidOuterShadow`
  （shadowLevel 2，outwardOffset 1）+ `LiquidSurface`（regular：light #FFF .58 / dark #1C1C1E .52，
  rim .45/.30，edgeWidth 14，reflection 1），锚定 toolbar 左右各缩 8、满高 40。
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件（新增 LiquidStyle/LiquidSurface/LiquidBackdrop/
  LiquidCard/LiquidActionButton/LiquidNavigationButton/LiquidCheckBox/LiquidDialog/
  LiquidOuterShadow/VectorIcon 等及 shaders）。
- LQ01：无源码改动，仅建立视觉基线。

## 仍差
1. 工具栏圆钮仍是旧的本地 `GlassSurface`，压在玻璃胶囊上 → **玻璃叠玻璃**；LQ04 改 host-owned plain 行时消除。
2. 日/周/月/年仍是旧分段样式，未用 `LiquidSegmentedControl`（LQ03）。
3. 侧栏仍是旧平面，未用 `LiquidSurface`(regular)（LQ05）。
4. 编辑器/详情浮层/菜单/tooltip 仍是旧组件（LQ07–LQ11）。
5. 工具栏胶囊是静态材质，无背景采样；其下没有可折射内容（外推，见下）。
6. 窄窗列宽约 77px，事件块标题截断到 4–5 字；是否属预期留待 LQ15 判。
7. 月视图、全天条、事件块的 tint/描边细节尚未对照（LQ12–LQ14）。

## 外推待确认
- 工具栏玻璃按「整条浮动胶囊」解释：参考图顶部是透明窗面 + 独立玻璃圆钮，没有整条玻璃带；
  但队列与预算把工具栏记为 1 组 L1 持续玻璃，故按 liquid-spec 浮动工具栏（高 40、r 20、浮 8、E2）执行。
  其下为不透明平面且无内容滚入，故**不挂 backdrop**，材质由 bezel/rim/外阴影承担；light 下右半边白上白，
  主要靠阴影与边缘辨认。若需要更强可见度，后续可加 α .06 的 plain 填充或 1px 内描边。
- 日历侧栏用 `LiquidNavigationButton` 还是保留分类勾选行：按参考图为勾选行，暂定保留行结构，
  仅换表面与复选框；LQ05/LQ06 实拍后确认。
- 1100×720 在 VM 内实际内容高 692；基线以 692 记录，不视为布局差异。

## Next round
LQ04 工具栏按钮（先于 LQ03）：侧栏开关、添加、搜索、更多换 host-owned plain 行（iconOnly，
28×28 命中区、tooltip 不退化），消除胶囊上的叠玻璃；日期导航 prev/Today/next 同步检查。

