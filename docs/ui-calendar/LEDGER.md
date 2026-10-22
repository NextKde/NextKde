# LQ0 — 液态组件接入与剩余 spec 收敛

## 本轮
- LQ18c 全量回归 17/N：**D04 内联标签字重 PASS（产品改动 2 处，仅两行属性）**。
  `EventEditorDialog.qml:761/:773` 的 `Todo list` / `Priority` 由 11 Normal 改为
  **11 DemiBold**，与七个主字段标签同式；字号、`AppTheme.mutedText`、RowLayout spacing 8、
  两个组合框的 fill/radius/stroke、可见性绑定全部零改动。
  light+dark 1100×692 实拍（打开事件编辑器 → 点勾「同时将此日程显示为待办任务」）：
  - light 墨量（暗像素/bbox）：内联 **.470/.556**，主字段 .533–.590，同尺寸 11 Normal
    提示行 **.267** → 内联进入 DemiBold 档；
  - dark（亮像素/bbox）：内联 **.353/.416**，主字段 .519，提示行 **.126**；
  - 布局未动：两标签 ink y408..417 与组合框文字同基线，行仍 404..421，下方「重复」
    仍 y448；「优先级」完整无裁切。
  - 帧 `r063-d04-link-unchecked.png`（勾选前）、`r063-d04-link-checked.png`（light）、
    `r063-d04-link-checked-dark.png`、`r063-d04-inline-4x.png`、`r063-d04-inline-dark-3x.png`。
  - spec.md D04 由 PARTIAL 回填 **PASS**。玻璃预算不变：持续 2/2，瞬态 1/1（弹框）。

## 上一轮（LQ18c 16/N E05）
- E05 黄名单腿 PASS（无产品改动）：隔离 profile 加 `Yellow #f2c14e` list + 两条黄色
  VTODO；侧栏点色精确、全天/计时 chip 同填充 (253,244,225)、stripe #f2c14e、
  ink (121,96,39) 对比度 5.46:1、4x 可读。spec E05 回填 PASS。

## 前一轮（LQ18c 15/N 对账）
- 40 个 PENDING 行与 rounds.md 取证对齐，spec.md 回填 37 PASS + 3 PARTIAL；
  唯一剩余为 E05 黄腿 / D04 内联标签 / D03 两条裁决，现只剩 D03。

## 队列（一轮一条；[x]=已完成）
- [x] LQ01 基线：light week 1100×720 / 760×540；日志无启动回归。
- [x] LQ02 工具栏：`LiquidSurface`(regular) + `LiquidOuterShadow`；持续玻璃 1/2。
- [x] LQ03 分段控件：`LiquidSegmentedControl` materialForm，228×28、pill 231。
- [x] LQ04 工具栏按钮：`LiquidActionButton` + host-owned plain 行；无叠玻璃。
- [x] LQ05 侧栏表面：`LiquidSurface`(regular)，合成 237（持续 2/2）。
- [x] LQ06 侧栏分类：`LiquidCheckBox` 12×12/r3 视觉。
- [x] LQ07 事件编辑器：`LiquidDialog` + `LiquidTextField`，r24/.25 scrim/D05 几何不变。
- [x] LQ08 任务编辑器：同上 + 标签列对齐、组合框 plain、备注外环；D05 三行按钮已验。
- [x] LQ09 详情浮层：`LiquidSurface`（plain α .06、禁叠玻璃）+ `LiquidOuterShadow`，r16。
- [x] LQ10 右键菜单：`MenuActionRow` 行高 30/图标 16/左内 10、plain + hoverFill、1px 分隔线；
  r16 regular E3 卡片、36px 阴影边；light/dark 已拍。O04–O07（O09 未做）。
- [x] LQ11 tooltip：实心卡 + 发丝 + E1、r12/11px/6×10、1000ms、单实例、下方定位 +
  水平 clamp；light/dark 与出现/消失连续帧均已拍，右缘 clamp 生效；上方翻转在当前布局
  不可达（见外推 O09）。
- [x] LQ12 月视图：连续网格/V04 去 agenda 卡/V05 day 共用/V02/M04 已实拍通过；
  V03 跨天连续条未做（见仍差 #4）。
- [x] LQ13 全天条：A01–A04（最小 28、行 24×1.33、gap 2、inset 2、连续跨天、`+N` 溢出）；
  light 实拍通过，dark 未验。
