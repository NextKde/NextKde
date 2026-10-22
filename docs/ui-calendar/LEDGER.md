# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ01 基线完成：构建 no work to do；light 启动 ✓。
  实拍：默认周 2026-10-15 `LQ01-week-1100x720-light.png`、`LQ01-week-760x540-light(-crop).png`；
  fixture 周 2026-04-02 `LQ01-fixture-1100-light.png`、`LQ01-fixture-760-light(-crop).png`（tmp，不入库）。
  app + pim 日志均 **0 error / 0 warning**；事件、全天条、迷你月均正常渲染，无启动回归。
- 量测：请求 1100×720 实际内容 1100×**692**（VM 可用高度上限），后续基线按 692 记录；
  窄窗 760×540 生效，但 `captureClient` 画布固定 1100×692，右侧黑边，读图前裁至 760×540。
- 启动态侧栏为展开（本 profile 持久状态，非回归）。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：在新组件树上启动 light week，截 1100×720 与 760×540；记录 runtime log 的 error/warning，确认无启动回归。
- [ ] LQ02 工具栏：`Main.qml` 顶部工具栏换 `LiquidSurface`(regular) + `LiquidOuterShadow`；保留 L02–L04 的 40 高、按钮 28–30、分段居中几何；持续玻璃 1/2。
- [ ] LQ03 分段控件：Day/Week/Month/Year 换 `LiquidSegmentedControl`，高 28、胶囊、pill 当前视图；宽度随 4 段重算并保持主区域居中。
- [ ] LQ04 工具栏按钮：prev/Today/next、侧栏开关、搜索、添加、更多换 `LiquidActionButton` / `LiquidNavigationButton`（iconOnly/specificationForm）；命中区与 tooltip 不退化。
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
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件（新增 LiquidStyle/LiquidSurface/LiquidBackdrop/
  LiquidCard/LiquidActionButton/LiquidNavigationButton/LiquidCheckBox/LiquidDialog/
  LiquidOuterShadow/VectorIcon 等及 shaders）。
- LQ01：无源码改动，仅建立视觉基线。

## 仍差
1. 工具栏仍是旧实心+玻璃圆钮组合，无 `LiquidSurface`(regular) 与外阴影（LQ02/LQ04）。
2. 侧栏仍是旧平面，无 `LiquidSurface`(regular)（LQ05）。
3. 日/周/月/年仍是旧分段样式，未用 `LiquidSegmentedControl`（LQ03）。
4. 编辑器/详情浮层/菜单/tooltip 仍是旧组件（LQ07–LQ11）。
5. 窄窗列宽约 77px，事件块标题截断到 4–5 字；是否属预期留待 LQ15 判。
6. 月视图、全天条、事件块的 tint/描边细节尚未对照（LQ12–LQ14）。

## 外推待确认
- 日历侧栏用 `LiquidNavigationButton` 还是保留分类勾选行：按参考图为勾选行，暂定保留行结构，
  仅换表面与复选框；LQ05/LQ06 实拍后确认。
- 1100×720 在 VM 内实际内容高 692；基线以 692 记录，不视为布局差异。

## Next round
LQ02 工具栏换 LiquidSurface(regular) + LiquidOuterShadow。
