# 坑位与性能债台账

每条固定三态:**已规避 / 暂缓 / 待处理**。暂缓项不得在补刀时顺手引入第二次重算;
先记录,按阶段处理。原则:性能与稳定优先,宁可少一个视觉细节,不做每帧全链路重算。

## A. 已经在旧插件里踩过、新实现必须避开

| # | 坑 | 旧实现现象 | 新实现策略 | 状态 |
| --- | --- | --- | --- | --- |
| A1 | 几何动画时重建纹理链 | `backgroundRect.size()` 变化触发整链重建 | 捕获域按 64 逻辑像素网格量化;origin 变化只整块重填、不重建链 | 已规避(退避:网格跨界仍会重填;尺寸变化仍需重建) |
| A2 | 每帧整块背景跑完整链路 | 静止桌面也全量 Kawase | 结果缓存 + 背景损伤键;本帧未刷新捕获像素时复用 `framebuffers[1]` | 已规避(2026-11-18 事件驱动键,边界见 B13) |
| A3 | capture 只按窗口损伤 | 窗口滚动时背景未变也重算 | 捕获按 `deviceRegion` 与捕获域的交集裁剪 | 已规避 |
| A4 | 每级 Kawase 画整块 quad | 高分辨率下填充率浪费 | 每级按扰动区域传播并用 scissor 只画脏矩形;多窗口共享前缀仍未做 | 已规避(单窗口) |
| A5 | per-shape blur override 各自重跑整链 | 多级 override 时链数翻倍 | 先按层级排序,共享前缀,最后拷贝 | 已规避(按 (级数, offset) 分组:同配置的 shape 共用一条链,所有链共享 level 0 捕获;边界:不同配置仍是各跑一条整链,共享前缀未做) |
| A6 | 噪声单独 additive pass | 每个 shape 额外一次全屏混合 | 折叠进材质 shader,或按 profile 关闭 | 暂缓 |
| A7 | 全局噪声 | Material 也吃颗粒 | per-shape noise | 暂缓 |
| A8 | 每帧复制 shape 列表/region | `shapesFor()` 返回值拷贝、逐行构造 region | 只读视图/引用;region 用矩形并集 | 暂缓 |
| A9 | QML 整场景 capture | `ShaderEffectSource` 每实例重渲染背景 | 合成器多 shape;QML 只保留非 KWin 兜底 | 暂缓 |
| A10 | 纹理分配抖动 | 尺寸抖动导致反复 `GLTexture::allocate` | 纹理池 + 尺寸分档 | 暂缓 |
| A11 | 空 region 语义 | 空声明被当成整窗 blur | v8 显式空声明优先;未声明才走 legacy | 已规避(设计) |
| A12 | 过度圆角/双重圆角 | 遮罩与填充各圆一次 | 内容/玻璃共用同一 SDF 轮廓 | 已规避(设计) |
| A13 | 每帧 `setBorderRadius` | 与窗口自身圆角互相覆盖 | 只在值变化时写,记录原值 | 暂缓 |
| A14 | 旧 region/装饰/X11 适配重复计算 | 每条路径各算一遍 region | 统一成隐式 shape,只算一次 | 暂缓 |
| A15 | 6.6 损伤传播记账缺失 | 下层窗口(桌面菜单蒙层)重绘时把 dock 区域覆盖掉,dock 内容单帧消失/闪烁 | 恢复旧实现的两级记账:`m_paintedDeviceArea` / `m_currentDeviceBlur`,在 `prePaintWindow`(bottom→top)中把下层已绘区域回加到玻璃窗口的 `devicePaint`;该记账对每个窗口都要执行,包括无 shape 的窗口 | 已规避(2026-11-17;dock 闪烁最终根因见 A16,本项仍是 6.6 正确性必需) |
| A16 | onscreen pass 未按 `deviceRegion` 裁剪 | 窗口只被部分重绘时,整块 shape 的玻璃被重复混合在旧内容上(内容随后只在新损伤区重绘),dock 图标单帧被材质盖住 → 闪烁 | 与旧实现一致:先求 shape 设备矩形与 `deviceRegion` 各矩形的交集,按交集矩形建 onscreen quad;交集为空则不画。效果自绘发生在 `renderItem()` 之前,KWin 不会替效果设 scissor,必须自己裁 | 已规避(2026-11-17) |
| A17 | 单级大 offset 冒充"强模糊" | 旧强度表把半径押在第 3/4 级的大 offset(最大 8 texel,折合 128 px tap)上;实数上不是平滑低通:细内容被复制成几条离散重影,玻璃下的文字/滑杆出现条带,强度越高越像"重影 + 发虚"。旧 onscreen 又叠一次 9 tap 环形平均(无中心 tap,覆盖像素多 8 次采样)去遮,成本高且仍不干净 | 半径改用**级数**堆:6 级、每级 offset 1..2 texel(级边界处 `2.0@N ≡ 1.0@N+1`,像素半径连续)。合成阶段只取 1 次链结果。2026-11-17 对照图确认:旧表在动画内容(设置页滑杆)上有明显条带,新链为平滑云雾状,无重影 | 已规避(2026-11-17) |