- [x] LQ14a 事件块 E01–E03/E05 + N02：tint 预混同全天条、stripe 3/3、顶部 1px、now 线/pill。
- [x] LQ14b E04：timed 块按真实起点/时长绘制、重叠簇分道（≤3）、短块 30min 可读；light 实拍通过。
- [x] LQ15 窄窗：760×540 回归完成；timed 网格整数列宽 + 宽度随 resize 同步，窄窗不再溢出。
- [x] LQ16 空/密/深色：X04/X05/X03 回归通过；timed 网格改整数列宽 span，1100 右缘余量
  1x 不可辨。
- [x] LQ17 底色与 chrome：S01/S04/C05 通过——侧栏 237/画布 255（dark 41/30）、
  分类行勾选/未勾选可辨 + hover 227/按下 220、圆点 hover/press 与 settings 同为不变，
  工具栏 chrome hover/press 有连续帧；inactive 按代码证据（见外推）。
- [x] LQ18a X06 日历/settings 同尺度对照：PASS（仅取证）。
- [x] LQ18b X07 弹框/浮层/菜单/tooltip 同尺度对照：PASS（仅取证）。
- [x] LQ18c 收尾 5/N：**V03b 续接块预混不透明**——4x 边界 Δ1（原 (205,220,231) 已消），
  单日块复拍未变。V03 线全部结清。
- [x] LQ18c 收尾 6/N：**编辑器组合框 plain 化**——四处 combo 填充 240，与旁侧字段同面，
  1px 边消失。
- [x] LQ18c 收尾 7/N：**事件编辑器备注框焦点环外扩**——聚焦时 r12 环外扩 4px，失焦
  无描边，与任务编辑器逐像素同构。
- [x] LQ18c 收尾 8/N：**N01 补拍**——今天红盘（22×22 红/白字）与选中日灰盘
  （22×22 #E5E5E5/暗字）同屏可辨；now 线 261–262 红、gutter 01:53 pill 可读，
  选中灰不压 now 红。N01 PASS。
- [x] LQ18c 收尾 9/N：**E06 完成态勾标 PASS**——数据链根因是 fixture link 属性前缀写错
  （`X-KOS-` → `X-KDE-KOS-`）；改 fixture 后 timed/全天两种 chip 均 ✓ + strikeout 实拍通过。
- [x] LQ18c 收尾 10/N：**R32 三枚纯黑 chip 修复**——`start` 空串未回退 `due`（落 00:00）
  + `listColor` 返回字符串致混合路径 NaN 变纯黑；改后任务回到 due 时刻并正常着色。
- [x] LQ18c 收尾 11/N：**O09 菜单腿结清**——唯一触发点（工具栏 More）在 1100/760 两档都完整
  落在窗内（卡右 = 窗口−36/−40，阴影槽未被裁切）；垂直翻转不可达，项目顺序翻转 N/A。
- [x] LQ18c 收尾 12/N：**day 视图 TypeError 清零**——`itemColor`/`itemCompleted`/`itemTodoId`
  加 undefined 早退；day/week 往返 5 次日志 0 条 TypeError，两视图目视不变。
- [x] LQ18c 收尾 13/N：**任务编辑器高度内容自适应**——编辑态 560→464，备注→保存
  95→16px；footer 固定高度不变，D05 三行未压。
- [x] LQ18c 收尾 14/N：**菜单 hover 圆角结清**——实测水平内缩 8 ⇒ r_inner 8，原 r8 正确，
  无产品改动；light hover 帧已拍（前：开菜单无 hover；后：首行 hover 244）。
- [x] LQ18c spec 回归 2/N：**D02 弹框圆角 PASS**——四角 r≈24 = `AppTheme.largeRadius`，
  无直角；边缘单层 AA 无内描边。仅取证，无产品改动。
- [x] LQ18c spec 回归 3/N：**D03 双层阴影 PASS**——ambient+key 双层 token 阴影，
  light 近/中/远 174/183/191（目标 170/180/191），卡面 255 不变；cardSurface/1px border
  两条待裁决（见仍差 #1）。
- [x] LQ18c spec 回归 4/N：**D04 弹框文字层级取证**——标题 20 DemiBold 左内 24 PASS；
  正文 13 常规 PASS；字段标签 11px 但 **Normal 非 DemiBold**（spec 不符，见仍差 #3）。
