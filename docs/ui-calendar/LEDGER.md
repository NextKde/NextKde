# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ10 ✓ 工具栏 More 菜单：Qt `Menu` 保留键盘导航/自动定位，外观自绘——卡片 `neutralPlane` 底 +
  `LiquidSurface` regular（white .58 / #1C1C1E .52，r16，E3 `LiquidOuterShadow`）＋ 36px 阴影
  预留边；行改 `MenuActionRow`（纯平面、无叠玻璃）：行高 30（O04 28–32）、图标 16、图标左缘
  距卡 10、文本 13、左内边距 10；hover/press 用侧栏同款 `rowHoverFill`/新 `rowPressFill`，
  8px 圆角内缩 8；分隔线 1px `.separator` 内缩 10（去掉 Basic 样式的通栏粗线）。
- 内容分 3 组（新建任务 | 导入/导出 | 设置），四项均按语义配 16px 图标（plus/download/
  preview/settings）；无快捷键重复、无破坏性项，O05/O06 现状即满足。
- 实拍 1100×692 light `LQ10-menu-light-v2.png` + hover `LQ10-menu-hover.png`；dark
  `LQ10-menu-dark.png`。亮色卡片为纯白（内容平面本身是白，regular 填充无可见色偏），
  暗色卡面比页高一级、white .12 描边、hover 可见；键盘 `highlighted` 与 hover 同一填充。
- 玻璃预算：持续 2/2；瞬态 1/1（菜单是唯一 L2 玻璃，菜单内部零玻璃）。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：light week 1100×720 / 760×540；日志无启动回归。
- [x] LQ02 工具栏：`LiquidSurface`(regular) + `LiquidOuterShadow`；持续玻璃 1/2。
- [x] LQ03 分段控件：`LiquidSegmentedControl` materialForm，228×28、pill 231。
- [x] LQ04 工具栏按钮：`LiquidActionButton` + host-owned plain 行；无叠玻璃。
- [x] LQ05 侧栏表面：`LiquidSurface`(regular)，合成 237（持续 2/2）。
- [x] LQ06 侧栏分类：`LiquidCheckBox` 12×12/r3 视觉。
- [x] LQ07 事件编辑器：`LiquidDialog` + `LiquidTextField`，r24/.25 scrim/D05 几何不变。
- [x] LQ08 任务编辑器：同上 + 标签列对齐、组合框 plain、备注外环；D05 三行按钮已验。
- [x] LQ09 详情浮层：`LiquidSurface`（plain α .06、禁叠玻璃）+ `LiquidOuterShadow`，r16；P01 未回归。
- [x] LQ10 右键菜单：`MenuActionRow` 行高 30/图标 16/左内 10、plain + hoverFill、1px 分隔线；
  r16 regular E3 卡片、36px 阴影边；light/dark 已拍。O04–O07（O09 未做）。
- [ ] LQ11 tooltip：深色实心 rgba(0,0,0,.85)、11/14、6×10、500ms、靠边翻转；O01–O03/O09。
- [ ] LQ12 月视图：V01–V05 + M04（today 红圈、其他选中灰/描边、外月 muted、事件条不裁切）。
- [ ] LQ13 全天条：A01–A04（最小 28、行 18、gap 2、inset 2–3、连续跨天、`+N` 溢出）。
- [ ] LQ14 事件块：E01–E06 + N01–N02（tint、左侧 2–3 stripe、inset 4、列 gap 2、今日红线/徽标）。
- [ ] LQ15 窄窗：X01/X02/P03/D11 在 760×540 回归，弹框不裁切、按钮不换行。
- [ ] LQ16 空/密/深色：X04/X05/X03 回归；L0 无玻璃，深色无霓虹事件块。
- [ ] LQ17 底色与 chrome：S01/S04/C05，画布/侧栏层级、窗口圆点三态。
- [ ] LQ18 最终对照：X06 + X07；spec 全量 PENDING 清零、PASS 回归。

## 已改
- LQ10：`apps/calendar/qml/Main.qml:230-243` 菜单 token、`:190-193` `rowPressFill`；
  `:1103-1181` `MenuActionRow`/`MenuGroupSeparator`；`:2162-2252` 触发定位 + 自绘 `Menu`
  （卡片/阴影/玻璃、四项图标、分组）。LQ09 细节移入 rounds.md。
- LQ08：`apps/calendar/qml/CalendarTaskEditorDialog.qml:8,26-46,53` 基类/标题/内边距；
  字段 `:500-590`；备注 `:621-670`；`shared/qml/foundation/KosComboBox.qml:4-21` 新增外观参数。
- LQ07：`EventEditorDialog.qml:8` 基类 `LiquidDialog`；`LiquidTextField.invalid` 新增。
- LQ02–LQ06 详见 rounds.md（工具栏/分段/按钮/侧栏/勾选）。
- `shared/qml/**`：同步 nextkdeAppDemo 液态组件与 shaders。

## 仍差
1. 事件编辑器的组合框（重复/提醒/列表/优先级）仍是 250 底 + 1px 边，与旁边 plain 240
   字段并排有色差（任务编辑器已对齐）；LQ18 前统一。
2. 事件编辑器备注框焦点环仍是 `KosSurface` 内嵌 2px，未换成 task editor 的外扩环。
3. 详情浮层阴影在白底上偏弱（约 4%/10px，参考更宽更柔）；level 2→3 已用掉两次回路，
   留 LQ10/LQ11 建立共享浮层材质时一并复核，避免三处各调一次。
4. 任务编辑器卡片固定 560 高，备注底到保存条留白 151px（事件编辑器 77）；D11 窄窗一并定。
5. 浮层 dark 已验；P03 的 point 分支、760×540 浮层、出现/消失连续帧未验证（P02 未触及）。
6. 菜单：O09 边缘翻转未实现（现为右侧 clamp，卡片右缘距窗 36）；亮色卡在白底上纯白、无参考的
   磨砂色偏（regular 填充在白底没有可采内容）；hover 半径 8 小于参考示意 ~12；按下/开合连续帧、
   键盘上下/回车路径未验证。tooltip 仍是旧组件（LQ11）。
7. 月视图、全天条、事件块 tint/描边尚未对照（LQ12–LQ14）。
8. 侧栏接缝 224 略清晰、勾号笔画偏细（r3 vs 参考 ~4），归 LQ17/LQ18。

## 外推待确认
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
  未按其绝对尺寸。高亮圆角 8 为表外外推（参考示意约 12），待 LQ11 建共享浮层语言时复核。
- 菜单阴影预留 36 与 LQ09 浮层同法；菜单贴右缘时为保证阴影完整，卡片右缘停在窗口内 36，
  比按钮右缘内收 20，未做 O09 翻转。
- 1100×720 在 VM 内实际内容高 692，基线按 692。

## Next round
LQ11 tooltip：深色实心 rgba(0,0,0,.85)、11/14、内边距 6×10、约 500ms 延迟、靠边翻转，
O01–O03/O09。先找参考 `offering-help-macos-tooltip-help-tag.png` 与现有 ToolTip 用法
（`Main.qml` 顶部已按亮/暗给 palette 的两槽着色；`ToolbarButton.hint` 是现成文案源）。