## B. KWin 合成器 API 坑

| # | 坑 | 处理 |
| --- | --- | --- |
| B1 | 6.7+ 不要用 `data.setTranslucent()` 展开重绘 | 6.7 路径改用 BackgroundEffectItem 语义或保持不覆盖;6.6 用 devicePaint 展开 |
| B2 | `deviceRegion` 是 damage,不是可见区域 | 命中/可见矩形与世界状态解耦;每个被画矩形各自 clip,不要提前 return |
| B3 | render target 是 y-down | 采样/on-screen UV 按 y 翻转;不要对 `glReadPixels` 再翻 |
| B4 | viewport 坐标空间 | `mapToDeviceCoordinates()` 已含 renderOffset,不要再减 |
| B5 | 6.6 与 6.7/6.8 的 hook 签名不同 | compat 层统一 `#if`,业务代码不散落 |
| B6 | X11 可选 | X11 单独后端/宏,不污染 Wayland |
| B7 | 全屏效果/截图窗口 | 全屏效果期间跳过捕获;spectacle 等单独判断 |
| B8 | 插件加载失败会拖垮会话 | shader 失败即 `isActive=false`;每次资源分配判空 |
| B9 | 效果内改 `glScissor` 会污染后续合成 | 进入前 `glGetIntegerv(GL_SCISSOR_BOX)` + `glIsEnabled`,退出时原样恢复;scissor 是屏幕/帧缓冲坐标(y 从底部算) |
| B10 | 自绘 FBO 后 `glActiveTexture`/blend 状态残留 | 链末尾显式 `glDisable(GL_BLEND)`,纹理单元保持在 0(与上游一致) |
| B11 | KWin 6.6 注销时偶发 `Display` 析构崩溃 | 2026-11-17 观察到 1 次(3 次 relogin 中 1 次):`wl_display_destroy_clients → libkwin` 段错误,栈内无 glass 帧,判断为 KWin 自身关闭路径;若复现,用旧插件做 A/B 注销对照 | 观察中 |
| B12 | 增量链的 scissor 不能"恢复后不管" | 2026-11-18 定位:down pass 的局部脏区留下 `GL_SCISSOR_TEST=enabled` 和**上一级像素坐标**的 box;后续 up pass 若目标是整级(rectCount=1 且等于 full)就走进"整级直接画"分支,只按旧的 `hadScissor` 恢复而不关 scissor,于是整级 up 被裁到一个小角落 —— 表现就是"100% 强度不糊"+"随机块状瞬间很糊"。`drawLevel` 现在对整级绘制**无条件 `glDisable(GL_SCISSOR_TEST)`**,局部才设 box;链尾统一恢复入口状态。判据:同一帧 down 后/up 后读 `framebuffers[1]`,局部脏区窗口的 changedFrac 必须显著>0(修复前 0.2%/3.4%,修复后 47%/96%) | 已修 |
| B13 | 背景损伤键不能用绘制路径信号 | 链结果只依赖玻璃**下方**的像素。`EffectWindow::windowDamaged` 只在绘制路径发射(最小化窗永不发射),而 `deviceRegion` 不区分"下方变了"和"窗口自己重绘了"。改为连内部 `Window::damaged`(screencast 同款,每次客户端提交都发射),在回调里**只标 `backdropDirty` 不绘制**;窗口自己的损伤只跳过自己的链;另外把 `windowFrameGeometryChanged`、`stackingOrderChanged`、`desktopChanged`、`virtualScreenGeometryChanged` 与 windowAdded/Deleted 当保守失效源。按层序精确判断(`invalidateAbove`):只有**堆叠在玻璃上方**的窗口提交/移动/新建/删除才让该玻璃失效;层序重排只比较"各自下方的有序前缀",下方两个窗口互换也会正确失效;`windowDeleted` 时窗口已不在 stackingOrder 里,位置从缓存的上一次顺序(`m_stackingOrder`)解析,查不到则保守全失效。边界:不提交的 KWin 侧动画(壁纸插件、效果动画)不触发,6.7+ `BackgroundEffectItem` 路径同样未接;窗口在玻璃下方的整面提交(Qt 客户端每帧整面 damage)仍会逐帧失效 —— 客户端 damage 粒度,效果侧无解。2026-11-18 实测:蒙层/弹窗关闭时 dock 自身 33fps 整面提交不再重跑链(19s 扫描 run 396 / skip 385);层序判断后 12s hover 中上方弹窗(type 13/未知类型)hits=0、下方普通窗 hits=2/3;A/B(VM 上 25s 扫描)`KOS_GLASS_NOSKIP`=1 25.3/25.6% vs 关 25.6/25.9%,无可见差异 —— 链不是该机(vmwgfx)瓶颈,瓶颈是每帧合成与驱动提交 | 已落地 |
| B14 | 6.6 没有"缓存背景"语义 | 2026-11-18 核实:6.6.6 的 `scene/backgroundeffectitem.h` 是空壳(注释明确"isn't (yet) involved in any rendering of its own"),只扩重绘域;唯一能跳过下方绘制的入口是 `WindowPrePaintData::deviceOpaque`(`paintSimpleScreen` 里 `visible -= deviceOpaque`,且 `PAINT_WINDOW_TRANSLUCENT` 只有效果调 `setTranslucent()` 才会置位)。探针(hover 扫描中把 blurArea 加进 deviceOpaque):25.5% → 32%,两次一致,回滚。perf:68.6% kernel,其中 `vmw_fence_obj_wait_ioctl→dma_fence_wait` 占大头 —— 该机瓶颈是每次提交后的 fence 等待与 draw call 吞吐,不是像素填充率;"少画下方"这类像素级优化不可能兑现。真要收益只能减少 frame/draw 提交次数(客户端整面提交、每帧 draw call 数),已超出效果可控范围 | 暂缓(实测否定) |
| B16 | `EffectsHandler::mouseChanged` 不能作为指针位置来源 | 6.8 头文件注释仍写"要先 `startMousePolling`",但该函数已不在 `EFFECTS_HANDLER_EXPORT` 里,信号是否发射不可依赖。指针采样统一走 `InputEventSpy::pointerMotion`(context-menu 特效同款,6.6/6.7/6.8 都有),位置用 `effects->cursorPos()`;spy 在构造时安装、析构自动卸载,输入系统未就绪时 100 ms 重试 | 已落地(2026-11-18) |
| B15 | per-shape 链成倍增加每帧工作 | 每个不同的 (级数, offset) 各有一条 down/up 链;每窗口的内嵌表面(如 IME 面板 frost 18 + 内部卡片)会各自成链。旧实现按 gaussianKey 逐 sigma 跑高斯,成本同类。新做法:按 (级数, offset) 分组,同配置共用一条链并共享 level 0 捕获;每条链按自己的 tap 做增量脏区;本帧没用到的链在合成结束后释放。sigma 映射(按核算,不是拍脑袋):每级 9 tap tent 单 pass 在 level `i` 贡献 `0.79 * o * 2^i` 逻辑像素标准差,down+up 两遍 → 整链标准差约 `1.29 * o * 2^n`;取 `n = clamp(ceil(log2(sigma / 2.58)), 1, 6)`、`o = clamp(sigma / (1.29 * 2^n), 1, 2)`,σ=12 → n=3/o=1.16,σ=16 → n=3/o=1.55,σ=32 → n=4/o=1.55。`sigma = 0` 直接采样捕获 |

