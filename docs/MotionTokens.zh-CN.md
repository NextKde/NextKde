# Shell 动效 Token 统一方案（T5）

状态：**方案待确认，尚未替换代码**。本文件单独提交；按任务卡“等确认后再批量替换”的要求，确认前不执行后续实现批次。

统计基线：`6df77a57`，2026-11-11。目标是统一普通界面过渡的节奏，不重设计动画，不调整弹簧参数。下文“替换后”均为方案或待验收项，不代表已经实现。

## 1. 复核结果与统计口径

`AppearanceTokens.qml:561` 的位置正确，但“只覆盖组件 spring，其余界面完全没接入”与代码不符。现有 `motion` 已包含：

| 现有字段 | windows12 | Material | macOS |
| --- | ---: | ---: | ---: |
| `fastDuration` | 120 | 100 | 135 |
| `normalDuration` | 180 | 220 | 200 |
| `slowDuration` | 260 | 300 | 360 |
| `standardEasing` | OutCubic | OutQuart | OutCubic |
| `popupOpenDuration` / `popupCloseDuration` | 150 / 140 | 150 / 140 | 150 / 140 |

`PageMotion`、`PopupMotion`、Dock、控制中心、快速搜索、输入法及桌面中心已有消费者。共享层另有 `AppTheme.motionFast = 120`、`motionNormal = 220`（减少动态效果时为 0），部分 Liquid 控件注释还记录着 `100/150/220/320/400` 五档。这几套规则需要一起收敛，不能只新增一套数字。

使用 Git 跟踪的 QML 文件统计，避免把 `shell/Kos/Ui` 指向共享源码的符号链接重复计入：

| 范围 / 计数 | 本次实测 | 任务卡 | 说明 |
| --- | ---: | ---: | --- |
| `shell/ + shared/` 的 `duration:` 行 | 392 | 391 | 多 1；并非全是硬编码 |
| 同范围 `easing.` 或 `Easing.` 命中行 | 288 | 287 | 多 1；一行可能含多个枚举 |
| 同范围数字开头的 `duration:` | 250 | 未区分 | 对应验收 grep 的主要口径 |
| 同范围纯数字 RHS | 248 | 未区分 | 包含 `property int duration: 240` 默认值 |
| 同范围数字开头的算式 | 2 | 未区分 | `2200 + index * 180`、`1840 + index * 180` |
| 同范围其他 RHS | 142 | 未区分 | 包含条件、token 引用、多行绑定，不等于 142 个硬编码 |
| 全仓 `duration:` 行（含 apps/tests） | 429 | 称为“全仓 391” | 原统计范围实际更接近 shell/shared |
| 全仓数字开头的 `duration:` | 287 | 未区分 | apps/tests 不属于本次批量替换范围 |
| 全仓 easing 相关行 | 310 | 未区分 | 同上 |

任务卡列出的十二个高频值，在 `shell/ + shared/` 下全部复现：100×36、150×30、140×29、120×27、160×24、110×18、180×11、200×9、90×5、170×5、130×5、240×4。不能据此把 392 个绑定都判为裸数字。

### 模块 × 时长分布

下表覆盖全部 392 个 `duration:` 绑定；“数字”计数字开头的 RHS，“其他”包括条件表达式和引用。“easing 行”按行计数。时长单位均为 ms，`值×次数` 只表示 RHS 开头数字，不代表算式最终时长。

