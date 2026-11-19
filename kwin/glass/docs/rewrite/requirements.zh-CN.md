# 液态玻璃插件重构:需求文档

状态:工作文档。除 Mica / per-shape 噪声 / 壁纸来源(FR-7、FR-9~11)外,其余能力已在
`kwin/glass/` 落地;各项实现约束与实测结论见
[pitfalls](pitfalls.zh-CN.md),协议的现行版本见
[protocol](protocol.zh-CN.md)。

## 1. 背景

原 `kwin/glass-effect`(已完成迁移并删除)源自第三方 Glass/Blur 分支,在保留上游业务的同时叠加了
KOS 的表面形状协议、refraction、glints、scrim 与材质透明度。结构性问题集中在:

- 每帧对整块背景跑完整 Kawase 链与全分辨率高斯,结果不复用;
- shape 几何动画时 `backgroundRect` 变化,纹理链整链重建;
- 噪声强度是全局的,无法 per-surface;
- QML 兜底路径对整场景做 `ShaderEffectSource` 采样;
- Material/Windows 材质只是"关掉液态",没有独立的材质语义;
- 没有壁纸来源材质(Mica),也没有指针驱动的光学反馈。

本次从底层重写,不 fork 旧实现。保留外部契约,替换内部结构。

## 2. 目标

- G1 液态玻璃是一等能力,视觉不弱于现版本。
- G2 代表性场景的模糊链路工作量相对现版本至少减半(>2x),以人工测量确认。
- G3 不降低 KWin 兼容性:6.6 / 6.7 / 6.8 Wayland,X11 保持可选。
- G4 材质家族化:液态、Material 磨砂、Windows Acrylic、Windows Mica/Mica Alt。
- G5 动画感知:几何动画期间不重建模糊链,不每帧重算。
- G6 现代材质:指针 hover 光、指针视差、per-shape 噪声与环境色。
- G7 外部契约不变:effect id、kcfg 组、配置模块、metadata、协议 id、安装路径。

## 3. 非目标

- 不接管客户端弹窗/窗口动画的所有权。
- 不在合成器里裁剪客户端内容的 squircle(内容遮罩仍由 QML 负责)。
- 不做高帧率动态壁纸的 Mica 实时刷新。
- 不承诺 HDR、广色域或特定 GPU 的数值指标。
- 不新增自动化 UI/渲染测试;验收一律人工。
- 不把 Dock 放大、按钮反馈等交互态搬进合成器。

## 4. 术语

| 术语 | 含义 |
| --- | --- |
| Shape | 一个表面内的一块玻璃区域,带几何、圆角、光学与材质参数 |
| MaterialProfile | 光学栈 + 底色来源 + 表面层的组合 |
| Optics | `liquid`(折射/glints/rim)或 `frosted`(只模糊) |
| BackdropSource | `live`(窗口下方实时背景)或 `wallpaper`(壁纸静态样本) |
| Cache | 以捕获域、背景损伤、材质签名为键的结果缓存 |
| Legacy adapter | 把旧 blur region、装饰、X11 atom、内部窗口属性映射成隐式 Shape |
| Closed fallback | 依赖不可用时退到不暴露额外信息的材质,而不是改变语义 |

## 5. 材质矩阵

| 材质 | Optics | 底色来源 | 噪声 | 用途 |
| --- | --- | --- | --- | --- |
| Liquid | liquid | live | 有 | macOS 主题,默认 |
| Soft | liquid(弱折射、高柔和度) | live | 有 | 柔和液态预设 |
| Material Frosted | frosted | live | 0 | Material 3 主题 |
| Acrylic | frosted | live | 细(1–2) | Windows 浮层、菜单 |
| Mica | frosted | wallpaper | 极细 | Windows 常驻窗口 |
| Mica Alt | frosted | wallpaper | 极细,更强染色 | Windows 变体 |
| Tonal | 无 | 无 | 0 | 协议不可用时的 QML 兜底 |

规则:

- 非液态 profile 不进入 `glass()` 光学分支,不是把折射强度设为 0。
- Mica 永远不显示窗口后面的应用内容;壁纸样本不可用时使用上一次样本或纯 tint,
  **不得**退回 live 背景。
- 噪声按 surface 设置,0 是完全关闭;全局 `NoiseStrength` 只作为液态默认值。
- Material 的 M3 表面色通过 fixed tint 承载,不新增协议色板。

## 6. 功能需求