## C. Shader / 协议坑

| # | 坑 | 处理 |
| --- | --- | --- |
| C1 | GLSL 只在运行时编译 | 每次改 shader 先 `glslangValidator`;失败会导致 BlurEffect 半初始化并可能 abort |
| C2 | KWin 6.6 需要 `_core` shader 变体 | 生成同名 `_core` 资源;6.7+ 合并 |
| C3 | uniform 名拼错静默为 0 | C++ location 与 shader 声明逐项静态核对 |
| C4 | 新协议 request 插在 destroy 前会移动 opcode | 只追加在 interface 末尾;版本号同步 |
| C5 | QML `Timer` 等类型缺 import | 只 import Quickshell 的文件需显式 `import QtQuick` |
| C6 | `set_blur_sigma` 的 0 与"未声明"无法区分 | 客户端 `SurfaceShape` 默认 `blurSigma = 12` 且 v8 每次 sync 都发;QML 传 -1(继承全局)在客户端被 clamp 成 0,语义是"直接采样未模糊背景"。pre-v8 客户端从不发这条 request,值同样为 0,但必须沿用 blurLevel/全局。做法:`GlassShape` 加 `blurSigmaSet` 存在位,只在收到 request 时置位;效果侧优先级为 存在位→sigma(0=不模糊) → blurLevel → 全局 |
| C7 | 提升 global version 后忘了同步 `bindManager` 的 clamp | 2026-11-18 现场:v9 全局 + 客户端按 9 绑定,但 `bindManager` 仍是 `std::min(version, 8u)`,manager 资源被建成 v8;客户端发出 since=9 的 `set_pointer_effects`,服务端回 `invalid version ... (8, need at least 9)` 并断开整条 Wayland 连接。quickshell 靠 `QT_WAYLAND_RECONNECT=1` 才没继续崩,但重连后 glass shape 全部丢失 = 液态效果消失。改版本号时全仓搜 `std::min(version`;现在 clamp 用 `kos_surface_shape_manager_v1_interface.version` 自动跟随 |
| C8 | 共享卡片把 allow-list id 写死进组件 | `ControlCenterCard` 曾把 `pointerEffectsFor("controlCenter")` 写死在玻璃里,桌面组件复用同一卡片就继承了视差/hover/点击,表现为"组件背景跟着鼠标动"。allow-list 必须由宿主在装配点注入(`ControlCenterPanel.placeCard`),组件默认 0,选项默认关闭 |