| 模块（路径） | duration 总数 | 数字 | 其他 | easing 行 | 数字分布 |
| --- | ---: | ---: | ---: | ---: | --- |
| `shared/demo-ui/controls` | 52 | 14 | 38 | 25 | 50×2、60×1、70×1、85×1、100×2、120×2、150×2、155×1、200×1、300×1 |
| `shared/demo-ui/foundation` | 2 | 0 | 2 | 2 | — |
| `shared/qml/colorize` | 2 | 0 | 2 | 2 | — |
| `shared/qml/controls` | 50 | 33 | 17 | 37 | 100×21、150×10、200×2 |
| `shared/qml/foundation` | 26 | 1 | 25 | 15 | 240×1 |
| `shell/desktop/modules/applauncher` | 33 | 31 | 2 | 38 | 110×2、120×6、130×1、140×6、160×5、180×5、220×2、300×1、450×2、650×1 |
| `shell/desktop/modules/bar` | 65 | 51 | 14 | 36 | 100×3、110×13、140×14、150×4、160×2、170×4、180×2、200×1、220×1、240×2、250×1、300×1、360×1、900×2 |
| `shell/desktop/modules/common` | 10 | 9 | 1 | 11 | 90×1、100×1、120×2、140×1、150×1、180×1、420×1、1100×1 |
| `shell/desktop/modules/deskcenter` | 28 | 23 | 5 | 23 | 90×3、110×3、120×4、130×3、140×2、150×2、170×1、240×1、360×1、380×1、1840×1、2200×1 |
| `shell/desktop/modules/dock` | 54 | 37 | 17 | 46 | 100×5、105×1、115×4、120×9、140×3、160×5、180×1、210×3、220×1、260×1、650×1、800×1、900×1、1200×1 |
| `shell/desktop/modules/inputmethod` | 11 | 10 | 1 | 5 | 90×1、100×1、150×4、160×4 |
| `shell/desktop/modules/notifications` | 8 | 5 | 3 | 8 | 200×5 |
| `shell/desktop/modules/overview` | 7 | 7 | 0 | 2 | 120×2、140×2、150×1、160×2 |
| `shell/desktop/modules/quicksearch` | 5 | 4 | 1 | 2 | 100×2、150×2 |
| `shell/desktop/modules/stage` | 15 | 7 | 8 | 12 | 120×2、130×1、150×2、160×1、260×1 |
| `shell/desktop/modules/wallpaper` | 24 | 18 | 6 | 24 | 55×2、65×1、75×1、100×1、140×1、150×2、160×5、180×2、250×1、280×1、500×1 |
| **合计** | **392** | **250** | **142** | **288** | **40 种 RHS 开头数值** |

其余 142 个 RHS 的首行中，58 个仍含数字，84 个不含数字（后者可能是多行表达式，仍需追踪定义）。例如 `reduceMotion ? 0 : 150`、`_pressed ? 100 : 200`、`index * 620` 都不能漏掉。以下入口也不被验收 grep 覆盖：

- `LauncherIconMotion.qml:43/46`：JS 赋值中的 300ms 姿态、200ms 淡入淡出，按剩余进度缩放。
- `LauncherMotion.qml:29/38`：函数实参中的 100ms 打开背景、200ms 关闭背景。
- `DockAnimation.qml`：70ms 悬停、45ms 按下反馈、320ms 音乐展开、自动隐藏及预览参数。
- `SelectionHighlight.qml:14/15`：140ms 淡入淡出、80ms 按下反馈默认值。
- `StageConfigService.qml`：持久化用户配置、schema 默认值与 KWin 投影；不能直接改用户保存值。
- `ArtworkColorSource.qml:22` 的 760ms 配色插值、`LiquidGlassSurface.qml:95` 的 2600ms 环境过渡。

### 曲线分布

以下计枚举出现次数，不与 easing 命中行混用：

| 枚举 | 次数 | 处理方向 |
| --- | ---: | --- |
| OutCubic | 182 | 普通进入/交互 settle 的主族 |
| InCubic | 15 | 普通退出主族；核对是否误用于进入，不能直接反向 |
| OutQuad / InOutQuad | 14 / 11 | 先区分普通反馈与 wobble 分段 |
| OutQuint | 10 | 普通过渡可归并，液态释放物理表现先保留 |
| InOutCubic | 10 | 双向位置/尺寸插值 |
| InOutSine | 10 | 区分循环/环境动画与普通过渡 |
| OutBack / OutBounce | 7 / 1 | 现有回弹表现，登记例外 |
| Linear | 7 | 旋转、进度和业务停留，保留线性 |
| Bezier | 2 | 启动台清除按钮同一组回弹，保留控制点 |
| OutQuart | 1 | 现有 Material 主族定义 |
| OutSine / InSine | 1 / 1 | 音乐音符循环，保留 |