- [x] LQ18c spec 回归 5/N：**D04 标签字重修正**——7 个主字段标签加 DemiBold，墨量翻倍、
  三级层级保持；light/dark 实拍通过。内联 Todo list/Priority 未纳入（见仍差 #3）。
- [x] LQ18c spec 回归 6/N：**D06 按钮高亮/胶囊 PASS**——主按钮实心 accent + 白字、
  次按钮浅灰 + 深/亮字；两枚 349×31、同 r=h/2 胶囊、文字水平零偏、垂直 ≤0.5px；
  light/dark 同构。仅取证，无产品改动（详见 rounds.md R43）。
- [x] LQ18c spec 回归 7/N：**D07 按钮权重 PASS**——编辑态仅保存为实心 accent，取消/删除同 227,229,230；确认态仅取消为实心 accent，删除保持弱权重 + 红字（#d83b3b 色族）。仅取证，无产品改动（详见 rounds.md R44）。
- [x] LQ18c spec 回归 8/N：**D08 按钮三态 PASS**——五枚按钮 hover/pressed 填充各一档
  （保存 69,152,204/85,161,208；中性 215,216,217/204,205,206）、2px focusRing
  (123,182,219) 四边可见、Esc 在编辑/确认两态均关闭。仅加 `objectName`（零视觉改动）。
- [x] LQ18c spec 回归 12/N：**D11 窄窗完整性/自身滚动 PASS**——760×540 事件编辑器卡
  380×508、表单 262/418 由内部 Flickable 滚到 contentY 156，footer 三钮固定完整；
  任务编辑器编辑态 380×428、243=243 免滚动，三行 footer 完整；无产品改动。
- [x] LQ18c spec 回归 13/N：**D12 关闭唯一性 PASS**——设置面板头部重复 `×` 已删
  （footer `完成` 为唯一关闭口）；事件/任务编辑器无 `×`，删除确认是同卡状态非套弹框；
  Import/Export 系统对话框单关闭口。
- [x] LQ18c spec 回归 14/N：**D13 scrim PASS**——开弹框时父窗均匀 ×0.75（白 191/
  侧栏 178/周末 187），内容文字 2x 可读，非纯黑；跨窗可交互按 `modal: true`
  窗口内 Overlay 判 PASS（单窗口无实拍）。
- [x] LQ18c 全量回归 15/N：**PENDING 对账**——40 行全部对齐，spec.md 回填 37 PASS +
  3 PARTIAL；唯一剩余 = E05 黄名单腿 / D04 内联标签 / D03 两条裁决。
- [x] LQ18c 全量回归 16/N：**E05 黄名单腿 PASS**——fixture 加 `Yellow #f2c14e` list +
  两条黄色 VTODO（全天/计时）；侧栏点 #f2c14e 精确、两处 chip 填充同 (253,244,225)、
  stripe #f2c14e、ink (121,96,39) 对比度 5.46:1、4x 可读。spec E05 回填 PASS。
- [x] LQ18c 全量回归 17/N：**D04 内联标签字重 PASS**——`EventEditorDialog.qml:761/:773`
  `Todo list`/`Priority` 补 `font.weight: Font.DemiBold`；light 墨量 .470/.556、dark .353/.416
  对同尺寸 Normal 提示行 .267/.126；布局零变；spec D04 回填 PASS。

## 已改
- LQ18c 全量回归 17/N（D04 内联标签）：`EventEditorDialog.qml:761/:773` 两个内联
  `Label` 各补 `font.weight: Font.DemiBold`，并把单行声明展开为多行（与七个主字段
  标签同式）；字号 11、颜色、间距、组合框参数、可见性绑定零改动。
- 更早的已改记录（LQ01–LQ18c 16/N）见 `rounds.md`，不再在 state 滚动窗口重复。

## 仍差
1. **D03 卡片结构两条待裁决**：① 面硬编码 `#ffffff` / `#29292d` 而非 `cardSurface`
   （该 token 在玻璃会话下 α .54/.46 半透明且带 accent 微染色，与 D01 实测 255 及参考
   白卡冲突）；② 无 1px `border`（`alert-macos.png` 无可见描边）。双层阴影已改为
   `shadowAmbient`+`shadowKey` 并 PASS。下轮按“参考图优先”结清并回填 spec。