## D. 本阶段(首个可渲染里程碑)主动接受的债

这些是本轮为了尽快恢复画面而**明确暂缓**的项,已按"不重复重算"的最低标准实现:

1. ~~**结果缓存是保守键**~~:已由 B13 的事件驱动背景损伤键取代;窗口自身内容提交
   不再重跑链;并按层序只失效"玻璃上方"的窗口,上方弹窗不再误失效。剩余保守面见 B13。
2. **捕获域按 64 逻辑像素网格量化**:跨网格边界仍整块重填;尺寸跨档仍重建链。
3. **每帧重新计算 region**:shape 数量少时可接受;A8 在缓存阶段一起处理。
4. ~~**忽略 blur sigma / 高斯**~~:已接入。sigma 映射到同一链条(见 B15 的推导):
   `n = ceil(log2(sigma / 2.58))` 级、每级 offset `sigma / (1.29 * 2^n)` 限制在 1..2 texel;
   `sigma = 0` 直接采样未模糊的捕获。视觉 sigma 对齐旧插件的真高斯,核形状是近似,不是同一个核。
5. ~~**忽略 scrim 与 tint 的完整语义**~~:已接入旧实现的 `adaptiveScrim` 曲线(cap/decay/黑|白),
   在 onscreen 合成阶段、tint 之后应用;无模糊 shape 用 5 tap 宽邻域 luma 代替旧插件的 1/16 亮度图。
