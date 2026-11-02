# 窗口外观：实现与 VM 审阅

[English](WindowAppearance.md)

面向 AI 贡献者。源码在 `kwin/kos-bridge/windowappearance/`、`kwin/kos-decoration/`、
`kwin/glass-effect/`、`shell/native/surface-shape/`。按[开发指南](Development.zh-CN.md)只在 VM 构建安装，
原生插件改动后注销登录或重启。本文替代历史方案和审计过程记录。

## 窗口所有权与回退

Bridge 连续圆角通过 KWin `OffscreenEffect` 缓存**窗口自身内容**，裁剪完整 SSD/CSD 外框。
超椭圆指数为 `2 + 2 * smoothness`，不宣称复刻 Apple 私有曲线。
连续裁剪、内描边、可选外框、贴边/扩散阴影共用轮廓，不叠加原生圆弧描边/阴影。
`arc`/零 smoothness 使用原生描边和装饰器/图像阴影；应用自己已画掉的角和阴影无法恢复，需应用例外。

效果链 Glass → Dock/Stage → Bridge（20 → 50 → 100）。动画捕获已裁剪源；Bridge 不缓存后续动画输出或背景模糊。
连续窗口需透明遮挡语义，让裁角后背景参与绘制；为性能删除此标志可能造成黑角。
Glass 用真实视觉轮廓，不再次应用旧圆弧输入半径。

连续缓存预算 256 MiB 并检查 GPU 纹理上限，着色器/资源/几何/预算失败则记录原因并回退原生圆弧。
几何、缩放、配置、预算变化后重考虑拒绝项，不每帧反复分配。窗口删除或关闭效果时释放引用。
原生阴影 atlas 为 32 MiB LRU，活动引用及其他 GPU 资源不计其中，两者都不是合成器总显存上限。

Slide 将连续窗口裁剪到外框所触及的输出；着色器回退会绕过此判断，修改裁剪前先检查着色器错误。
GLSL 1.40 / GLES 3.00 已内置 `fwidth`，着色器头由 KWin 生成，不额外插入导数扩展。

Overview 和“展示窗口”的缩略图直接绘制场景项，绕过 Bridge 的绘制入口。
这些效果激活时，Bridge 在首次缩略图捕获前释放连续圆角缓存、恢复原生圆弧，包括此前隐藏的连续圆角窗口。
退出后正常绘制恢复连续圆角；Slide 仍保留按输出裁剪。

Glass 的 `overviewpreview.cpp` 在原生窗口缩略图也使用的 `WorkspaceScene::preFrameRender`
钩子中，按层序将 Desktop 表面和 Quickshell Dock 合成到各输出的 GPU 帧缓冲。
先以捕获的壁纸绘制有界 Glass，再绘制客户端内容；应用窗口不进入合成，继续由 KWin 排列和遮挡。
Qt Quick 纹理项覆盖原生 `DesktopBackground`（含桌面网格及顶部缩略图），让壁纸、组件和 Dock
共同缩放。重复面板缩略图临时置于透明视觉父项下，保留原生 QML 透明度绑定，
不修改实际客户端可见性、焦点或虚拟桌面归属。

通过 Qt 原生 OpenGL 导入及 GPU fence 共享纹理，不读回 CPU。桌面/面板像素、几何、透明度及形状
变动使捕获失效，未变化帧复用纹理。各输出 RGBA8 预览缓冲总计最多 128 MiB；Glass 临时缓冲和
原生缩略图另计。分配/渲染失败后本次概览保留原生预览，Qt Quick 软件渲染也回退。
退出、锁屏或特效销毁时恢复缩略图视觉父项并移除预览项；退出时释放隔离的 Glass 捕获缓存。
VM 验收进入/退出、手势取消、反复激活、多输出变动、动态组件内容及实际材质连续性。
`kos-glass.overview-panel-projection` 使用真实 Qt Quick 项检查原生透明度绑定连续性、重复投影、
恢复，以及场景项/特效销毁。

## 配置

`~/.config/kos/window-appearance.json` 为 schema 2，解析器兼容 schema 1 迁移。
源码目录 `window-appearance.example.json` 供查字段，保留用户规则并合并字段，不整份覆盖。
配置错误保留上次有效状态。应用匹配先完整 window class，再 desktop/resource 标识，不猜标题。

保留描边物理/逻辑像素及 schema-1 转换语义；阴影参数为逻辑像素的高斯 sigma，不是完整外延。
焦点过渡预留两态所需边距，有界重绘定时器空闲后停止。
全屏始终关闭 KOS 圆角/描边/阴影/按钮以覆盖输出，离开时恢复；最大化按配置。
裁剪不实现内容保护留白；Settings 提供部分外观控制，详细规则以解析器/示例为准。
调色板外观和应用覆盖不采壁纸，也不能恢复客户端已裁掉的内容。

## Surface-shape 协议

`kos-surface-shape-v1.xml` 定义版本协商，保留接口/操作码顺序。
v1–7 维持原即时行为；v8 通过 manager commit 在下一次 `wl_surface.commit` 锁存 pending 状态，绘制只读 committed。
检查原子批次及旧客户端。v8 显式几何即使空/隐藏也拥有表面，不回退整窗模糊；未声明普通窗口保留旧模糊路径。

圆角矩形携带几何、视觉圆角、scrim、连续模糊 sigma、材质透明度、展开/捕获参数。
染色透明度与背景模糊独立；材质透明度衰减完整效果。用显式形状元数据，不用 layer-shell namespace 猜测。
协议不承诺任意旋转路径或 Glass 所有全局光学设置均可按形状配置；v8 已支持液态/磨砂 profile 及独立染色，不标为未来计划。扩展现有协商协议，不再造传输层。

## 开销与验证

局部 damage 仍可能使整张窗口纹理失效，滚动/视频/缩放比静态缓存多一次绘制。
Bridge、Dock、Stage 可各持独立纹理，阴影遮挡最坏可能平方级。
几何、输出缩放、装饰器、规则变化需使缓存失效；可见动画仍引用源时不能提前释放。
没有测量不声称性能百分比、无泄漏、HDR 兼容或总 GPU 预算。

VM 覆盖 SSD/CSD、圆弧/连续、深浅及应用覆盖、焦点/堆叠、最大化/全屏、移动/缩放、最小化/还原/关闭、
动画中反向及跨输出工作区切换。检查黑角、双描边、旧帧、输入偏移、阴影脱离；条件允许检查混合缩放及配置重载。
离线 Bridge、真实 Wayland 读回、GPU 读回分别记录，缺失上下文明确跳过。
性能审阅采用静态/滚动/视频与多个窗口数量；真实合成器覆盖与三套 SDK 编译分开，见[发布流程](Releasing.zh-CN.md)。