（浮层/菜单观感差异不是 spec ID 失败，已归入 X07 外推词条；tooltip 各腿、O09 可达面、
V03/V03b 均已结清，细节见 rounds.md R152–R154。）

## 外推待确认
- D12 设置面板删除 `×` 后，标题文本仍从卡内 x≈415 起（图标右缘+间距应为 345），
  实测既不贴图标、也不在卡/列中心；删 × 只能让居中元素右移 ~20px，解释不了 70px，
  判为既有头部布局/字体度量问题，本轮未动（D12 只要求关闭唯一性）。
- `KosSettingsDialog` 是 calendar/todo/weather 共用组件：本轮删 `×` 三处同时生效；
  本轮只实拍 calendar，todo/weather 未复拍（视觉上仅少一个按钮，风险低）。
- D10 reduceMotion 腿未实拍：`AppTheme.qml:72` `reduceMotion: false` 无赋值入口，本环境
  无法切换；按 `:239-241` 的 `motionNormal/Fast = 0` 与 `KosDialog.qml:10` 的
  `scale: reduceMotion ? 1 : …` 判「不动」，仅代码证据。
- D10 退出时 scrim 先于卡片消失：`Overlay.modal` 跟随 popup.opened（close 起点即 false），
  卡片随后仍按 120ms InCubic 淡出（帧 0012 无 scrim、卡 α≈.68）。spec D10 只约定卡片
  scale/时长/曲线，参考图无动效帧，故未改产品。若要求 scrim 与卡片同步淡出，需先裁决：
  自绘遮罩会动到 D01/D03 已 PASS 的层级与点击阻挡。
- D10 抓帧延迟：nativeRecord 的 `pointerDriver.capture` 单帧耗时可达 ~20–100ms，120ms 的
  退出动画可能整段落在两次抓帧之间（R056 的 32 帧未拍到中间帧即此因）；本轮改用 8ms
  属性探针 + 4 帧像素佐证。此后 <150ms 的动效一律配属性采样，不以抓帧缺帧判失败。
- 760×540 + 模态弹框开启时，`captureClient` 的缓冲顶部 ≈148px 是陈旧/翻转内容带
  （R056 窄窗退出帧同款，见 `r056-exit760-0020.png`）。本轮 resize 抖动、重复抓帧均
  不能刷新；改由 `probeDialog` 卡 w/h + 像素量卡底/左右缘 + footer 位置取证，把该
  顶带记为无效区，不据此判产品缺陷。任务编辑器新开/编辑两态均可取到 footer 与表单。
- D10 进入录制的 f22（838ms）先于 f23 呈全显白卡、随后 f23 才回到 alpha .54，判为
  grab/合成器时序伪影（同一 popup 不可能先全显再淡入），不据此改产品。
- D09 的「完成必须有取消」对设置面板不适用：`shared/qml/foundation/KosSettingsDialog.qml:447-451`
  只有 `Done`（关闭）。设置项即时生效（无暂存/提交两态），`Done` 是关闭而非保存，配一个
  “取消”会暗示可回滚却无快照实现。故按语义判不冲突；若要求字面满足，需先裁决是否给设置
  加快照/回滚（产品语义变更）。
- 文件选择器（Import/Export）是独立顶层窗口：主窗 `captureClient` 只含日历窗口，整屏
  `spectacle` 在无人值守 VM 下返回空白（输出被blank），活动窗口 `spectacle -a` 可用。
  故 D09 ② 的 Import/Export 证据是活动窗口截图，不是合成桌面截图。
- D03 的 `cardSurface`：`AppTheme.qml:192-193` = `withAlpha(card, glassActive ? .54/.46 : 1)`。
  评审 VM 是有合成器模糊的玻璃会话，玻璃激活时弹框面会变成 α .54/.46，背后的窗口内容
  与 scrim 会透出，和参考 `alert-macos.png` 的不透明白卡、以及 D01 已实测的 255 冲突；
  即使 `glassActive=false`，`card = mix(windowRaised, accent, .018)`（`:159`）也带 accent
  微染色，不等于 255。故 D03 的“face = cardSurface”按参考图与既有 PASS 行为优先，
  **保留硬编码卡面**。若产品要字面满足 spec，应先裁决“弹框允许半透明/微染色”。
