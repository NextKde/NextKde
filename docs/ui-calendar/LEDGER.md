# R0 — 收尾轮：人工裁定后执行

## 本轮
- VERIFY-2 完成：新建任务编辑器空字段占位符补拍。
  驱动路径：taskEditor 实例补 `objectName: "taskEditorDialog"`（Main.qml，唯一源码改动，
  零视觉）；harness 侧 PointerDriver 加 `objectNamed`（QObject findChild）+ harness Main.qml
  加通用 `invoke` 动作（tmp/，不入库）→ `openForTodo(null)` 直开弹窗（绕开 toolbarMore
  原生 popup 菜单不可合成的老阻塞）。
  实拍 `shots/verify2-newtask-light.png`（1100×720）+ 3x 裁块
  `shots/verify2-title-3x.png` / `verify2-datetime-3x.png` / `verify2-notes-3x.png`。
  确认：标题占位「任务标题」、截止日期占位 `YYYY/MM/DD`（I7 locale 化后的 datePattern）、
  备注占位「备注（可选）」均以 labelSecondary 浅墨呈现，字段空态清晰。
  观察：时间字段新建态预填默认值 `18:00`（深墨，非占位符）——timePattern 占位符
  在新建态不露出，属应用既有行为，非缺陷。
  构建✅ light 启动✅ runtime log 0 error 0 warning。

## 队列（一轮一条；✅=已改）
- [x] P2-3a 月视图 today 文字 → `"white"`
- [x] P1-A6b 窗口圆点：命中区 22×22、Accessible.role/name、键盘可达（视觉几何不动）
- [x] VERIFY-1 议程徽标 10px 补拍
- [x] VERIFY-2 新建任务编辑器空占位符补拍

## 仍差
*(无)*

## Next round
*(无 — 队列已清空)*

DONE

## 注意
- 只改 finding 涉及的文件/行，不顺手重构。
- 每轮必须构建通过 + 应用能起。
- 全部完成后在下面单独一行写 `DONE`。