**FR-1 Shape 模型(P0)**
一个 `wl_surface` 支持 N 个 shape;服务端已按 surface 保存 shape 列表,客户端桥接
必须支持每个 QML item 一个 shape。几何、圆角、指数、捕获域、材质、噪声、底色来源
均逐 shape 独立。v8 事务提交语义保持不变。

**FR-2 MaterialProfile(P0)**
材质由 Optics、BackdropSource、Tint、Noise、Scrim、Opacity 组成;插件按 profile
选择 shader 分支,不允许主题通过参数组合意外复活液态光学。

**FR-3 动画感知(P0)**
几何只变化(位置/大小/圆角)且捕获域不变时,模糊结果保持有效;动画期间不得因
`backgroundRect` 尺寸变化重建纹理链。捕获域优先使用客户端声明的
`captureGeometry`;未声明时,插件可在动画期间冻结为起止几何的并集。

**FR-4 结果缓存(P0)**
缓存状态至少为 `Invalid / Partial / Valid`;失效原因至少区分
`Geometry / Shape / Material / Backdrop / Output / Config / Wallpaper`。
纯材质变化不得使捕获失效;Mica 的壁纸来源不依赖背景损伤。

**FR-5 纹理池(P1)**
按输出与尺寸复用纹理,动画期间不做逐帧分配;池有上限并可回收。

**FR-6 损伤裁剪(P1)**
Kawase 各级 pass 按扰动区域裁剪;静止桌面与局部滚动不得跑整块背景。多个玻璃
窗口共享降采样前缀。

**FR-7 Per-shape 噪声(P0)**
协议 v9 增加 per-shape 噪声强度(0–100,与 kwinrc 同刻度);0 关闭。噪声必须
随材质透明度一起淡出,不得在静态背景上闪烁。

**FR-8 Material Frosted(P0)**
Material 主题下:blur + tonal tint + 可读性 scrim,无折射、无 glint、无 rim、
无噪声、无指针光。QML 只保留 state layer、文字和阴影;材质由合成器拥有。

**FR-9 Acrylic(P1)**
Windows 浮层:live blur + tint + 细噪声,无液态光学。

**FR-10 Mica / Mica Alt(P1)**
Windows 常驻表面:壁纸样本 + tint + 极细噪声;窗口移动时按屏幕坐标采样,
背景应用内容不参与;壁纸更新时按低频率刷新,锁屏/省电/无可见 Mica 时暂停。
Mica Alt 使用更强染色或独立的变体参数。

**FR-11 壁纸供给(P1)**
Shell 按输出上传低分辨率、正向、sRGB、不透明的壁纸样本(建议 512–1024 宽),
优先复用壁纸缩略图缓存。插件复制后持有 GL 纹理,不依赖客户端长期保活。

**FR-12 Hover 光(P2)**
仅 Liquid/Soft profile:指针进入 shape 外扩区域时,在指针附近产生镜面光瓣与
边缘透光;120–180ms 衰减;只重绘 shape 及其光晕范围;`reduceMotion` 时仅保留
静态光斑;可配置关闭。非液态 profile 不启用。光斑半径可配置
(`HoverLightRadius`,逻辑 px,0 = 按面板尺寸自适应),强度走 `HoverLightStrength`;
是否启用由协议 v9 逐 shape 掩码决定,shell allow list 默认只开 dock、右键菜单、
控制中心。

**FR-13 指针视差(P2)**
同一指针 uniform 小幅偏置折射/高光方向;与 hover 光共用开关与重绘策略。
位移只加在边缘折射带(按 `edgeFactor` 权重),不得平移整块背景,否则面板像
一张图跟着指针游;掩码 bit 1。

**FR-14 主题映射(P1)**
`macos → Liquid`;`material → Material Frosted`;`windows12` 常驻窗口 `Mica`,
浮层 `Acrylic`。主题选 profile,用户预设只在 profile 内调强度,不能跨 profile。

**FR-15 QML 兜底(P2)**
非 KWin 会话保留 `LiquidGlassSurface` 路径,并新增 Material/Mica 的近似实现;
协议可用时不得同时绘制 QML 材质层。

**FR-16 兼容层(P0)**
所有 KWin 版本差异集中在 `compat` 层;业务代码不得散落 `#if`。X11 atom、
Wayland blur region、装饰 region、内部窗口属性继续映射为隐式 shape。

**FR-17 清理(P2)**
删除重写后不再承载的外部业务(静态模糊旧字段、未读配置、重复 region 计算),
但保留 provenance、许可证与外部契约。