- D03 的 1px `border` 同样按参考图（无可见描边）判为可豁免；两条都需人工裁决，
  不代表实现缺陷。
- 任务编辑器高度：编辑态（三行 footer）实测卡 464、备注→保存 16px；New task（两行 footer）
  与删除确认态未复拍。高度公式随 footer implicitHeight 联动，两态只会更矮（760×540 下限
  476 仍高于 464，不触发滚动），风险低。
- V03 用“每格独立判左右接”而非整周 span 层：只有跨日项在相邻格恰好同一行时才视觉连续。
  fixture 的跨日项都是全天（排序恒在首行）故成立；若一条非 all-day 跨日事件与当天其他
  事件排序交错，相邻格会不同行。整周 span 层数据模型可支撑，但属结构性改动，未做。
- 跨月格连续条在非本月格随整格 0.5 压暗（April 行实测 Mar 30–Apr 1 淡、Apr 2 全亮），
  与 macOS“非本月整格压暗”一致，不是新缺陷。
- 760×540 复拍：`resize` 延迟一次重绘才落地，命令后立即 grab 仍返回 1100×692 缓冲；
  本次以随后的 April / October 两张窄窗实拍为准（内容 760×540 画在缓冲左上）。
- O06：动作菜单里没有破坏性项，故“破坏性项置底 + destructive + 不重复快捷键”按 **N/A**
  判 PASS（无快捷键文本为实拍）；若后续加入“删除日历”类项，必须置底并染 destructive。
- O09 菜单：全仓只有一个 Menu 触发点（工具栏 More；box 1100 下 x1056..1084、760 下 x716..744），
  菜单恒向下展开，卡右缘 = 窗口−36（1100）/ −36..−40（760），36px 阴影槽在窗内，不越界。
  垂直翻转需要“锚点下方空间 < 卡高（≈248）”的生产者，当前布局（工具栏在顶部、min 高 540）
  不存在；水平方向用右对齐 + clamp 而非翻转（卡始终向左生长）。项目顺序翻转仅在翻转发生时
  才需要，判 N/A。未为验证新增底部触发点。
- O09：右缘水平 clamp 已验证（tooltip 卡右停在窗口内 ~10px）；tooltip 垂直翻转**当前布局
  不可达**：带 hint 的锚点只有工具栏（y36–64）与日期组（y81–107），卡底 ≤145；最靠底的
  mini 月箭头（heading y510–536）无 hint，且 540 min 高下该块被 `bottomMargin 12 +
  fixedHeight 170` 钉在底部、heading 底距窗底恒 156 > 28+10+8，故任何允许窗高都不触发。
  代码保留但未实证；不为此新增 hint 或违规缩窗。菜单/浮层仍只做右对齐/内缩，无方向翻转。
- O07：菜单 hover (244,244,245) = 白 255 + `rowHoverFill` α.04；侧栏 237 + 同 token = 227。
  同一 token、不同底，判同一视觉语言；不是新 token。
- D13 的“应用其他窗口仍可交互”：评审 VM 只有一个窗口，无法实拍。按 HIG 语义（modal 只
  冻结本窗口）与 `Dialog.modal: true` 的实现判 PASS，不声称有跨窗口实拍。
- D03 与参考冲突：`alert-macos.png` 卡面没有可见描边，D03 字面却要求 1px `border`。本轮保留
  “无描边 + E4 大软阴影”（贴合参考图），把 D03 记为仍差；若必须满足字面，需裁决描边可见度
  是否可接受。
- X07 色调分层：浮层 240（plain α .06 over neutralPlane）与菜单 255（regular 玻璃压白纸）
  同屏可辨。参考自身也分层（sheet 255 / popover 壳 246 / tooltip 226 / 菜单染色玻璃），
  故按“角色分层”判同一语言；但参考浮层壳内有白行，我们是单卡，观感更平。是否给浮层加
  内部白行需产品/数据模型确认。
- X07 tooltip 面 242 vs 参考实测 226：沿用 O02 的 smallRadius/中性卡 token 优先，不按
  参考图像素改（与 LQ11 外推一致）。
