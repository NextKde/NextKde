# R302 — FIX-02 窄窗干净全窗实拍

## 本轮
- FIX-02 结清。根因不是裁剪问题：Wayland 下 `Window.width/height` 只改 QML 逻辑尺寸，
  toplevel 仍由合成器保持 1100×692；`grabWindow()` 返回陈旧缓冲区，场景落在缓冲区底部，
  之前按左上裁剪才会出现“内容只占左上 760×540 + 黑边”。
- 修法两层：
  1. `harness/Main.qml:281` `resize` 命令同时把 `minimumWidth/Height` 与
     `maximumWidth/Height` 钉到目标尺寸，让 KWin 下发 760×540 configure，surface 真正变成 760×540。
  2. `harness/ReviewInput/ReviewInput.cpp:63` `capture()` 兜底：grab 结果大于窗口逻辑尺寸
     （按 dpr）时裁掉未用缓冲，防止同类陈旧缓冲再次入库。
- 验证（light，应用自捕获，AppTheme light）：
  - `FIX02b-760-month-light.png` = **760×540**，首行非黑 y=0、末行 y=539，**无黑边**；
    工具栏（红绿灯/加号/日周月年/搜索/更多）、侧栏、月头、5 行网格（28–1 到 26–1）完整。
  - 回归 `FIX02-wide-1100-month-light.png` = **1100×692**，y=0–691 全幅无黑边，宽窗采集未受影响。
- 附带发现：本轮后续 `date 2026-03` 命令未切换月头（仍 2026年10月），未在本轮追查，
  与 FIX-02 无关，列入仍差。

## 已改
- `tmp/ui-acceptance/calendar/harness/Main.qml` — resize 用 min==max 强制合成器尺寸。
- `tmp/ui-acceptance/calendar/harness/ReviewInput/ReviewInput.cpp` — capture 按窗口逻辑尺寸兜底裁剪。

## 仍差
1. 玻璃合成帧缺失（FIX-03）：自捕获看不到真实合成器 backdrop，需合成器截图验证玻璃。
2. 动效未验证（无连续帧，不声称通过）。
3. 4 周月份（2027-02）未实拍。
4. `date` 命令在 resize 后未切换月份（2026-03 未生效），原因未查。

## 外推待确认
- 月视图按实际周数分行（4/5/6）无参考图，按 Apple Calendar 行为外推。
- 窄窗 min==max 仅用于 review harness，不进产品代码。

## Next round
FIX-03 玻璃合成帧：用合成器截图（grim/spectacle）在 760×540 验证侧栏/工具栏玻璃的真实合成。