## 2. 推荐的五档阶梯

采用 **100 / 120 / 160 / 220 / 300ms**。任务卡中的 90/120/160/220/280 是示例；这里保留高频 100ms 反馈和现有 300ms 启动台主运动，减少不必要的视觉变化。`instant` 是短反馈，不是零时长；零时长只表示已有的立即完成/减少动态效果语义。

| token | macOS duration | Material duration | windows12 duration | macOS / windows12 enter → exit | Material enter → exit | 新动画选用场景 |
| --- | ---: | ---: | ---: | --- | --- | --- |
| `instant` | 100 | 100 | 100 | OutCubic → InCubic | OutQuart → InQuart | 按下反馈、轻量高亮、小图标反馈 |
| `fast` | 120 | 120 | 120 | OutCubic → InCubic | OutQuart → InQuart | hover/focus、短距离交互反馈 |
| `base` | 160 | 160 | 160 | OutCubic → InCubic | OutQuart → InQuart | 菜单/弹窗、常规局部状态切换 |
| `slow` | 220 | 220 | 220 | OutCubic → InCubic | OutQuart → InQuart | 通知滑入滑出、布局/歌词切换、普通页面内容进入 |
| `page` | 300 | 300 | 300 | OutCubic → InCubic | OutQuart → InQuart | 大范围页面/启动台运动、较大容器展开 |

本轮三种风格共用时长阶梯，不额外发明 Material 时长差异；保留 `isMaterial` 策略输入及 Material 的 Quart 曲线分支。macOS/windows12 使用 Cubic 家族。`springEnabled`、组件 move/resize 的全部 spring/damping/mass/epsilon 值保持原样。

每档暴露 `duration`、`enterCurve`、`exitCurve`；另由同一策略提供 `settleCurve`（Cubic / Material Quart 的 InOut），用于一直留在屏幕上的双向位置/尺寸插值。纯交互反馈通常用 `enterCurve`，即使鼠标正在离开控件也不等于元素正在退场。不得把所有 `Behavior` 的反向变化都改成加速退出。

新增动画的决策顺序：

1. 判断是不是普通 UI 过渡。循环、物理跟手、用户可配置动画、与媒体/业务计时同步的动画不套五档。
2. 按上表的交互范围选档。不得按控件身份另设 `button123ms` 一类数字 token。
3. 入场用 `enterCurve`，真正退场用 `exitCurve`，常驻元素双向布局用 `settleCurve`。同一视觉动作的 opacity/scale/translation 用同一档。
4. 遵守已有 reduce-motion 与立即完成路径；不要把 0 改成 `instant`。
5. 中途反向从当前进度续接，用“完整 token 时长 × 剩余进度”。最低 1ms 等计算保护不是第六档。

预期 Shell 调用接口（示意，尚未实现）：

```qml
NumberAnimation {
    duration: AppearanceTokens.motion.base.duration
    easing.type: AppearanceTokens.motion.base.enterCurve
}
```

## 3. 依赖方向与 token 所有权

不能让 `shared/qml/controls` 导入 `qs.desktop.modules.common`。独立 Settings 使用编译后的 `Kos.Ui`，Shell 使用源码目录导入；两条路径必须共享一份数字定义。

推荐新增可实例化的 `shared/qml/foundation/MotionTokens.qml`（纯 QtQuick QtObject，接收 `isMaterial`），在其中定义五档及曲线。`AppearanceTokens.motion` 使用这个类型并传入 `tokens.isMaterial`，在该实例保留 Shell 专用 popup 几何及现有 spring 属性。这满足 `AppearanceTokens.motion.instant/fast/base/slow/page` 的公开入口，不复制五档字面量。

`AppTheme` 使用同一类型实例；共享 Liquid 控件通过显式 `motionPolicy` 输入读取，默认使用 AppTheme 的策略。Shell 宿主需把 `AppearanceTokens.motion` 传给所使用的控件，避免控件与宿主使用不同风格。AppTheme 现有应用外观偏好与 Shell 样式不同步，本任务不新增跨进程外观同步，也不把 `modernDesign` 擅自解释为 Material。

