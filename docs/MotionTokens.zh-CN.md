# Shell 动效 Token 统一方案（T5）

状态：**方案已获人工确认，代码批次已落地；视觉验收尚未完成**（2026-11-12）。原始审计与方案保留如下，实测结果、例外登记及未通过项目见第 8 节。

统计基线：`6df77a57`，2026-11-11。目标是统一普通界面过渡的节奏，不重设计动画，不调整弹簧参数。第 1–7 节保留方案基线与约束；第 8 节记录最终实现和实际验收。

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

Shell 调用接口（现已实现）：

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
| 90×5、100×36、105×1 | 42 | `instant` / 100 | 见第 8 节语义审计结果 |
| 110×18、115×4、120×27、130×5 | 54 | `fast` / 120 | 见第 8 节语义审计结果 |
| 140×29、150×30、155×1、160×24、170×5、180×11 | 100 | `base` / 160 | 见第 8 节语义审计结果 |
| 200×9、210×3、220×4、240×4、250×2 | 22 | `slow` / 220 | 见第 8 节语义审计结果 |
| 260×2、280×1、300×3 | 6 | `page` / 300 | 见第 8 节语义审计结果 |
| 50×2、55×2、60×1、65×1、70×1、75×1、85×1 | 9 | 必须审查：分段/跟手等，不直接拉长到 100 | 见第 8 节语义审计结果 |
| 360×2、380×1、420×1、450×2、500×1、650×2、800×1、900×3、1100×1、1200×1、1840×1、2200×1 | 17 | 必须审查：长过渡、循环、等待、业务进度 | 见第 8 节语义审计结果 |
| **合计** | **250** | **224 个普通区间候选 + 26 个区间外必审项** | **见第 8 节** |

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

### 最终验收概览

| 指标 | 替换前实测 | 替换后实测 |
| --- | --- | --- |
| 数字开头 duration 行 | 250 | 99（含 5 行唯一档位定义） |
| 普通时序归并 | 多套硬编码 | 五档与兼容别名；物理/环境/业务保留 |
| instant / fast / base / slow / page 直接引用 | 新接口不存在 | 34 / 55 / 87 / 27 / 9，包含定义默认值和别名 |
| 条件表达式/JS 赋值 | 需额外追踪 | 剩余进度计算与例外见第 8 节 |
| 保留例外 | 待逐处确认 | 文件、行号、表达式及原因见第 8 节 |
| 五组前后录屏 | 尚未录制 | 待真机验证 |
| 视觉契约 | 通过 | 通过 |
| Qt 6 语法检查 | 395 files, OK | 476 files, OK |
| 完整 lint / runtime / Settings | 未执行 | 第 8 节列明通过范围与限制 |

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

基线 `6df77a57` 的预期汇总：

```text
shell/shared {'duration_lines': 392, 'easing_lines': 288, 'numeric_start_lines': 250}
repository {'duration_lines': 429, 'numeric_start_lines': 287, 'easing_lines': 310}
```

字典输出顺序可能随文件遍历顺序变化。本段保留原始基线，当前分支输出见第 8 节；不能用文本计数代替行为验收。

## 8. 实施结果（2026-11-12）

### 合入 main 的补充（2026-11-13）

合并保留 main 的共享 `MotionSpring` / `SpringMotion`、启动显现与桌面组件帧同步弹簧；Popup、开关、分段控件和滑块的几何运动继续使用弹簧，颜色及透明度的普通过渡接入五档策略。滑块拖动直达、提交回执期间禁止补间及 reduce-motion 路径保留。下方开关/滑块/分段控件的旧 wobble 分段记录属于合并前历史，不再描述当前几何运动。

`ContextMenu` 保留快速交互例外：`springResponse: 0.08`，打开/关闭淡入淡出为 45/35ms，均使用 OutCubic；菜单内 `PageMotion` 退出/进入为 20/30ms，不套五档。下方旧 60/80ms 菜单例外记录由此取代。本次集成只进行源码审查与 Git 差异检查，未运行测试、构建或图形会话；人工可检查菜单快速反向开关、滑块拖动/提交、开关连续切换和减少动态效果。

