# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ06 ✓ 侧栏分类勾选改共用 `LiquidCheckBox`：`LiquidCheckBox.qml` 增加
  `indicatorSize/indicatorRadius/fillColor/fillStrength/uncheckedFillStrength/checkColor/
  checkVisible/indicatorBorderWidth/indicatorBorderColor`（默认 22/r7/accent 不变）；
  `Main.qml:464` 用 disabled 视觉实例承接勾选框，行仍由 `CategoryRow` 处理点击。
- 未按队列写 16×16/r4：实测参考勾选框 **12×12**（行 82..93 / x17..28），且 S03 已 PASS
  12-square r3；16px 相对本应用 13px 标签会明显偏大（16:13 vs 参考 12:16）。故保持 12/r3，
  仅做组件迁移与勾选绘制统一。
- 实拍 `LQ06-1100-light-v3.png` / `LQ06-hover-v3.png` / `LQ06-toggle.png`（tmp，不入库）：
  勾选框 x12..23（嵌套行 x36..47）、高 12、行距 30、标签 gap 8；hover 行填充 227
  （参考选中行 226），行圆角 6。点击勾选框坐标仍能切换分类（disabled 视觉实例不吞事件），
  勾选/未勾选（橙色 1px 空心）可辨；app + pim 日志 0 error / 0 warning。
- 仍差（下轮可顺带）：勾号用 12px 下 8px 字号 ✓，笔画比参考的粗勾细；圆角保持 3（参考视觉约 4，
  1px 内歧义且 S03 记为 3）。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：在新组件树上启动 light week，截 1100×720 与 760×540；记录 runtime log 的 error/warning，确认无启动回归。
- [x] LQ02 工具栏：`Main.qml` 顶部工具栏换 `LiquidSurface`(regular) + `LiquidOuterShadow`；保留 L02–L04 的 40 高、按钮 28–30、分段居中几何；持续玻璃 1/2。
- [x] LQ03 分段控件：Day/Week/Month/Year 换 `LiquidSegmentedControl`，高 28、胶囊、pill 当前视图；宽度随 4 段重算并保持主区域居中。
- [x] LQ04 工具栏按钮：prev/Today/next、侧栏开关、搜索、添加、更多换 `LiquidActionButton` / `LiquidNavigationButton`（iconOnly/specificationForm）；命中区与 tooltip 不退化；**host-owned plain 行，消除叠玻璃**。
- [x] LQ05 侧栏表面：侧栏换 `LiquidSurface`(regular)（持续玻璃 2/2）；分隔线、行高 30、选中行 tint α .13 保持。
- [x] LQ06 侧栏分类：勾选框改共用 `LiquidCheckBox` 视觉（12×12/r3，分类色 + 白勾，未选 1px 空心）；复验 S03/S04。
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
- LQ06 `apps/calendar/qml/Main.qml:464`：CategoryRow 的勾选框由手绘 Rectangle+双斜条 V
  改为 `LiquidCheckBox`（disabled 视觉、行持有交互）；12×12、r3、solid 分类色、白勾、
  未选 1px 分类色空心。`shared/qml/controls/LiquidCheckBox.qml:12-38`：尺寸/圆角/填充色/
  填充强度/勾色/勾可见/描边可配，默认值保持 22/r7/accent/15px 深色勾不变。
- LQ05 `apps/calendar/qml/Main.qml:1757-1785`：侧栏底面改 `#D4D4D4` / `#353535` 替身，其上叠
  `LiquidSurface`(regular)（白 .58 / `#1C1C1E` .52、`diffuseStrength:1`、rim/reflection 关）。
  合成 light 237、dark 40；分隔线、行高、选中 tint 未改。
- LQ02–LQ04 详情见 rounds.md（工具栏 LiquidSurface+阴影、LQ03 分段 materialForm、LQ04 plain 行）。
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件（LiquidStyle/LiquidSurface/LiquidBackdrop/
  LiquidCard/LiquidActionButton/LiquidNavigationButton/LiquidCheckBox/LiquidDialog/
  LiquidOuterShadow/VectorIcon 等及 shaders）。

## 仍差
1. 编辑器/详情浮层/菜单/tooltip 仍是旧组件（LQ07–LQ11）。
2. 工具栏胶囊是静态材质，无背景采样；其下没有可折射内容（外推，见下）。
3. 侧栏接缝：参考 236→255 几乎无线（仅 AA），现分隔线实测 224 略清晰；归 LQ17 chrome 复核。
4. 窄窗列宽约 77px，事件块标题截断到 4–5 字；是否属预期留待 LQ15 判。
5. 月视图、全天条、事件块的 tint/描边细节尚未对照（LQ12–LQ14）。
6. tooltip 仍是旧样式（白底方角），悬停验证只确认「会出、文案对」，样式归 LQ11。
7. 分段描边为折中值：参考只有圆头两端 ~222、顶边无线，单一描边无法同时满足；现取 α .05（244..247）。
8. 侧栏勾号笔画比参考细（12px 框内 8px 字号 ✓，参考笔画约 2px）；框圆角保持 3、参考视觉约 4，
   1px 内歧义按 S03 从 3。留 LQ18 终检决定是否加粗/改 r4。

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
- LQ05 侧栏无真实背景可采样（窗口是不透明平面）：用 `#D4D4D4` / `#353535` 作未采样替身，使 regular
  填复合到参考实测 237 / 原深色 40；`diffuseStrength:1` 只给 pigmented 面光，不声称模糊。替身值属
  表外；若后续拿到壁纸或透明窗口，应换真 backdrop 并删除替身。
- 1100×720 在 VM 内实际内容高 692；基线以 692 记录，不视为布局差异。
- LQ06 队列原写 16×16/r4：参考实测 12×12（x17..28 / y82..93），且 S03 已记 12/r3 PASS；
  1.35 倍的 16 是把参考图 (814 宽) 当 1100 逻辑宽的误换算。按参考与 S03 保持 12/r3，
  组件可配参数留给后续需要 16 的弹框勾选。

## Next round
LQ07 事件编辑器：`EventEditorDialog` 换 `LiquidDialog`（圆角 24、E4、scrim .25）+ `LiquidTextField`；保持 D05–D12。