6. ~~**忽略 per-shape blur level**~~:已接入;v8 客户端优先用 sigma,老客户端用 1..15 级,均未声明才回落全局配置。
7. **单输出缓存**:纹理按窗口缓存,未按输出分键。2026-11-18 静态核对:捕获、脏区与合成用的坐标约定与旧实现完全相同(捕获/脏区是全局逻辑 rect,device 坐标含 renderOffset,`blitFromRenderTarget` 内部映射),捕获纹理本身就是逻辑分辨率、与输出 scale 无关,所以共享一份缓存不构成正确性问题;旧实现按 output 分键只是为了省掉另一输出的重复刷新。**仍需真机实测**:双屏、混合 DPI、跨屏窗口。
8. ~~**无 reveal 动画**~~:2026-11-18 已接入协议 v7。`SurfaceShapeManager` 拥有可逆时间线
   (cubic ease-out,1..2000 ms,serial 回传),`shapesFor()` 同步缩放玻璃几何与圆角并乘
   `materialOpacity`;捕获几何固定为**最终** rect,否则逐帧缩小会重建捕获和模糊链。
   效果侧在 `drawWindow` 里只变换已合成的客户端内容(以形状底边中点为锚,scale 0.8→1,
   透明度随进度),`revealFrameChanged` 只重绘面板 + 采样 margin;`postPaintScreen` 之后
   才发 `reveal_finished`。QML 侧的 `compositorRevealEnabled` 管线早已存在,但当前没有
   面板主动启用(启动器曾用,后按"静止淡出"方案改回)——这是 shell 的产品决策,不是
   合成器缺口。
9. ~~**无 KCM**~~:2026-11-18 新增 `kwin/glass/src/kcm/`(`kwin_glass_config.so`,安装到
   `kwin/effects/configs`)。只暴露新效果真正读取的键:BlurStrength/Finetune/饱和度补偿、
   折射/边缘/软材质、HoverLight/Strength/Radius、PointerParallax 与 ClickLight/
   Strength/Radius/Duration;保存后经 KWin Effects
   D-Bus 触发 `reconfigureEffect("glass")`。KCMUtils 或 KWinDBusInterface 缺失时整页跳过,
   效果本身照常构建。

首轮实现落地后新增的已知债(按"可能增加每帧工作"排序):

10. ~~无液态光学~~:已实现边缘/体部折射透镜、双边缘 rim/glint 与 soft 材质扩散,
    参数读取 `[Effect-blurplus]`;`effect=1`(Frosted)只做模糊 + tint,不进入光学阶段。
11. ~~无饱和度补偿~~:已在最终 up pass 按旧实现的 luma 加权曲线补偿(`kSaturationCompensation=1.296`,
    只加一次、只改该 pass 的逐像素运算);数值暂为常量,等 KCM 落地后接配置。
12. ~~固定 4 级链~~:已读取 `[Effect-blurplus]` 的 `BlurStrength`(1..15)/`BlurFinetune`(0..10)/
    `BlurSaturationCompensation`。强度到半径的映射按 A17 改为**级数 + 小 offset**:
    6 级上限、每级 1..2 texel(15 档 → 3,3,3,2,2,2 分配),`BlurFinetune` 只做整体缩放。
    纹理按需分配实际级数;静态场景仍由增量脏区裁剪保持接近零成本。
    per-shape `blurSigma` / `blurLevel` override 已接入(A5/B15)。
