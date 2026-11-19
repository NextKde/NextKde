# 开发步骤与验证步骤

状态:工作文档。按阶段迭代,每阶段结束汇报并停下,不自动接力。

## 0. 工作规则

- 不编写、不运行自动化测试(单元/集成/UI/截图对比/headless 渲染)。
- 验证 = 人工运行 + 构建/静态检查。构建放后台;单条命令 ≤ 1 分钟。
- 不为了验证启动本机 quickshell/kwin_wayland;需要运行时验证时走 `kos-vm` skill:
  `sync → build → install → relogin → shot`,插件改动必须 `relogin`。
- 临时日志、截图、ledger 放 `tmp/glass-rewrite/<阶段>/`。
- 每阶段先编译,再人工验收;不通过不进入下一阶段。

## 0.1 目录策略

- 新实现只位于 `kwin/glass/`,从空目录开始,不复制旧树的代码、注释或文档。
- 旧树 `kwin/glass-effect/` 已完成迁移并从仓库删除;`kosctl` 与 CI 只构建/安装 `kwin/glass/`;
  功能对齐后整体删除。
- 构建、安装与 CI 入口已指向 `kwin/glass/`;回滚靠 revert 入口提交,不保留双架构。
- 旧树的自动化测试暂留在根 CMake,直至新树有对应覆盖或旧树删除;它们不链接新插件。
- 第一阶段只验证构建与加载,不安装到桌面;首次安装放在第一个可渲染里程碑之后。
- VM 安装会清理旧树遗留的 `kwin_glass_config.so`、locale 与旧 `glass.so`。
  新 KCM 尚未实现前,设置页的 Glass 配置项不可用;首次正式安装必须补上
  config module,或在台账中明确记录该缺口。

## 1. 阶段 0:基线与行为台账

目标:在改代码前固定"不能丢的行为"和"现在有多慢"。

产出(写入本文附录或 `tmp/glass-rewrite/baseline/LEDGER.md`):

- 现有 KOS 行为台账:
  - 多 shape / 单 surface;
  - v8 事务提交与空声明;
  - 自适应 scrim 曲线与固定 graphite/pearl;
  - material opacity 对完整效果的淡出;
  - per-shape blur level / sigma;
  - captureGeometry 与 reveal;
  - 旧 blur region、装饰、X11 atom、内部窗口属性的映射;
  - dock/bar/popup 的现有动画路径。
- 人工基线:静态桌面、菜单开合、滚动窗口、视频、多输出、分数缩放各记录
  一次观感与资源占用;不写百分比结论。

停止条件:台账缺项说不清"哪些行为必须保留"。

## 2. 阶段 1:架构骨架

目标:替换内部结构,外部行为不变。

新增(建议路径,可在实现时调整):

- `src/glassshape.{h,cpp}`:Shape 值对象与生命周期;
- `src/materialprofile.{h,cpp}`:Optics / BackdropSource / Tint / Noise;
- `src/backdrop.{h,cpp}`:live 捕获与壁纸来源的统一接口;
- `src/glasscache.{h,cpp}`:缓存状态与失效原因;
- `src/texturepool.{h,cpp}`:按输出/尺寸复用;
- `src/compat.{h,cpp}`:唯一的 KWin 版本 `#if` 区。

要求:

- effect id、kcfg 键、metadata、协议、安装路径不变;
- 业务代码不再直接散布版本分支;
- 旧适配器(region/decoration/X11)产出隐式 Shape。

静态门:6.6/6.7/6.8 构建;shader 离线校验;`git diff --check`。

人工门:现有 Liquid 主题在静态桌面、菜单、Dock、Bar 上与阶段 0 对照无明显差异。

停止条件:出现无法用现有协议表达的旧行为。

实现状态(2026-11-17):阶段 1 的最小可渲染子集已落地。

- `glassshape.h` + `surfaceshapemanager.{h,cpp}`:v8 协议服务端与不可变 Shape 快照;
- `glass.cpp` / `glass.h`:捕获、4 级 Kawase、圆角 SDF、tint 与 material opacity;
  KWin 版本分支目前只在 `glass.h`/`glass.cpp` 的 hook 声明与 `#ifdef` 中,
  `compat.*`、`materialprofile.*`、`backdrop.*`、`glasscache.*`、`texturepool.*`
  尚未拆出,等阶段 2/3 再按职责迁移,避免为拆而拆;