实现时同步更新 `shared/qml/foundation/qmldir`、`shared/qml/CMakeLists.txt`、`shell/Kos/Ui/qmldir` 等真实加载入口，验证目录导入和编译模块，不能只靠编辑器解析。此类型不应新增对 ColorScheme、Quickshell 或平台 daemon 的依赖。

旧字段迁移按语义逐处处理：

| 旧入口 | 迁移方式 |
| --- | --- |
| `AppearanceTokens.motion.fastDuration` | 先审查消费者，普通短反馈转 `fast.duration`；高频物理反馈走例外 |
| `normalDuration` | 普通内容进入优先 `slow.duration`，不能默认压到 160ms |
| `slowDuration` | 无消费者时移除；有消费者按动作核对，不能偷偷将 360ms 减到 300ms |
| `standardEasing` | 指向当前风格的进入曲线；逐处核对是否需要 settle/exit |
| `popupOpenDuration` / `popupCloseDuration` | 普通 popup 收敛至 `base.duration`；保存进度续接、关闭完成后 unmap 的逻辑 |
| `AppTheme.motionFast` / `motionNormal` | 可保留兼容别名，分别读 `fast` / `slow`，保留 `reduceMotion ? 0 : ...` |
| `DockAnimation` 的普通 UI 常量 | 按语义引用统一 token；物理参数/业务延迟留在 Dock 所有者 |

兼容别名不能继续存第二套时长。跨样式变化在实现批次中列出原值→新值，逐批验证，不借“重构”掩盖原本 100/135/180ms 的改变。

## 4. 迁移规则与行为保留

### 替换前 vs 替换后：数字绑定的初步分桶

这是对 250 个数字开头绑定的**算术候选分布**，用于评估改动量，不是逐处语义审查后的最终结果；wobble 等处于中间区间的例外会从候选桶移出。实现完成后必须另记真实 token 引用数和例外数，不能把此表当验收结果。

| 替换前值×次数 | 候选数 | 拟采用的 token / 时长 | 当前替换后实测 |
| --- | ---: | --- | --- |
| 90×5、100×36、105×1 | 42 | `instant` / 100 | 未实施 |
| 110×18、115×4、120×27、130×5 | 54 | `fast` / 120 | 未实施 |
| 140×29、150×30、155×1、160×24、170×5、180×11 | 100 | `base` / 160 | 未实施 |
| 200×9、210×3、220×4、240×4、250×2 | 22 | `slow` / 220 | 未实施 |
| 260×2、280×1、300×3 | 6 | `page` / 300 | 未实施 |
| 50×2、55×2、60×1、65×1、70×1、75×1、85×1 | 9 | 必须审查：分段/跟手等，不直接拉长到 100 | 未实施 |
| 360×2、380×1、420×1、450×2、500×1、650×2、800×1、900×3、1100×1、1200×1、1840×1、2200×1 | 17 | 必须审查：长过渡、循环、等待、业务进度 | 未实施 |
| **合计** | **250** | **224 个普通区间候选 + 26 个区间外必审项** | **未实施** |

142 个其他绑定及 JS 赋值、函数参数、属性默认值另行追踪，不计入上述 250 的分桶。范围内所有现存短时长来源都必须有明确归属。

迁移约束：

- 240→220（-8.3%），绝不机械归到 160（-33.3%）。260→300（+15.4%）、180→160（-11.1%）等需要结合位移与录屏判定；不能仅凭百分比宣称视觉等价。
- 先沿同一交互的状态机、并行/串行组、Timer、unmap/销毁时机追踪依赖，再替换。不能让动画仍在跑时容器已经销毁。
- `PopupMotion`、`KosPageMotion`、`LauncherIconMotion` 的剩余进度比例、反向续接、完成回调全部保留；不改 from/to、scale、offset、distance、spring 或 overshoot。
- 通知现有进入使用 InCubic，属于曲线语义冲突。首批保持其时间曲线语义并标注兼容例外，不趁统一切换到 OutCubic；该变化需要另行视觉设计决定。新普通通知动画遵守进入/退出接口。
- Liquid 控件的 squash/stretch 是串行物理表现：不能把四段各自“就近取整”而改变总周期，也不能改 OutBack/OutQuint/Quad 的组合以换取曲线计数清零。
- 所有例外保留现场数值和解释，不把数值搬到新属性以逃避 grep。已存在有意义的业务/物理配置继续留在原所有者，并在使用处注明关系。