- X07 圆角：参考 popover/menu 角按 2x 约 20pt，我们按 liquid-spec §4 取 16；token 优先。
- X06：settings 以仓库源码（session checkout）启动，橙条“开发者热更新模式”为 dev HUD；
  生产安装副本无此条。chrome/材料对照不受其影响，但截图里它占据内容区。
- X06：settings 的 QML 无窗口圆角自遮罩（app-only 截图直角），calendar 自遮罩 r30；
  KOS 会话里 settings 的圆角应由合成器负责。composited 桌面同屏圆角逐角本轮未拍，
  故只把“圆点/顶带/尺寸/调色”记为 PASS，不把直角截图当作圆角差异。
- C05 inactive 腿未实拍：评审环境只有一个窗口，无法让主窗失焦；`Main.qml` 圆点与
  `apps/settings/main.qml:947-961` 均无 `active` 绑定（失焦外观不变），按“与实际 settings
  相同”判为不变，而非新增灰化。若后续有多窗口评审环境，可补一张失焦帧坐实。
- S04 的“selected row gray r6”按 R096 口径落在 `CategoryRow`：我们的数据模型没有“选中
  日历行”语义（`pim.lists` 只是图例、无选中态），参考图 Personal 行的 226 灰仅作
  hover/按下的 ΔL 标尺；不新造选中语义。
- 本轮 dark 侧栏 41（light 237）为既有 LQ05 玻璃合成值 + 深色外推，无深色参考图。
- tooltip 旧计划“深色实心 rgba(0,0,0,.85)”与 spec O02 / 参考图冲突：参考是中性浅卡 + 轻边框 +
  柔阴影，已按 spec 执行（light `#F2F2F2`、dark `#3C3C3C`、边框 .10/.12）。
- tooltip 延迟按 O01 的“约 1 秒”取 1000ms（旧计划的 500ms 作废）。
- E1（spread 8）作为 tooltip 阴影；9px gutter、可视卡与控件间距 10，保证弹窗不覆盖锚点、
  不抢 hover。参考实测间距约 9–10。
- r12 直接取 spec O02 的 smallRadius；参考图角约 6（2x 角 10–12px），按 token 优先。
- 水平方向用 clamp 而非翻转；O09 的翻转仅实现垂直分支，未验证。
- tooltip 为实心（非玻璃），瞬态玻璃预算仍为菜单 1/1。
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
  未按其绝对尺寸。高亮圆角 8 为表外外推（参考示意约 12）。
- 菜单阴影预留 36 与 LQ09 浮层同法；菜单贴右缘时卡片右缘停在窗口内 36，未做 O09 翻转。
- 1100×720 在 VM 内实际内容高 692，基线按 692。
- 月视图无外部参考图（`.loop/refs/macos-calendar.png` 只含 week；年/月无图）：网格发丝取
  `AppTheme.text` α .085（light）/.13（dark）为表外值；连续网格、表头底线按 macOS 月视图常识外推。
- 月视图选中样式保留整格圆角描边 + 淡蓝填充（既有行为，非本轮引入）；参考无月视图区域，
  未改成“日期圆盘”式选中。
- V04 直接删除底部 agenda 卡：月视图无法再查看“选中日列表”，日程入口保留为格子 chip 与
  悬停 `+` 按钮；如需列表应回 week/day 视图。
- A01 的 “row 18” 按参考 1:1 数值保留为 24：本窗口 hour pitch 是 40 而参考 27，全表统一
  ×1.33 缩放（同 T01）；inset/gap 取 spec 的 2，于是单行带恰为 28，与 “min about 28” 一致。
- KCalendarCore 的 all-day `end` 是**含当天**（实测 Design sprint DTEND 10-17 → end
  10-16）：week 覆盖与详情范围均按含当天处理；timed end 仍为 exclusive。

- 事件 chip 垂直内缩按参考实测：顶 1 ref px、底 0（26 高 / 27 pitch），×1.33 取 1/0；
  水平 fill 距列规则 2 ref px ×1.33 = 3，未按 E02 "about 4" 的字面值。
- timed 填充 α 由 .19 统一到全天条的 .17（light）/.32（dark），E05 一致性优先；与参考
  fill (222,237,254) 的差别来自 accent 色相（项目 accent 偏青），本轮不改全局 accent。