**FR-18 点击光(P2)**
左键按下时从点击点向外的扩散脉冲,只在该 shape 启用掩码 bit 2 时渲染。
`ClickLight` 可关,`ClickLightStrength` / `ClickLightRadius` /
`ClickLightDuration` 分别控制亮度、范围与时长;与 hover 共用 16ms 定时器,
`animationTimeFactor()==0` 时不发脉冲。脉冲是场景坐标上的全局时钟,多个面板
各自按其掩码渲染同一脉冲。

## 7. 非功能需求

**NFR-1 性能**
- 静态桌面、单个玻璃面板场景:单帧模糊链路工作量目标 ≤ 现版本的 1/2;
- 弹窗/菜单开合动画:不得重建纹理链,不得每帧跑完整模糊链;
- 无光标移动、无内容变化时不得持续重绘;
- 缓存命中时单帧只允许最终材质 pass、必要的 scrim 与噪声;
- 以上以人工测量确认,文档不预填百分比。

**NFR-2 视觉**
Liquid 主题 A/B 对照:结构、亮度、颜色、折射形状不得有明显差异;允许边缘 1px
内的抗锯齿差异。其他 profile 按各自参考语义验收。

**NFR-3 健壮性**
缓存失效必须覆盖几何、形状、材质、背景损伤、输出、配置、壁纸;不得出现陈旧帧、
黑块、错位、泄漏。依赖缺失时 closed fallback。

**NFR-4 可观测性**
沿用日志分类;允许静态调试计数与诊断开关,不引入测试框架或断言式验收。

**NFR-5 资源**
纹理池、壁纸样本、噪声纹理均有上限;不逐帧分配;壁纸样本单输出一份。

**NFR-6 兼容**
6.6 / 6.7 / 6.8 三套 SDK 必须构建通过;X11 可选;旧客户端与旧服务端行为不变。

**NFR-7 流程**
验证 = 人工运行 + 构建/静态检查。不编写、不运行自动化测试;不为了验证启动
本机图形会话;VM 只走 `kos-vm`。

## 8. 外部契约(冻结)

- effect id:`glass`;kcfg 组:`Effect-blurplus`;配置模块:`kwin_glass_config`;
  metadata 名称与许可证不变;
- 协议 id:`kos_surface_shape_v1`,只追加版本,不重排 opcode;
- 安装路径与插件元数据不变;
- `kwinrc` 既有键名保持可读,新能力优先走协议;
- SPDX 与 provenance 保留。

## 9. 验收标准

| 阶段 | 人工可观察的通过条件 |
| --- | --- |
| 骨架 | 现有 Liquid 画面无可见变化;三版本构建通过 |
| 缓存 | 弹窗开合无掉帧感;静止桌面无持续重绘;滚动窗口背景实时更新 |
| 损伤裁剪 | 局部滚动/视频/多窗口重叠下无陈旧块、无撕裂 |
| Material | 无折射/glint/rim/噪声;换壁纸时 tonal 色不跳 |
| Mica | 应用窗口挡在后面时仍显示壁纸;换壁纸后更新;动态壁纸刷新有节流 |
| Hover | 指针进入/离开光斑连续;无光标移动时停止重绘;reduceMotion 生效 |
| 兼容 | 6.6/6.7/6.8 加载正常;旧客户端行为不变;X11 可选构建通过 |

不采用像素 diff、截图对比阈值或"截图通过"作为验收条件。

## 10. 风险与待确认

- **多 shape / 单 surface** 的服务端支持已确认;QML 侧多 shape 的实际合成顺序
  仍需在骨架阶段人工验证。
- **壁纸供给**:壁纸是 Quickshell 表面,不是 KWin desktop background;Mica 必须
  依赖 Shell 上传样本,不能用截屏。
- **指针 API**:`effects->cursorPos()` 在 6.6–6.8 的可用性与坐标系需实现时确认。
- **驱动差异**:GLSL 分支在目标 GPU 上可能未编译;依赖离线 shader 校验 + 人工运行。
- **运动中降级**是否肉眼可见,需要人工判断;不可见才允许作为默认。
- **Mica 语义**必须 closed fallback,不能静默变成 Acrylic。
- **动画所有权**:保持客户端动画,插件只做缓存与感知。

## 11. 假设

- Shell 是主题/profile 的唯一来源;
- 壁纸缩略图缓存可生成低分辨率样本;
- 用户接受人工验收,不要求自动化视觉回归;
- 重写期间允许一次性不兼容的内部接口调整,但外部契约冻结。