### 已识别的例外及长过渡保留项

| 文件 / 动作 | 保留内容 | 为什么不能强套五档 |
| --- | --- | --- |
| `AppearanceTokens.qml` widget move/resize、`DockAnimation.qml` 物理悬停 | 全部物理参数、70/45ms 跟手反馈、帧同步响应 | 改动会改变跟手/弹簧行为；Dock 主悬停不是一个普通 160ms tween |
| `LiquidGlassButton.qml`、`LiquidGlassSwitch.qml`、`LiquidSlider.qml` 及 demo 对应项 | wobble 分段、OutBack/OutQuint 等物理释放表现 | 时间比例与振幅/曲线共同构成原动画；本轮不重设计 |
| `AppLauncherWindow.qml` 文件夹合并进度 | 650ms + Linear | 与 folderMergeTimer 的停留判定同步 |
| `DeskCenterWindow.qml` 文件夹放入进度 | 380ms + Linear | 完成时才授权文件放入操作，时长属于手势阈值 |
| `AppLauncherWindow.qml` 清除搜索按钮 | 450ms Bezier ×2，原控制点 | scale/rotation 同步回弹，压到 300 会改变表现 |
| `DockMusicPlayer.qml` 跑马灯/歌词停顿 | 1200/800/900/650ms 及距离计算、暂停 | 阅读停留与滚动速度，不是 UI 进入退出 |
| `WifiCard.qml`、`BluetoothCard.qml`、`WavyProgress.qml` | 900/1100ms 周期与原曲线 | 等待/加载循环 |
| `DeskCenterWindow.qml` 音符 | 2200/1840 + index×180、360ms 段与错峰 | 同一循环的行程与透明度必须同步 |
| `LiquidGlassSurface.qml` | 420ms 光照过渡、2600ms 环境变化 | 表面连续光照表现，不随 popup 时长压缩 |
| `DepthWallpaperLayer.qml`、`ArtworkColorSource.qml` | 500ms 壁纸显现、760ms 配色插值 | 大面积环境过渡，本轮保留避免闪变 |
| `NotificationHistoryPane.qml` 空状态玻璃 | 360ms InOutSine | 暂保留既有大表面交叉过渡，不能机械压成 160ms |
| `StageConfigService.qml` 及消费者 | 持久化用户时长、KWin 同步参数 | 用户配置属于功能契约，不用 token 覆写用户值 |
| `KosKineticScroll.qml` 等物理滚动 | 速度/距离计算出的时长 | 保留物理模型；不按五档量化 |
| 已有即时完成与最小时长保护 | 0、`Math.max(1, ...)` 等 | 关闭动效/数值保护，不是普通节奏档 |

以上是已核实的迁移边界，不是给任意裸数字加免责注释的模板。实施时每个留下的数字都需在附近说明具体业务/物理原因，并登记到最终例外表（文件、行、值、原因）；未说明的数字目标为 0。

## 5. 分批提交计划

本方案提交之外，每批独立 commit。正文必须列出实际文件和旧值→token 映射；不能只写“统一动画”。