- 构建门:宿主 KWin 6.8 与 VM KWin 6.6 均编译通过;生成的 5 个 shader 经
  `glslangValidator` 离线校验;
- VM 人工观察:Dock 与左侧卡片恢复背景模糊;系统设置窗口本身不是 KOS 表面。
  未验证:高速动画下的拖影、多输出、HiDPI、缩放动画。
- 液态光学已接入(阶段 3 之后补):onscreen pass 实现边缘折射透镜、体部透镜、
  双边缘 rim/glint 与 soft 材质扩散;参数读取 shell 已写入的 `[Effect-blurplus]`
  kwinrc 键(`theme.sync-glass` 契约不变),`reconfigureEffect("glass")` 即时生效。
  scrim、噪声、全局 colorMatrix 仍未接入。

阶段 1 没有拆出新文件是刻意选择:当前渲染逻辑只有一条路径,先保证行为,
阶段 2 引入缓存/捕获域时再按文档拆分,避免空壳抽象。

## 3. 阶段 2:捕获稳定化与结果缓存

目标:几何动画不重建模糊链,静止画面不重算。

实现要点:

- 捕获域 = 客户端声明的 `captureGeometry`;否则动画期间冻结为起止几何并集;
- 缓存键:`output + captureRect + backdropDamage + materialSignature`;
- 失效:`Geometry / Shape / Material / Backdrop / Output / Config / Wallpaper`;
- 纯材质变化不失效捕获;纯平移在固定捕获域内只改最终 pass;
- 纹理池替代逐帧分配。

静态门:三版本构建;uniform/配置交叉检查。

人工门:

- 菜单/面板开合动画:无掉帧感、无纹理闪烁、无边缘错位;
- 静止桌面:无持续重绘;
- 窗口滚动/视频:玻璃内容实时更新,无陈旧块;
- 快速反复开合:无残留、无累积延迟。

停止条件:出现陈旧背景或缓存命中导致画面不更新。

实现状态(2026-11-17):部分落地。

- 捕获域按 64 逻辑像素网格量化(`stableCapture`);纯平移只要不跨网格就不重建链,
  跨原点时整块重填一次而不是重建;
- 结果缓存:`captureRect` 未变且本帧没有向 texture0 blit 任何像素时,复用
  `framebuffers[1]`,跳过 4 级链;材质/tint/opacity 变化不影响该缓存;
- `deviceRegion` 为空直接跳过合成,避免半透明材质重复混合;
- 未做:纹理池、按 output/config/wallpaper 显式失效(目前靠尺寸/原点/损伤间接覆盖)。
- 已知缺口:缓存键是保守的——KWin 不提供"下方背景损伤"的独立来源,窗口自身
  内容动画仍会让捕获域内出现损伤并重跑链。要真正只按背景损伤失效,需要在
  阶段 3 的下层遍历里累积损伤。

人工观察:VM 上仍为同一 Dock/卡片模糊效果,静态画面无闪烁;把系统设置窗口
移到 Dock 下方后截图,Dock 内未见陈旧的壁纸块(但 4 级模糊下无法逐像素确认
底色已切换,需要人工看动画)。

## 4. 阶段 3:损伤裁剪与共享前缀

目标:静止/局部变化时只处理脏区。

实现要点:

- Kawase 各级 pass 按扰动区域裁剪;
- 同帧多个玻璃窗口共享降采样前缀;
- 被不透明窗口完全遮挡的部分跳过;
- 保持 `deviceRegion` 与几何/命中矩形解耦。

静态门:三版本构建;shader 校验。

人工门:局部滚动、视频、窗口重叠、多输出、分数缩放;无条纹、无错位、无陈旧块。

停止条件:任一场景出现可见伪影。

实现状态(2026-11-17):单窗口部分落地。

- 每帧从 `dirty`(deviceRegion ∩ capture)构造 level 0 脏区,向下每级扩 4 texel、
  除以 2 后取整,向上每级扩 25 texel、乘 2;只在这些矩形内画 down/up pass;