13. **捕获域固定外扩 160 逻辑像素**:小于旧插件最大 expand(150)之外没有动态计算;贴屏边时被裁,边缘会出现 clamp。
14. **6.7+ 只靠 `BackgroundEffectItem` 展开损伤**:未额外覆盖 `prePaintWindow`。item 在 shape 首次提交后才创建,首个动画帧可能吃到旧背景(拖影)。
15. **空损伤直接跳过整个渲染**:`deviceRegion` 为空时不再重复合成(避免半透明材质双重混合)。
16. **窗口变换时整窗跳过**:见 19 —— 与旧插件默认一致(同时跳过,不会错位)。
17. **shape 全部移除时 item 不回收**:`updateItem` 在空列表时直接返回,旧 item 的损伤域会残留到窗口销毁;不产生错误像素,但会多扩一点重绘。
18. ~~**6.6 的 `prePaintWindow` 外扩量直接按逻辑像素加到 device region**~~:已修(2026-11-18),外扩先按 `view->scale()` 换算成设备像素再加到 `deviceRegion`;捕获域本身仍是逻辑像素,与旧实现一致。
19. **窗口变换期间不画玻璃(与旧插件默认一致)**:2026-11-18 核对,旧插件的 `shouldBlur` 同样在缩放/平移窗口上返回 false(`blur.cpp:1484`),只对 `WindowForceBlurRole` 破例。该 role 的实际使用方(上游 KWin 源码检索,2026-11-18):Slide(桌切,只平移所以对全部窗口置位)、Present Windows(窗口展开,对窗口置 true、对 dock 置 false)、Maximize(最大化动画期间置位并在结束时恢复);Magic Lamp 不使用;Overview 未查到设置证据。KOS 现状:玻璃只发布在 shell 自己的面板/Dock/弹窗上,它们不参与最大化/Present Windows;只有桌切 Slide 可能平移面板(Dock/Bar 是否随滑取决于 KWin 的 Slide 行为,需人工看一眼)。所以影响面接近零,但未实测。**2026-11-18 已按旧插件补上变换跟随**:窗口带 `WindowForceBlurRole` 时不再跳过,shape 几何按与 KWin 相同的变换(以窗口场景位置为锚缩放,再平移)映射,捕获域与 onscreen quad 都用变换后的几何;不带 role 的窗口仍跳过(与旧插件默认一致)。性能上界:变换帧捕获 rect 仍走 64px 网格量化,原点/尺寸跨格才整块重填或重建链,同一格内平移只改 UV、不重算;最坏情况出现在 Slide/Present Windows/Maximize 期间,每个受 role 驱动的玻璃窗口每次跨格一次全捕获 blit + 全链。6.6 的 `prePaintWindow` 记账仍用未变换几何(旧插件相同),变换效果自身会请求全屏重绘。sigma 不随变换缩放(与旧插件一致)。已补旧实现里真正影响 KOS 的那一条:`kwin/dock-window-animation` 通过数据 role `0x4b4f5342`("KOSB")驱动材质淡出,新插件现在读取它并乘进 modulation(与旧 `blur.cpp:2232` 一致),最小化/还原动画里玻璃随动画淡出而不是停在原地。剩余差异仅是 KWin 自带全屏效果下旧实现会画玻璃,保留跳过。
20. **窗口 opacity 直接平方进材质**:沿用旧实现的 `opacity*opacity`,保证关窗淡出时玻璃不残留;Dock 动画另有 `KOSB` role 的材质淡出(见 19)。
21. **共享前缀未做**:每个玻璃窗口各自一条 down/up 链;同帧多窗口没有共享降采样结果。
22. **液态光学成本**:onscreen pass 加入逐像素折射采样(色散开启时 3 次纹理读取)与
    边缘光计算;没有新增 pass,也不影响模糊链缓存,但玻璃覆盖的每个设备像素成本上升
    (旧实现相同甚至更高:旧实现在折射时另做 4 次 SDF 求值,本实现保持同样做法以对齐
    观感)。scrim 已接入(scrim 亮度的 5 tap 只用于无模糊 shape);噪声、全局 colorMatrix
    (亮度/对比度/饱和度)仍不做。