### 策略与使用方法

唯一数字定义位于 `shared/qml/foundation/MotionTokens.qml`。`AppearanceTokens.motion` 继承该类型并保留 Shell 的 spring、popup 几何与兼容别名。`Kos.Ui`、`Kos.Demo` 均注册此类型；Demo 的源码入口使用符号链接复用定义，构建时进入自己的 QML 资源路径。共享控件不反向导入 Shell。Liquid 控件按自身 `materialForm` 选择策略，并允许宿主显式传入 `motionPolicy`；通用 foundation 默认 macOS 曲线，不能把 `modernDesign` 当成 Material。

| 档位 | ms | 选择依据 |
| --- | ---: | --- |
| instant | 100 | 小面积、近乎立即的反馈 |
| fast | 120 | hover、颜色、轻量显隐 |
| base | 160 | 普通弹窗与状态切换 |
| slow | 220 | 大面积显隐、通知、较长控件运动 |
| page | 300 | 页面/启动台姿态、大跨度展示 |

进入/普通反馈使用 `enterCurve`，离场使用 `exitCurve`，双向平稳重排使用 `settleCurve`。macOS/windows12 为 OutCubic/InCubic/InOutCubic；Material 为 OutQuart/InQuart/InOutQuart。`0` 的减少动画/立即完成语义、剩余进度乘法和 `Math.max(1, ...)` 保留。物理运动、循环周期和业务定时不按档位强制映射。

兼容别名：Shell fastDuration→fast、normalDuration→slow、slowDuration→page、standardEasing→enterCurve、popupOpen/CloseDuration→base；AppTheme.motionFast/Normal→fast/slow，仍响应 reduceMotion。无 spring/damping/mass/epsilon 参数改动，无布局、颜色值或动画层级改动。

### 替换前后分布

统计范围为 Git 跟踪的 shell/shared QML，跳过符号链接及构建产物。新增 5 行是唯一策略中的档位定义。

| 指标 | 基线 | 当前 |
| --- | ---: | ---: |
| duration 行 | 392 | 397 |
| 数字开头 duration 行 | 250 | 99 |
| easing 相关行 | 288 | 378 |

数字开头绑定减少 151 行；剩余 99 行中 5 行是档位定义，94 行为下表登记的物理/循环/业务例外。这不等于全部 392 行都曾硬编码。新增显式 easing 使 easing 行数增加，不能把净行数差当作替换量。

直接 `.duration` 引用：instant=34、fast=55、base=87、slow=27、page=9。兼容别名消费者继续通过原有 API 读策略。

下表按 diff 中发生变化的原始绑定行计数（包括 `*Duration` 属性和 JS 赋值；同一行 duration/easing 可各计一次；新增显式 easing 不算“替换旧 easing”）。

| 模块 | 时序绑定变更行 | 旧 easing 变更行 |
| --- | ---: | ---: |
| `shared/demo-ui/controls` | 34 | 9 |
| `shared/demo-ui/foundation` | 0 | 2 |
| `shared/qml/controls` | 30 | 14 |
| `shared/qml/foundation` | 9 | 13 |
| `shell/desktop/modules/applauncher` | 17 | 15 |
| `shell/desktop/modules/bar` | 55 | 30 |
| `shell/desktop/modules/common` | 16 | 8 |
| `shell/desktop/modules/deskcenter` | 19 | 16 |
| `shell/desktop/modules/dock` | 26 | 18 |
| `shell/desktop/modules/inputmethod` | 7 | 5 |
| `shell/desktop/modules/notifications` | 7 | 8 |
| `shell/desktop/modules/overview` | 9 | 2 |
| `shell/desktop/modules/quicksearch` | 7 | 2 |
| `shell/desktop/modules/stage` | 5 | 1 |
| `shell/desktop/modules/wallpaper` | 7 | 6 |

另有 Settings 壁纸瓦片边框 150→base，两个 AppTheme 的 120/220 兼容属性改读统一策略。

### 例外登记

以下按文件和数值分组，行号为本次审计定位（多行表达式列出首行，完整式见源码）；同一数值的多个段合并登记。每组保留原时长和原曲线，原因对应源码 `motion-exception` 注释。