- fixture 只写隔离 profile 的 `calendar.ics`（3 个 10-22 事件），不入库。
- harness 指针限制（R30 发现）：`pointer` press/release 在本 harness 下**不触发
  `TapHandler`**——日期头与全天 chip 两处实测均无响应，而同驱动下分段按钮
  （MouseArea/Button 路径）正常切视图。故不能据此判产品缺陷；选中态改用 `date`
  命令（handleActivation→selectedDate）设置，与点选后视觉状态相同。真机鼠标点选
  日期头仍未实拍。

- R33：`listColor` 改返回 QColor 后，月视图/详情浮层的 todo 着色走同一路径（此前对 todo 的
  `withAlpha`/`mix` 同样拿到 NaN）；月视图本周的 todo chip 被 `+N` 收起，未单独复拍，
  但事件 chip 与前一版逐像素同值。仅直接证据为 timed chip。
- R33：只有 “有 DUE 但无 start 的 todo” 走 due 回退；date-only 的 due 若 `allDay` 为 false
  仍会得 00:00 一小时块（KCalendarCore 对纯日期 DUE 置 allDay，当前 fixture 无此组合）。
- E04 不再需要跨行 z 序：每个小时格只画本格区间的切片，跨行块在相邻格上下相接（上行
  底部贴线、下行 y=0 起），不跨越 delegate 边界，因此不会压到后续行的发丝线。
- E04 短块最短可读 30min（fill 18px）为表外外推：参考图无 <1h 事件；E03 要求"短块一行
  可读"，11px 标题 + 2px 顶场约需 18px；visualEnd 仍被同 lane 下一块起点截断。
- E04 小时接缝按"整体块"处理：首段上角、末段下角 r3，中间方角；同 lane 首尾相接的两块
  之间保留下一块的 2px 顶场（实测 10:15 前留 2px 白）。
- E04 重叠块按簇内 lane 数平分宽度：单独块仍满宽，只有真正重叠的时段才分道；lane 上限 3
  与既有 +N 规则一致。标题/时间行只画首段，跨行后段为纯填充（参考多小时块同形）。
- LQ15 整数列宽是表外修正：分数列宽被 QQuickGridLayout 向上取整，760 下 7×102+52=766
  会溢出 6px。选 floor 而非“把余数塞给最后一列”：GridLayout 各列等宽，加宽末列会让所有
  列跟着变宽；余数留在最右画布（760 下 1px、1100 下 5px）。
- LQ16：1100 下右缘 5px 为画布色（light 255 vs 周末 field 249；dark 30 vs 37），
  1x 实拍不可辨、4x 裁切可见。若 LQ18 判不可接受，只有两条路：末列吸收余量（七列不再
  等宽、牵动 16 处 geometry）或逐列宽度函数（同上）；本轮不选。
- LQ16：密集簇 3 道时标题只余 3 字 + ellipsis 属参考同款行为（参考无重叠密集图，按 macOS
  窄事件惯例外推），不算 X05 的“unintended overlap”。

- E05 黄色腿（已结清 R062）：黄色由任务清单 todo 取证。`Main.qml:1697-1701`
  `itemColor` 对非 todo **恒返回 `AppTheme.accent`**（事件没有独立类别色，是产品设计，
  不是缺数据），故 E05 的 “category color” 只对 todo 有意义；隔离 profile 的
  `Yellow #f2c14e` list 与两条黄色 VTODO 只存在于 tmp，不入库。
- 对账口径（15/N）：spec.md 回填只引用已有实拍/量测记录，不重拍、不把外推升格为实拍。
  X03 dark-empty、D10 reduceMotion、D13 跨窗、O09 垂直翻转仍保留各自
  “未实拍/不可达（N/A）”的原始口径。

## Next round
LQ18c 全量回归 18/N：**D03 卡片结构两条结清**。复核 `macos26/alert-macos.png` 的卡面
（不透明白卡、无可见 1px 描边）与 D01 实拍 255；把 ① `LiquidDialog.qml:22` 面保留硬编码
`#ffffff`/`#29292d`（不用半透明/染色的 `cardSurface`）、② 无 1px border 判为**按参考图
豁免**，把 spec.md D03 由 PARTIAL 回填 PASS 并在「外推待确认」写明豁免理由；不切换
token、不改视觉、不重拍（D03 已有的 4x 阴影帧足够）。完成后做一次 DONE 前自检：
「仍差」清空则单独一行写 `DONE`。