- scissor 进入前保存、退出后恢复,避免污染 KWin 后续合成;
- 未做:同帧多窗口共享降采样前缀、被不透明窗口完全遮挡的裁剪;
- 已完成的本轮审查修复:删除未使用的 `captureRect`/`ownsGeometry`/`removeShape`;
  manager 析构不再泄漏 ShapeResource;shape 全部隐藏时回收 `BackgroundEffectItem`
  但保留纹理链。
- 饱和度补偿:最终 up pass 按旧实现的 luma 加权曲线提升饱和度(`1.296`,默认
  finetune 下的旧值);只多一次 uniform 更新与逐像素分支,不新增 pass,不使缓存失效。

人工观察:VM 上 Dock 时钟按秒刷新时,局部链更新未见矩形接缝;与全量链截图
对照,背景观感一致。

## 5. 阶段 4:Material Frosted 与 per-shape 噪声

目标:Material 主题成为独立材质,而非"关掉液态"。

实现要点:

- 协议 v9:`set_noise`;Material 固定 0,Acrylic 1–2,Mica 极细;
- Material 主题:`paintInQml = false`,tint 由插件承担,QML 只保留内容层;
- QML 液态 overlay 在非液态 profile 下不实例化;
- 主题映射:`material → Material Frosted`。

静态门:三版本构建;协议 opcode 顺序核对;QML 枚举与 C++ 一致。

人工门:

- 任意壁纸下无折射、glint、rim、扫光、噪声;
- 换壁纸/开合菜单时 tonal 色不跳;
- 文字可读性 scrim 在亮/暗壁纸均正常;
- 与阶段 3 前的 Liquid 主题互不串味。

停止条件:非液态 profile 仍出现任何液态光学。

## 6. 阶段 5:Acrylic 与 Mica

目标:Windows 材质家族。

实现要点:

- 协议 v9:`set_backdrop_source`、manager `set_wallpaper`;
- Shell 按输出上传低分辨率壁纸样本(复用缩略图缓存);
- Mica:wallpaper 来源 + tint + 极细噪声,closed fallback;
- Acrylic:live 来源 + tint + 细噪声;
- windows12 常驻窗口用 Mica,浮层用 Acrylic;
- 动态壁纸低频率刷新;锁屏/省电/无可见 Mica 时暂停;
- 输出增删与多输出映射。

静态门:三版本构建;协议生成表核对;壁纸 buffer 校验路径复查。

人工门:

- 应用窗口挡在 Mica 窗口后面:Mica 仍显示壁纸,不显示应用内容;
- 换壁纸后常驻窗口更新;动态壁纸刷新有节流;
- 多输出各自壁纸正确;输出热插拔无黑块;
- 壁纸样本缺失时保持上次样本或纯 tint,绝不变成 Acrylic;
- Acrylic 浮层背后内容实时变化且噪声细腻。

停止条件:出现 Mica 显示后方窗口、错输出、或每帧重算。

## 7. 阶段 6:Hover 光与指针视差

目标:现代材质反馈,且不破坏缓存收益。

实现要点:

- 合成器读取指针位置,逐 shape 传 uniform;
- 仅 Liquid/Soft profile;指针进入 shape 外扩区域才请求局部重绘;
- 离开后用 120–180ms 衰减到 0;
- `reduceMotion` 关闭动态,只保留静态光斑;
- 可配置强度,0 关闭;
- 与缓存协同:hover 只重跑最终 pass,不失效模糊结果。

静态门:三版本构建;shader 校验;指针 API 版本适配。

人工门:

- 指针进入/离开/快速移动光斑连续,无跳变;
- 无光标移动时停止重绘(观察资源占用);
- 多个玻璃表面同时存在时行为独立;
- Material/Mica 不出现镜面光瓣;
- reduceMotion 与关闭开关生效。

停止条件:出现持续重绘或明显 CPU/GPU 占用上升。

## 8. 阶段 7:清理与文档

- 删除重写后不再使用的上游业务与未读配置;
- 保留 provenance、SPDX、许可证;
- 更新
  [Window appearance](../../../../docs/WindowAppearance.md)、
  [插件 README](../../README.md) 与配置说明;
- 将本目录文档中已实现的部分提升为正式架构页(中英配对),计划性内容留在本目录。

## 9. 验证步骤

### 9.1 静态门(允许,且是构建步骤)