| 文件 | 行号 | 保留值/表达式 | 原因 |
| --- | --- | --- | --- |
| `shared/demo-ui/controls/LiquidGlassSwitch.qml` | 82 | `root.reduceMotion ? 0 : _pressed ? 120 : 200` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidGlassSwitch.qml` | 92, 95 | `50` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidGlassSwitch.qml` | 93 | `70` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidGlassSwitch.qml` | 94 | `60` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidSegmentedControl.qml` | 60 | `85` | 选择透镜形变及位移响应 |
| `shared/demo-ui/controls/LiquidSegmentedControl.qml` | 61 | `155` | 选择透镜形变及位移响应 |
| `shared/demo-ui/controls/LiquidSegmentedControl.qml` | 62 | `150` | 选择透镜形变及位移响应 |
| `shared/demo-ui/controls/LiquidSegmentedControl.qml` | 187 | `300` | 选择透镜形变及位移响应 |
| `shared/demo-ui/controls/LiquidSlider.qml` | 75 | `root.reduceMotion ? 0 : root._pressed ? 270 : 460` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidSlider.qml` | 87, 90 | `100` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidSlider.qml` | 88 | `150` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidSlider.qml` | 89 | `120` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/demo-ui/controls/LiquidSlider.qml` | 275 | `root.reduceMotion || root._pressed || root._suppressXAnimation ? 0 : 200` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/colorize/ArtworkColorSource.qml` | 23 | `760` | 背景取色的环境过渡 |
| `shared/qml/controls/LiquidGlassButton.qml` | 43 | `Foundation.AppTheme.reduceMotion ? 0 : (_pressed ? 100 : 150)` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidGlassButton.qml` | 55, 57, 58 | `100` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidGlassButton.qml` | 56 | `150` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidGlassSwitch.qml` | 84 | `_pressed ? 100 : 200` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidGlassSwitch.qml` | 93, 94, 95, 96 | `100` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidNavBar.qml` | 118, 119, 120 | `100` | 逐帧弹簧的显示滤波，三轴同步 |
| `shared/qml/controls/LiquidSlider.qml` | 71 | `root.reduceMotion ? 0 : root._pressed ? 220 : 400` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidSlider.qml` | 83, 85, 86 | `100` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidSlider.qml` | 84 | `150` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/LiquidSlider.qml` | 292 | `root.reduceMotion || root._pressed || root._suppressXAnimation ? 0 : 200` | 透镜膨胀、四段形变/拖拽位移的耦合物理响应 |
| `shared/qml/controls/SelectionHighlight.qml` | 18 | `80` | 80ms 按压反馈，低于普通档位 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 318 | `650` | 文件夹合并拖拽接受计时 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 1540, 1547 | `450` | 搜索清除图标的配套 Bezier 缩放/旋转 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 1744, 1751, 2497, 2504 | `160` | 拖拽位移、握持缩放及落点提交前的回落 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 1758, 2511 | `120` | 拖拽位移、握持缩放及落点提交前的回落 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 1832, 1840 | `110` | 编辑模式周期抖动 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 2054, 2061, 2706, 2713 | `180` | 拖拽位移、握持缩放及落点提交前的回落 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 2307 | `220` | 文件夹 OutBack 膨胀 |
| `shell/desktop/modules/applauncher/AppLauncherWindow.qml` | 2560, 2568 | `(index % 3 === 0) ? 140 : 160` | 编辑模式周期抖动 |
| `shell/desktop/modules/bar/NotificationHistoryPane.qml` | 394 | `360` | 空状态玻璃的淡出包络 |
| `shell/desktop/modules/bar/StatusTooltip.qml` | 28, 29 | `70` | 70ms 提示的近即时显隐 |
| `shell/desktop/modules/bar/SysTray.qml` | 525, 530, 690, 695 | `150` | 拖拽重排或 70ms 提示显隐 |
| `shell/desktop/modules/bar/SysTray.qml` | 621, 622 | `70` | 拖拽重排或 70ms 提示显隐 |
| `shell/desktop/modules/bar/TemperatureSensorPopups.qml` | 96, 97 | `70` | 70ms 提示的近即时显隐 |
| `shell/desktop/modules/bar/controlcenter/BluetoothCard.qml` | 82 | `900` | 加载指示周期 |
| `shell/desktop/modules/bar/controlcenter/WifiCard.qml` | 88 | `900` | 加载指示周期 |
| `shell/desktop/modules/common/ContextMenu.qml` | 77 | `60` | 子菜单/菜单的近即时退出，不放慢到 100ms |
| `shell/desktop/modules/common/ContextMenu.qml` | 271 | `80` | 子菜单/菜单的近即时退出，不放慢到 100ms |
| `shell/desktop/modules/common/LiquidGlassPanel.qml` | 152 | `2600` | 环境色/材质强度插值 |
| `shell/desktop/modules/common/LiquidGlassSurface.qml` | 96 | `2600` | 环境色/材质强度插值 |
| `shell/desktop/modules/common/LiquidGlassSurface.qml` | 231 | `420` | 环境色/材质强度插值 |
| `shell/desktop/modules/common/WavyProgress.qml` | 26 | `1100` | 不定进度循环周期 |
| `shell/desktop/modules/deskcenter/DeskCenterWindow.qml` | 2148, 2154 | `index * 620` | 音乐音符循环的相位、寿命与淡出包络 |
| `shell/desktop/modules/deskcenter/DeskCenterWindow.qml` | 2149 | `2200 + index * 180` | 音乐音符循环的相位、寿命与淡出包络 |
| `shell/desktop/modules/deskcenter/DeskCenterWindow.qml` | 2155 | `360` | 音乐音符循环的相位、寿命与淡出包络 |
| `shell/desktop/modules/deskcenter/DeskCenterWindow.qml` | 2156 | `1840 + index * 180` | 音乐音符循环的相位、寿命与淡出包络 |
| `shell/desktop/modules/deskcenter/DeskCenterWindow.qml` | 2874 | `380` | 文件夹拖入 dwell |
| `shell/desktop/modules/deskcenter/FreeSlotDesktopDemo.qml` | 972, 977 | `150` | 拖拽重排响应；跟手期间零时长 |
| `shell/desktop/modules/dock/DockAnimation.qml` | 33, 38 | `70` | 物理 hover/按压反馈或 30ms 预览交接 |
| `shell/desktop/modules/dock/DockAnimation.qml` | 39 | `45` | 物理 hover/按压反馈或 30ms 预览交接 |
| `shell/desktop/modules/dock/DockAnimation.qml` | 113 | `30` | 物理 hover/按压反馈或 30ms 预览交接 |
| `shell/desktop/modules/dock/DockContainer.qml` | 965 | `180` | 拖拽重排响应；跟手期间零时长 |
| `shell/desktop/modules/dock/DockIcon.qml` | 459, 461, 463, 724 | `115` | 关注提示弹跳、编辑抖动及徽标回弹的配套淡入 |
| `shell/desktop/modules/dock/DockIcon.qml` | 467, 469, 471 | `210` | 关注提示弹跳、编辑抖动及徽标回弹的配套淡入 |
| `shell/desktop/modules/dock/DockIcon.qml` | 718 | `105` | 关注提示弹跳、编辑抖动及徽标回弹的配套淡入 |
| `shell/desktop/modules/dock/DockIcon.qml` | 941 | `140` | 关注提示弹跳、编辑抖动及徽标回弹的配套淡入 |
| `shell/desktop/modules/dock/DockIcon.qml` | 944 | `160` | 关注提示弹跳、编辑抖动及徽标回弹的配套淡入 |
| `shell/desktop/modules/dock/DockMusicPlayer.qml` | 273 | `1200` | 跑马灯阅读停顿和按距离计算的匀速滚动 |
| `shell/desktop/modules/dock/DockMusicPlayer.qml` | 277 | `Math.max(900,` | 跑马灯阅读停顿和按距离计算的匀速滚动 |
| `shell/desktop/modules/dock/DockMusicPlayer.qml` | 282 | `800` | 跑马灯阅读停顿和按距离计算的匀速滚动 |
| `shell/desktop/modules/dock/DockMusicPlayer.qml` | 370 | `900` | 跑马灯阅读停顿和按距离计算的匀速滚动 |
| `shell/desktop/modules/dock/DockMusicPlayer.qml` | 375 | `Math.max(800,` | 跑马灯阅读停顿和按距离计算的匀速滚动 |
| `shell/desktop/modules/dock/DockMusicPlayer.qml` | 381 | `650` | 跑马灯阅读停顿和按距离计算的匀速滚动 |
| `shell/desktop/modules/dock/DockMusicPopup.qml` | 251 | `index * 85` | 均衡器周期及错相延迟 |
| `shell/desktop/modules/dock/DockMusicPopup.qml` | 253 | `220` | 均衡器周期及错相延迟 |
| `shell/desktop/modules/dock/DockMusicPopup.qml` | 255 | `260` | 均衡器周期及错相延迟 |
| `shell/desktop/modules/dock/DockRevealHandle.qml` | 180 | `600` | 环境背景插值 |
| `shell/desktop/modules/inputmethod/InputMethodCandidateList.qml` | 134, 136, 138, 140 | `150` | SmoothedAnimation 速度连续性及原 easing cap |
| `shell/desktop/modules/inputmethod/InputMethodPopup.qml` | 134, 139 | `160` | SmoothedAnimation 速度连续性及原 easing cap |
| `shell/desktop/modules/stage/StageCard.qml` | 340 | `StageConfigService.cardEnterDuration + 40` | 用户配置/KWin 投影共享时序及倾斜回弹 |
| `shell/desktop/modules/stage/StageCard.qml` | 366 | `card.engaging ? 180 : StageConfigService.tiltAnimDuration` | 用户配置/KWin 投影共享时序及倾斜回弹 |
| `shell/desktop/modules/stage/StageCard.qml` | 462, 463 | `150` | 用户配置/KWin 投影共享时序及倾斜回弹 |
| `shell/desktop/modules/stage/StageConfigService.qml` | 193, 195 | `200` | 用户配置/KWin 投影共享时序及倾斜回弹 |
| `shell/desktop/modules/stage/StageConfigService.qml` | 194 | `140` | 用户配置/KWin 投影共享时序及倾斜回弹 |
| `shell/desktop/modules/stage/StageConfigService.qml` | 215 | `320` | 用户配置/KWin 投影共享时序及倾斜回弹 |
| `shell/desktop/modules/wallpaper/DepthWallpaperLayer.qml` | 23 | `500` | 场景环境淡入 |
| `shell/desktop/modules/wallpaper/DepthWallpaperLayer.qml` | 39, 40 | `150` | 深度视差指针滤波 |
| `shell/desktop/modules/wallpaper/WallpaperImageLayer.qml` | 26 | `activeTransition === "simple" ? 260 : 800` | 壁纸模式的配套环境转场 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 422 | `280` | 透镜形变、膨胀的物理节奏 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 423 | `180` | 透镜形变、膨胀的物理节奏 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 469, 471 | `55` | 透镜形变、膨胀的物理节奏 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 470 | `65` | 透镜形变、膨胀的物理节奏 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 472 | `75` | 透镜形变、膨胀的物理节奏 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 476 | `100` | 透镜形变、膨胀的物理节奏 |
| `shell/desktop/modules/wallpaper/WallpaperPreviewBar.qml` | 477 | `250` | 透镜形变、膨胀的物理节奏 |

另外保留：启动台按剩余距离计算的 `180..420ms` swipe settle；KosKineticScroll 的物理计算与 Cubic 曲线；通知原 InCubic 入场；ContextMenu 原减速退出；WallpaperColorSource 的 `transitionDuration: 0`；通知清理序列的业务延迟；所有 Timer/通知停留/轮询间隔。数值未移动到新变量以规避统计。锁屏和 SDDM 是独立应用的专用解锁/错误反馈编排，不在 shell/shared 普通动效批量替换范围。

### 提交与真实验证记录

| 批次 | 提交 | 内容 |
| --- | --- | --- |
| 方案 | `3f8c6d76` | 基线核查及待确认方案 |
| A | `0cc16e39` | 共享策略、foundation 与 QtTest |
| B | `af96a9f5` | Liquid 控件 |
| C1 | `e37a0bdc` | common、bar、notifications |
| C2 | `61e9f14c` | applauncher、dock、inputmethod |
| C3 | `2e24dd1c` | deskcenter、overview、quicksearch、stage、wallpaper |
| D | `48ed0f0c` | Demo、Settings、剩余共享入口 |
| 测试夹具 | `548ebb46` | 隔离夹具复制真实策略；此提交单独运行仍缺类型导出 |
| 夹具修复 | `6f523713` | named qmldir 导出 MotionTokens，专项 2/2 通过 |
| 物理例外收尾 | `b79971be` | 恢复透镜 280/180ms、KWin 扇叠 150ms 同步，补具体注释 |
| 通知夹具保留 | `ccd6da63` | 显式保留临时目录，面板/来源图标原断言 2/2 通过 |

曾有组合命令的后续 lint 成功掩盖前面的 CTest 失败，导致 `548ebb46` 提交时夹具仍未通过；后续检查真实 CTest 输出后补齐类型导出并确认 2/2 通过，不将该中间提交记为通过。

Qt 6 显式路径 `/usr/lib/qt6/bin/qmllint`，版本 6.12.0；各批次检查分别报告 13、9、35、16、11、13 files, OK。最终跟踪文件检查：`QML syntax: 476 files, OK`。仓库脚本只做语法检查，不能称为完整类型 lint 零警告。唯一策略 `MotionTokens.qml` 另以原生 Qt6 qmllint 默认检查运行，退出码 0、无输出；这不代表全部 Shell 文件完成完整类型 lint。视觉契约始终报告 `KOS UI visual contract: all checks passed`。

编译：`kos-shared-motion-tests`（包含 Kos.Demo）成功；独立 CMake 驱动的 `kos_ui` 成功；补编译 Stage desktop policy 和 overview panel projection 测试目标成功。独立配置 `KOS_BUILD_PLATFORM=ON` 后实际 `kos-settings` 编译成功（206 个构建步骤）；原 `build-motion` 配置关闭 platform，因而不存在该目标。无新增依赖。

已通过的实际输出：

- 策略 QtTest：`Totals: 4 passed, 0 failed, 0 skipped, 0 blacklisted`。
- 输入法：`Totals: 25 passed, 0 failed, 0 skipped, 0 blacklisted`。
- Dock/启动台 Node：`# tests 56`、`# fail 0`。
- C1 相关 CTest：`100% tests passed out of 6`。
- C3 可运行测试（排除缺 Pillow 的总览 GUI）：`100% tests passed out of 20`。
- Demo/共享动效/交互/选择高亮：`100% tests passed out of 4`。
- 选择面板 QtTest：`Totals: 6 passed, 0 failed, 0 skipped, 0 blacklisted`，该次独立执行未接 Wayland 的 shipping-surface 部分明确 SKIP。
- 实际 Settings：隔离 D-Bus/offscreen 下 `--smoke-test` 退出码 0，明确加载本工作树 `apps/settings/main.qml`。日志有 LiquidGlassSwitch、LiquidSlider、ColorRampSlider 的 `enabled` 覆盖基类成员警告，不能称零警告；未作基线差分。
- 通知面板/来源图标保留目录后完整进程通过：`100% tests passed out of 2`。
- 最终夹具回归：`100% tests passed out of 2`；物理例外恢复后 Stage visibility、motion-tokens、shared-motion：`100% tests passed out of 3`。
- 完整 popup-motion 在私有 KWin OpenGL 下通过原始断言：`PASS: Control Center navigation, confirmation, close/reopen; popup input lifetime; menu navigation; launcher exit; transformed blur geometry; stable navigation glass; Dock info backdrop; card content routing; launcher geometry and tint in six presentations; notification blur lifetime, dismissal, expiry and arrival during exit`。
- 整套 `quickshell --path shell --no-color` 在私有 D-Bus/KWin 下达到 `Configuration Loaded`，Dock/Appearance snapshot、启动台和控制中心 IPC 可调用；还在同一隔离 Wayland 会话打开并关闭 Konsole。由于缺平台 daemon，未取得完整 DockModel 窗口跟踪证据，不能宣称完整 Dock 真机流程通过。仅停止自己创建的实例。隔离环境缺平台服务、PipeWire、portal、kdeglobals，以及 SVG path 警告仍记录在日志中，不能把空 stderr 当无警告。

### 未完成与未通过项

1. **五组前后录屏均待真机验证**：控制中心、启动台、Dock hover、Settings 页切换、通知退出。尚无基线/改后视频，不声明视觉等价或“更顺”。Material/windows12 的完整交互也待验证；策略曲线切换已由 QtTest 覆盖。
2. 总览 GUI 测试缺 `PIL`；系统 Python 已具备 D-Bus，但没有 Pillow。遵守不新增依赖，未改断言或伪造通过。
3. popup-motion 初测失败已定位并解决验证环境：软件后端在 stage=1 入场检查失败；OpenGL 初测 stage=4 是标题 `Weather` 不匹配中文断言，blur 对象实际非空。`Qt.locale().uiLanguages` 显示英语优先，补齐 `LANGUAGE=zh_CN`（同时 LANG/LC_ALL=zh_CN.UTF-8）后，原始测试完整通过，没有修改标题/blur 断言。未执行依赖原生 KOS 特效的 `--verify-wayland` 帧提交专项。
4. 扩展 32 项 CTest 首轮为 `81% tests passed, 6 tests failed out of 32`。其中 Dock reveal、notification-history-visual 的 token 夹具缺失已修正，专项重跑 2/2 通过；notification-pane 和 source-icons 初次在清理时被环境 `SAFE_DELETE_BULK_CONFIRM_REQUIRED` 拦截。增加 `KOS_KEEP_TEST_TMP=1` 后保留文件、原断言专项重跑 2/2 通过，不绕过删除保护。四项专项通过不拼接成一次未实际执行的 32/32 结果。
5. Dock hover-hit/magnification 的退出阶段报告 `Unable to assign [undefined] to bool/double`，原始测试仍未通过。额外最小差分在相同当前依赖下分别加载当前/`6df77a57` 的 DockIcon：两侧 exit=0、均有 `DOCK_HOVER_HIT_PASS`、均产生相同的 18 条退出绑定警告。因此不是 DockIcon 本轮改动单独引起；未做整仓基线对照，不将它扩大成全基线结论。magnification 的三边 geometry/selection 报告通过不代表整个测试通过，未修改警告断言。
6. Settings 实际应用加载已通过，但五组视觉对照、KWin 原生玻璃与全部文件完整类型 lint 尚未完成。资源编译、页面状态机测试和 Shell 加载不替代这些检查。

本轮验证依据包括已调用的 `verify` skill（`.claude/skills/verify/SKILL.md`）：真实 Shell 加载、日志与交互检查；完整 Dock 真机流程仍属上述待验收范围。

### 验证日志与复现入口

本工作树保留 `.build/motion/` 中的实际输出：`all-lint.log`、`policy-full-lint.log`、`final-tests.log`、`fixture-final2.log`、`runtime-result.log`、`runtime-shell.log`、`runtime-popup.log`、`ui-build.log`、`settings-build.log`、`settings-smoke.log`、`retained-notification-tests.log`、`dock-differential.log`。这些是本地忽略产物，不进入提交。`build-motion/` 是未跟踪构建目录，也没有提交或清理。

```sh
QMLLINT=/usr/lib/qt6/bin/qmllint node tools/ci/qmllint-changed.mjs --all
node shared/qml/test_visual_contract.mjs
PATH=/usr/bin:/bin KOS_KEEP_TEST_TMP=1 QT_FORCE_STDERR_LOGGING=1 \
  ctest --test-dir build-motion \
  -R '^kos-shell.(dock-reveal-runtime|notification-history-visual)$' --output-on-failure
# 仅在独立的测试 Wayland / D-Bus 会话内运行；不得指向用户当前桌面。
LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 LANGUAGE=zh_CN \
  QT_FORCE_STDERR_LOGGING=1 /usr/bin/python3 tests/popup-motion/run.py
```
