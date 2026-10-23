# R303 — FIX-03 玻璃合成：纯窗内材质，合成器采集受阻

## 本轮
- FIX-03 结论修正：玻璃不依赖合成器 backdrop。`shared/qml/controls/LiquidBackdrop.qml:52-67`
  用 `ShaderEffectSource` 采样**同一窗口内**的 backdrop item，再由 `MultiEffect`
  （`:43-50`）模糊；`LiquidSurface.qml` 与 `apps/calendar` 全树 grep
  `KWindowEffects|enableBlur|blurBehind` 零命中，没有走 KWin 窗后模糊。
  因此 `grabWindow()` 自捕获就是玻璃的真实合成结果；合成器截图只会额外带上窗口圆角/
  外阴影与桌面壁纸，不会改变玻璃材质本身。
- 合成器采集仍试了一次作对照（均失败，已停止重试）：
  - KWin `ScreenShot2.CaptureScreen("Virtual-1")` → `ScreenShot2.Error.NoAuthorized`。
  - `spectacle -f -b`（走 xdg-desktop-portal）落盘 1280×800 **纯白**；
    portal 非交互 Screenshot 请求 10s 无 Response（授权弹窗无人可点）。
  → 无人值守拿不到合成帧，属环境/授权限制。
- 视觉对照（760×540 自捕获 light，`FIX02b-760-month-light.png`，工具栏 3x、侧栏 2x
  放大后与 `.loop/refs/macos-calendar.png` 逐区比对）：
  - 工具栏：浮动玻璃舱，圆角/1px 内描边/轻微提亮与参考浮动岛一致；日周月年选中
    “月”为抬升胶囊，对应参考 Day/Week/Month/Year 选中态；红绿灯在右（KDE CSD）
    与参考在左属平台差异。
  - 侧栏：浅色玻璃列、分组标题、方形勾选框、迷你月历 7 列节奏与参考一致。
  - 工具栏舱与侧栏顶角重叠，但二者采样同一张窗内 backdrop 纹理（单次模糊），
    不构成玻璃叠玻璃；舱体仍读作浮层岛，符合参考。
- 结论：玻璃材质本身已用自捕获验证；合成器级帧（窗口边缘/外阴影/桌面 backdrop）
  在本环境无法实拍，列入「需要你」。

## 已改
- 无产品代码改动（验证轮）。临时诊断脚本只落在 /tmp，未入库。

## 仍差
1. 合成器级玻璃帧（窗口圆角/外阴影/桌面 backdrop）无法实拍：portal 授权无人值守。
2. 动效未验证（无连续帧，不声称通过）。
3. 4 周月份（2027-02）未实拍。
4. `date` 命令在 resize 后未切换月份（2026-03 未生效），原因未查。

## 外推待确认
- 月视图按实际周数分行（4/5/6）无参考图，按 Apple Calendar 行为外推。
- 窄窗 min==max 仅用于 review harness，不进产品代码。
- 工具栏左侧“侧栏切换 + 加号”同处一舱、参考为两枚独立岛；沿用已接受布局，本轮未重开。

## 需要你
a) 若要合成器级玻璃帧，需人工在 portal 截屏授权弹窗点一次“允许”（本环境无人值守）。

## Next round
4 周月份（2027-02）实拍：切到 2027-02，核对行数 = 4、行高等分（FIX-01 回归）；
若 `date` 命令仍不生效，先修该命令再拍。