- 三套 SDK 构建:6.6 / 6.7 / 6.8;
- GLSL 离线 `glslangValidator`;`.qsb` 按项目约定烘焙;
- 协议只追加检查:新 request 在末尾、`destroy` opcode 未移动、`since` 正确;
- `uniformLocation` 与 shader 声明逐项比对;
- kcfg 键 ↔ settings ↔ 设置页 ↔ kwinrc 键名;
- QML 属性/枚举 ↔ C++/协议;
- `git diff --check`;文档相对链接存在。

这些只能证明"可编译、静态自洽",不证明运行时正确。

### 9.2 人工运行时清单

| 场景 | 观察点 |
| --- | --- |
| 静态桌面 | 无持续重绘;玻璃稳定;无闪烁 |
| 菜单开合 | 动画连贯;无纹理重建尖峰;无边缘错位 |
| 菜单快速反复 | 无残留、无累积延迟、无黑块 |
| 窗口滚动/视频 | 玻璃后内容实时更新;无陈旧块 |
| 窗口重叠 | 遮挡区正确;无重复模糊或漏模糊 |
| 多输出/分数缩放 | 各输出正确;无错位、无拉伸 |
| 亮/暗壁纸 | scrim 与文字可读性正常 |
| Material 主题 | 无液态光学;无噪声;tonal 色稳定 |
| Acrylic | live 背景 + 细噪声 |
| Mica | 不显示后方窗口;换壁纸更新;动态壁纸节流 |
| 输出热插拔 | 无黑块;壁纸重新映射 |
| Hover | 光斑连续;离开衰减;无持续重绘 |
| reduceMotion | 动态光关闭;动画降级 |
| 锁屏/省电 | Mica 刷新暂停;无异常占用 |

### 9.3 性能对比方法

- 同一机器、同一分辨率/缩放、同一壁纸与窗口组合;
- 场景固定:静止桌面、菜单开合、滚动窗口、视频播放;
- 记录观感、帧 pacing 与现有系统级资源数据;不预填百分比;
- 结论只写"观察到/未观察到",与阶段 0 基线对照。

### 9.4 VM 流程

- 只走 `kos-vm` skill;
- `sync → build → install → relogin → shot`;
- 插件改动必须 `relogin`;禁止 `loginctl terminate-session`;
- `shot` 只产出供人看的图,不作断言或交付条件。

### 9.5 失败处理

- 先拿到完整失败输出;禁止在看不到报错时沿链路猜;
- 做最小差分:能用/不能用两条路径,列出差异;
- 同一问题最多连续验证 2 个假设,第 2 个被推翻后整理 A/B/C 交人工;
- 排查超过 5 分钟或约 10 次工具调用必须汇报:已确认事实/已排除/当前假设/下一步;
- 结论被推翻时先列作废结论,再继续。

## 10. 每阶段完成定义

1. 三版本构建通过;
2. shader 与协议静态核对通过;
3. 对应人工清单通过;
4. 无新增编译警告;
5. 文档/台账更新;
6. 汇报"已改 / 仍差 / 需要你",然后停下等指示。

## 11. 待定事项

- 运动质量调节器是否默认开启(需人工判断是否可见);
- Mica 动态壁纸刷新频率与省电阈值;
- Material 是否完全移除 QML tonal 底板(取决于 Stage/Dock 的 state layer 迁移);
- 多 shape 同 surface 的合成顺序验证方式;
- X11 路径是否进入本轮验收范围。

## 附录 A:现有行为台账(待阶段 0 补全)

| 行为 | 现状位置 | 重写后要求 |
| --- | --- | --- |
| 多 shape / surface | `SurfaceShapeManager::m_shapes` | 保留 |
| v8 事务提交 | `commit` | 保留 |
| 自适应 scrim | `onscreen_rounded.glsl:adaptiveScrim` | 保留 |
| 固定 graphite/pearl | scrim decay 编码 | 保留 |
| material opacity | `set_material_opacity` | 保留 |
| per-shape blur | `set_blur` / `set_blur_sigma` | 保留 |
| captureGeometry | v5 | 保留并用于动画稳定化 |
| reveal | v7 | 保留 |
| 旧 region/装饰/X11 | `updateBlurRegion` | 保留为隐式 shape |
| 全局噪声 | `settings.general.noiseStrength` | 变为默认值,可被 per-shape 覆盖 |