1. **共享策略 + Liquid 控件**：新增纯 QtQuick 策略及模块注册、接入 AppearanceTokens/AppTheme；先迁移 `shared/qml/controls/Liquid*` 的普通 UI 动画及必要的 Shell 策略传入。同步更新直接受影响的契约断言，保留物理例外。普通 100→instant、120→fast、150→base、200/220→slow；400ms 释放先保留。
2. **Shell common + bar**：PopupMotion、PageMotion、AnimatedPopupWindow、控制中心、通知历史及顶部栏普通交互。弹窗 150/140→base，110/120/130→fast，普通 140/150/160/170/180→base，200/240→slow。
3. **Shell applauncher + dock**：启动台 JS 实参/赋值一起迁移，300→page、200→slow、100→instant；Dock 普通 resize/fade/预览按语义接入。保留物理悬停、folder dwell、跑马灯、动画完成同步。
4. **Shell 其余模块**：deskcenter、notifications、inputmethod、overview、quicksearch、stage、wallpaper。普通 240→slow；用户配置、长环境过渡、循环、通知进入曲线列为有理由的例外。
5. **共享剩余入口与收尾**：foundation（含 Settings 页切换）、SelectionHighlight、demo-ui、colorize。demo 在 `shared/` 的验收范围内，不能跳过。清理旧五档注释和失去消费者的兼容字段，补实测分布与例外清单。

`apps/lockscreen`、`apps/sddm` 和 `tests/` 的动画夹具不做全仓数字清洗；Settings 因消费共享 foundation 需要回归验证。测试仅将受影响的具体时长/曲线断言改为正确 token 及行为契约，不删除、不放宽断言，不改变其他期望值。

## 6. 验证与验收记录

### 已执行：方案阶段基线

真实命令与输出：

```text
$ node shared/qml/test_visual_contract.mjs
KOS UI visual contract: all checks passed

$ node tools/ci/qmllint-changed.mjs --all
qmllint 1.0
apps/lockscreen/contents/lockscreen/LockAvatar.qml:
qmllint: Unknown options: ignore-settings, max-warnings, 1.
[同类错误重复，命令退出码 1]

$ QMLLINT=/usr/lib/qt6/bin/qmllint node tools/ci/qmllint-changed.mjs --all
qmllint 6.12.0
QML syntax: 395 files, OK
```

默认 PATH 下的 qmllint 不兼容仓库脚本，显式选 Qt 6 后语法基线通过。该脚本有意关闭普通类型/import 警告，只检查语法；**不能据此声称完整 qmllint 零警告**。实施时需对受影响文件在生成 qmltypes 和正确 import path 下做完整 lint，并检查实际运行日志。

工具探测找到 `/usr/bin/qs`、`/usr/bin/quickshell`、Qt 6 qmllint 和 ffmpeg，未找到 `weston` 或 `wf-recorder`。本阶段不安装工具、不启动真实桌面、不修改动画；未执行 headless 启动或五组交互录屏。

### 确认后逐批验证

- 每批执行 `node shared/qml/test_visual_contract.mjs`。当前文件第 323 行直接断言 popup 150/140，第 327 行断言 Cubic；接入 token 时同步改为验证 token 路径及方向语义，不能删除检查。
- 使用 Qt 6 跑受影响文件的语法检查与完整 lint；编译模块接入需增量构建 Settings/Kos.Ui 并做加载验证。检查目录导入、编译资源及安装路径，不仅源码路径。
- 先准备隔离的 runtime、config、state 和日志目录，在可用的 headless Weston 中运行：

  ```sh
  QT_FORCE_STDERR_LOGGING=1 node tests/shell-startup/run.mjs /usr/bin/qs /path/to/weston
  ```

  现有脚本以 `qs -p <本工作树>/shell` 启动、等待 Configuration Loaded 并存活 4 秒；它**不会逐页点击，也不会录屏**。另行通过实际 IPC/输入驱动交互并保存日志、录屏。新配置端点必须重启测试实例；不向正在运行的个人桌面发送操作。
- 开启 `QT_FORCE_STDERR_LOGGING=1` 检查 QML warning/error、绑定循环、缺少属性和 import；空 stderr 不能代替加载成功。
- 不自动修改 `tests/` 中的其他断言。现有动效行为测试检查反向续接、reduce-motion、完成后 unmap、页面交接和快速切换，必要时加有意义的契约覆盖。

五组前后录屏使用相同分辨率、缩放、帧率、主题和输入序列，在实现前保存基线，实施后重播：

