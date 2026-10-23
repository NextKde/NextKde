# R305 — 窄窗采集根因实测确认；grabToImage 不可用；harness 采集重建（尺寸日志）

## 本轮
- **根因确认（实测，非推断）**：Wayland 下客户端 `QWindow::resize()` 不会让 toplevel
  surface 重配/重绘。resize 760×540 后 `grabWindow()` 仍是 1100×692，其不透明内容为
  `QRect(0,152 761×389)`（场景只画在 buffer 行 152..540）；再把窗口 resize 回 1100×692，
  grab 返回**同一张陈旧内容**（宽仍 761）——surface 不恢复。
  xdg-shell 无客户端主动 toplevel resize；`setMinimumSize/setMaximumSize` 不会让 KWin
  下发 configure（R304 现象复现）。Qt 只改了自身 QWindow 几何（日志 `window 760×540`），
  buffer 停在初始的 1100×692。
- `QQuickItem::grabToImage()`（contentItem）在该状态下 **ready 信号永不触发**（无渲染帧），
  不能作为采集旁路；已放弃，不再试。
- harness 采集已重建并加载：记录 `window` / `content item` / `dpr`，`grabWindow()` 后按
  alpha bbox 定位场景块再裁切。
  - 健康窗口（新启动、未 resize）实测输出 **1100×692 全帧**，bbox 全幅，无回归。
  - 一旦 resize 过，本会话后续抓帧全部不可用，**必须重启 app** 才能再采。

## 已改
- `tmp/.../harness/ReviewInput/ReviewInput.cpp`（tmp，不入库）capture()：顶裁 → alpha-bbox
  裁切 + 尺寸日志；`libreviewinput.so` 已重建并加载。
- 产品代码无改动（验证轮）。

## 仍差
1. 760×540 全窗帧仍不可得：resize 后 surface 冻结，现有窄窗帧只是旧缓冲里的
   760×388 中段切片（无工具栏/月头/底部），不能做全窗视觉复核。
2. 2027-02 的 4 行等分只在“中段切片”内量过，全窗几何未复核。
3. 动效未验证（无连续帧，不声称通过）。
4. 合成器级玻璃帧（窗口圆角/外阴影/desktop backdrop）仍不可拍：portal 授权无人值守。
5. 旧 `harness/LEDGER.md` 的 Next round 段落停在 R183，与 state.md 不同步（不影响本轮）。

## 外推待确认
- 若 review 窗口**以 760×540 启动**（初始 configure 即窄尺寸），采集应正常；待验证。
- 窄窗启动开关应只影响窄窗轮次，默认仍 1100×692，避免破坏既有量测基线。

## 需要你
a) 若要合成器级玻璃帧，需人工在 portal 截屏授权弹窗点一次“允许”（本环境无人值守）。

## Next round
1. 让窗口**以 760×540 启动**而不是事后 resize：harness 根窗口按开关（env 或 harness
   属性）声明 `width/height 760×540`（默认仍 1100×692），重启后直接 `captureClient`。
   成功判据 = 全帧 760×540、无透明带、含工具栏/月头/底行。
2. 通过后重拍 2027-02 全窗，复核 4 行等分与工具栏/月头。
若 #1 仍被 Wayland 初始尺寸忽略：停手，在 state 记阻塞，不再换法。
