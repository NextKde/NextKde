# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ08 ✓ 任务编辑器 `CalendarTaskEditorDialog` 迁 `LiquidDialog` + `LiquidTextField`：
  - `:8` `KosWorkspaceDialog → LiquidDialog`，删除本地 `KosSurface` 背景；`padding: 24`、
    标题 17/600、r24 卡片/E4 阴影/.25 遮罩继承共享弹框。
  - 标题/截止日期/时间 3 个 `KosTextField → LiquidTextField`（`specificationForm`、
    `invalid` 红环），I5/I7 校验与 payload 未动。
  - 表单改 56px 标签列（标题/清单/截止日期/备注），与事件编辑器同一语法；
    备注框改 plain α .06/r10，焦点改为与字段一致的 2px 外环。
  - `KosComboBox` 新增 `fillColor/cornerRadius/strokeWidth`（默认值不变）；任务编辑器的
    清单/优先级组合框设 plain 240/r10/无描边，与字段同色。
- 实拍 `LQ08-task-light-v2.png`（1100×692）：卡片 380×559、r24；字段与组合框/备注填充均 240；
  保存 (48,140,198) 实心；取消 (227,229,230)。`LQ08-task-edit-error-light.png`：三行按钮
  x384..730 = 347、高 31、pitch 37（D05 任务编辑器补齐）；空标题保持弹框并显示红字 +
  标题框红环（I4 首错语义未变）。
- 日志：app + pim 0 error / 0 warning。玻璃预算：瞬态 1/1（弹框），内部无玻璃；持续 2/2。
- 未验证：dark、760×540（D11）、D08 hover/pressed/focus、D10 连续帧。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：light week 1100×720 / 760×540；日志无启动回归。
- [x] LQ02 工具栏：`LiquidSurface`(regular) + `LiquidOuterShadow`；持续玻璃 1/2。
- [x] LQ03 分段控件：`LiquidSegmentedControl` materialForm，228×28、pill 231。
- [x] LQ04 工具栏按钮：`LiquidActionButton` + host-owned plain 行；无叠玻璃。
- [x] LQ05 侧栏表面：`LiquidSurface`(regular)，合成 237（持续 2/2）。
- [x] LQ06 侧栏分类：`LiquidCheckBox` 12×12/r3 视觉。
- [x] LQ07 事件编辑器：`LiquidDialog` + `LiquidTextField`，r24/.25 scrim/D05 几何不变。
- [x] LQ08 任务编辑器：同上 + 标签列对齐、组合框 plain、备注外环；D05 三行按钮已验。
- [ ] LQ09 详情浮层：`EventDetailsPopover` 用 `LiquidSurface`（fill α .06，禁叠玻璃）+
      `LiquidOuterShadow`；P01/P02 不回归。
- [ ] LQ10 右键菜单：统一 plain 行 + hoverFill，项高 28–32、图标 16；O04–O07。
- [ ] LQ11 tooltip：深色实心 rgba(0,0,0,.85)、11/14、6×10、500ms、靠边翻转；O01–O03/O09。
- [ ] LQ12 月视图：V01–V05 + M04（today 红圈、其他选中灰/描边、外月 muted、事件条不裁切）。
- [ ] LQ13 全天条：A01–A04（最小 28、行 18、gap 2、inset 2–3、连续跨天、`+N` 溢出）。
- [ ] LQ14 事件块：E01–E06 + N01–N02（tint、左侧 2–3 stripe、inset 4、列 gap 2、今日红线/徽标）。
- [ ] LQ15 窄窗：X01/X02/P03/D11 在 760×540 回归，弹框不裁切、按钮不换行。
- [ ] LQ16 空/密/深色：X04/X05/X03 回归；L0 无玻璃，深色无霓虹事件块。
- [ ] LQ17 底色与 chrome：S01/S04/C05，画布/侧栏层级、窗口圆点三态。
- [ ] LQ18 最终对照：X06 + X07；spec 全量 PENDING 清零、PASS 回归。

## 已改
- LQ08：`apps/calendar/qml/CalendarTaskEditorDialog.qml:8,26-46,53` 基类/标题/内边距；
  字段 `:500-590`；备注 `:621-670`；`shared/qml/foundation/KosComboBox.qml:4-21` 新增外观参数。
- LQ07：`EventEditorDialog.qml:8` 基类 `LiquidDialog`；`LiquidTextField.invalid` 新增。
- LQ02–LQ06 详见 rounds.md（工具栏/分段/按钮/侧栏/勾选）。
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件与 shaders。

## 仍差
1. 事件编辑器的组合框（重复/提醒/列表/优先级）仍是 250 底 + 1px 边，与旁边 plain 240
   字段并排有色差（任务编辑器已对齐）；LQ18 前统一。
2. 事件编辑器备注框焦点环仍是 `KosSurface` 内嵌 2px，未换成 task editor 的外扩环。
3. dark 与 760×540 的本轮改动未实拍；D08 hover/pressed/focus、D10 出现/消失连续帧未验证。
4. 任务编辑器卡片固定 560 高，备注底到保存条留白 151px（事件编辑器 77）；HIG 要求 sheet
   贴合内容，但本轮两次回路已用完，未改高度，留 LQ15 窄窗一并定。
5. 详情浮层/菜单/tooltip 旧组件（LQ09–LQ11）。
6. 月视图、全天条、事件块 tint/描边尚未对照（LQ12–LQ14）。
7. 侧栏接缝 224 略清晰（参考 236→255 几乎无线），归 LQ17。
8. 侧栏勾号笔画偏细、框 r3 vs 参考视觉 ~4，1px 歧义按 S03 从 3；留 LQ18。

## 外推待确认
- 任务编辑器标签列 56、字段填充 240 直接复用事件编辑器实测值；标题上方 12px 间距沿用。
- 任务编辑器保留 560 固定高（与事件编辑器 620 同策略）：内容更短导致留白较大，未擅改，
  待窄窗回归时决定是否按 `editing` 收缩到 ~460/500。
- `KosComboBox` 新参数默认值 = 旧渲染；仅任务编辑器传 plain 值，其它调用点零变化。
- `.25` 遮罩、r24、E4 阴影均来自 `LiquidDialog`，与 LQ07 实测一致；浅色卡白 vs 旧 `#F7F7F7` 差一档，
  按共享材质接受。
- 工具栏按「整条浮动胶囊」解释、侧栏替身底色、LQ03 分段描边/dark 值等仍见 rounds.md 既往节。
- 1100×720 在 VM 内实际内容高 692，基线按 692。

## Next round
LQ09 详情浮层：`EventDetailsPopover` 换 `LiquidSurface`（上层 fill α .06、禁叠玻璃）+
`LiquidOuterShadow`，P01/P02 不回归。