23. **指针光与视差(新增,2026-11-18)**:只对 `effect=0`(Liquid/Soft)生效,Frosted 不参与。
    指针采样走 `InputEventSpy::pointerMotion`(与 context-menu 特效同款),不依赖
    `EffectsHandler::mouseChanged`(6.8 头文件已无 `startMousePolling`,不可假设它会发)。
    悬停值由 16 ms 定时器推进,快进(τ≈45 ms)慢出(τ≈150 ms),全部窗口收敛后立即停表;
    每帧只改 onscreen uniform 并 `addRepaint` 形状矩形 +4 px,**不**失效捕获/链。
    `animationTimeFactor()==0` 时改为静态光斑。视差在上采样阶段给 lens shift 加至多
    2 个捕获 texel(4 逻辑像素),并用 `smoothstep(edgeFactor)` 限定在边缘折射带内——
    **不要**加到整个 lensShift 上,否则整块面板的背景会跟着指针滑动,观感像一张图在游。
    hover 光半径可由 `HoverLightRadius`(逻辑 px,0=自适应)控制,强度仍走
    `HoverLightStrength`。点击光(2026-11-18)由 `InputEventSpy::pointerButton` 触发,
    单条全局脉冲(场景坐标 + 时钟),半径/强度/时长读 `ClickLightRadius`/`Strength`/
    `Duration`;与 hover 共用 16 ms 定时器,只在 `effect=0` 上渲染,`animationTimeFactor()
    ==0` 时直接不发。协议 v9 的 `set_pointer_effects(flags)` 把三者做成逐 shape 掩码
    (bit0/1/2),旧客户端不发送时默认 0x7;shell 侧由
    `AppearanceConfigService.pointerEffectsFor(id)` 决定哪些面板开启(默认
    dock/contextMenu/controlCenter),其余面板的 shape 传 0,合成器不再为其重绘。
    边界:指针每次移动都会遍历 `m_render` 求 shape 命中,窗口数多时是
    O(窗口数),当前 shell 场景(个位数)可接受;点击脉冲每 tick 重绘所有玻璃窗口(同上)。

## E. 补刀规则

- 任何"顺手修一下"的改动,先问:是否新增每帧全屏 pass、是否让缓存失效、是否增加一次纹理分配?
- 三者任一为是,先记入本台账,不当场做。
- 视觉细节只在缓存与损伤裁剪稳定后加;加之前先证明不会让静态场景多跑一遍。
- 发现新坑,先补台账,再改代码。

## F. 插件级成本结账(2026-11-18)

方法:同一台 VM、同一负载(dock 20s hover 扫描)、每次重新登录后的同一会话状态,
`perf record -F 199 -p kwin_wayland` 取 16s,`perf report --sort dso` 的 **Children**
列 = 调用栈经过该 .so 的采样占比(把 glass 发起的 gallium/kernel 调用算在插件头上)。

| 指标 | 旧插件(glass.so.oct19) | 当前实现 | 比值 |
| --- | --- | --- | --- |
| glass.so Children(插件可归属 CPU) | 4.49% | 1.38% | **3.3x** |
| glass.so Self | 0.56% | 0.46% | 1.2x |
| kwin 总 CPU(两次均值) | 27.0 / 27.6% | 25.4 / 26.3 / 26.2 / 26.3% | ~1.04x |
| libgallium Children | 64.4% | 61.8% | — |

结论:插件可归属成本已降到旧插件的 ~1/3(>2x 目标达成);整机只快 ~4–5%,
因为插件只占总 CPU 的 1.4%,剩下 ~78% 是内核(wmwgfx fence 等待)与合成本身。
继续在效果侧做像素级优化不会改变整机数字,见 B14。