| 交互 | 必须覆盖 | 观察重点 |
| --- | --- | --- |
| 控制中心开/关 | 完整开关、打开中反向关闭、子页返回 | opacity/scale/位移同步；关闭后再 unmap |
| 启动台开/关 | 背景+图标、连续反向、文件夹进出 | 300ms 姿态与淡出配合；图标未完成不能拆内容 |
| Dock 悬停 | 跨图标扫过、移出、预览交接 | 保留跟手与落点；普通提示的关闭不能抢先 |
| Settings 页切换 | 冷页、缓存页、快速连续切换、reduce-motion | 进出时序、无空白帧、旧页释放正确 |
| 通知滑出 | 单条退出、堆叠重排、历史交接 | 动画结束后删除，输入区域与可见区域一致 |

至少分别覆盖 macOS、Material，并补 windows12 分支加载与交互检查。headless 软件渲染能检查时序和状态，不证明 KWin 原生玻璃光学效果；若发现只有 KWin 下可复现的几何/可见性问题，先记录为何必须真实合成器，再补专项验证。本任务不预设需要 VM。

### 最终验收表（实施后填写）

| 指标 | 替换前实测 | 替换后实测 |
| --- | ---: | --- |
| 数字开头 duration 行 | 250 | 待实施 |
| 未说明原因的数字 duration | 尚未逐处完成注释审计 | 目标 0 |
| instant / fast / base / slow / page 引用数 | 新接口尚不存在 | 待实施，按直接引用与兼容别名分别计 |
| 条件表达式/JS 赋值隐藏时长 | 已识别，见第 1 节 | 逐项归属 token 或有理由的例外 |
| 保留例外数 | 待逐处确认 | 必须逐文件列明，不只报总数 |
| 五组交互录屏 | 尚未录制 | 基线/改后文件及结果待填 |
| 视觉契约 | 通过 | 各批次待填 |
| Qt 6 语法检查 | 395 files, OK | 各批次待填 |
| 完整 lint / headless / Settings 加载 | 未执行 | 待填真实结果与日志 |

验收 grep 的剩余行可以非零，但每行必须有具体注释及例外记录。不能把 duration 改成一个新变量，再在变量里硬编码同样数字。五档定义本身可在唯一策略源中包含数字，它们是明确设计定义，不是消费者逃逸。

## 7. 复现统计

在仓库根目录运行以下只读命令；不跟随共享源码符号链接，不计未跟踪构建产物：

```sh
python3 - <<'PY'
import collections
import pathlib
import re
import subprocess

files = subprocess.check_output(
    ['git', 'ls-files', '-z', '--', '*.qml']
).decode().split('\0')
for scope, prefixes in [('shell/shared', ('shell/', 'shared/')),
                        ('repository', ('',))]:
    totals = collections.Counter()
    modules = collections.defaultdict(collections.Counter)
    values = collections.defaultdict(collections.Counter)
    for name in filter(None, files):
        if not name.startswith(prefixes):
            continue
        path = pathlib.Path(name)
        if path.is_symlink():
            continue
        module = '/'.join(name.split('/')[:4]) if name.startswith(
            'shell/desktop/modules/') else str(path.parent)
        for line in path.read_text().splitlines():
            if re.search(r'\bduration\s*:', line):
                totals['duration_lines'] += 1
                modules[module]['duration'] += 1
            if re.search(r'easing\.|Easing\.', line):
                totals['easing_lines'] += 1
                modules[module]['easing'] += 1
            match = re.search(r'\bduration\s*:\s*(\d+)\b', line)
            if match:
                totals['numeric_start_lines'] += 1
                modules[module]['numeric'] += 1
                values[module][int(match[1])] += 1
    print(scope, dict(totals))
    if scope == 'shell/shared':
        for module in sorted(modules):
            print(module, dict(modules[module]), dict(sorted(values[module].items())))
PY
```

预期汇总：

```text
shell/shared {'duration_lines': 392, 'easing_lines': 288, 'numeric_start_lines': 250}
repository {'duration_lines': 429, 'numeric_start_lines': 287, 'easing_lines': 310}
```

字典输出顺序可能随文件遍历顺序变化；数值应一致。本统计是文本基线，后续必须附语义审查，不能用文本计数代替行为验收。
