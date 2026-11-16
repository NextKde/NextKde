# 壁纸架构

[English](WallpaperArchitecture.md)

面向 AI 贡献者。壁纸失败不能阻塞 Shell/Dock 启动。[深度引擎](DepthEngine.md)负责模型/worker，
[主题格式](ThemePackFormat.zh-CN.md)负责 host 契约，本文负责运行编排。
[动态壁纸设计与扩展指南](WallpaperDesignAndExtension.zh-CN.md)记录视觉目标、社区技术取舍、当前 shader 架构、新增主题步骤及未来渲染路线。

## 所有权

- `WallpaperService.qml` 管原图、模式、过渡、最近使用、轮播和接管；`WallpaperImageLayer.qml` 按输出绘制，限制过渡纹理并延后清理。
  不为局部动画强制全局 Qt 渲染循环。
- `WallpaperPreviewService.qml` 管多输出可取消草稿：Enter 确认，Esc/关闭取消；与已确认状态隔离。
- `SpatialWallpaperService.qml` 请求素材，`DepthWallpaperLayer.qml` 显示；失败保留普通壁纸。
  壁纸保留 `desktop` layer-shell scope，独立组件表面使用 `dock`，让原生概览捕获壁纸而非透明组件。
  两者保持 Bottom 层，见[桌面表面归属](DesktopIcons.zh-CN.md#桌面表面归属)。
- `WallpaperColorSource.qml` 取原图调色，`PlasmaWallpaperAdapter` 管 Plasma 和强调色元数据。
  Settings 经 `wallpaper-settings` → 平台 `wallpaper.plasma.*`、`wallpaper.preview.desktop`；QML 不直调 Plasma D-Bus/推理。

## 接管和能力检查

显式接管，各输出图像/调色就绪后，平台先备份逐屏原图到 `~/.local/share/kos/plasma-wallpaper-backup.json`，再设置小黑白占位图。
关闭时恢复，失败保留 Plasma 并报告错误。根据当前 ShellPackage 定位配置，不固定 appletsrc；预览结束恢复原 KWin 显示桌面状态。

`platform.ping` 能力决定预览/接管/空间资源入口。连接成功但版本旧时提示升级/不可用，不发未知操作。
断连保留窗口/桌面快照，重连再订阅；壁纸不重建 Dock 模型。当前各屏共享普通图片，无跨屏长图拼接。

## 异步准备和资源所有权

服务/组件页通过独立 worker 初始化固定 SHA256 校验的 ONNX 模型，成功后才持久化启用。
核心安装不下载模型，缺模型不影响普通图像/颜色/轮播。
`spatial.status` 下载报告字节进度，处理阶段用不定进度。
`spatial.cancel` 终止待处理和临时下载，任务代次拒绝迟到响应；取消不计崩溃冷却，完整已验模型可复用。

生成缓存上限 2 GiB，内部 `spatial.clear` 只接受 `generated`/`models`/`all`，先停 worker/渲染再刷新状态。
删模型关闭服务，清生成素材保留模型。URL/hash 以 `ModelManager.h` 为准，不假定已迁未来仓库。
完整推理与 worker 协议测试分开。

VM 开发需匹配原生模块和服务，`kosctl dev settings` 打印实际路径，两个 Qt 导入变量都要指向当前模块。
素材就绪不证明 3D 已启用，要检查 `renderer=3D mesh` / `meshRenderer: true`；着色器回退是另一条路径。
前后景深度网格、mask、缓存契约同步更新。

## 模式与主题

图像/颜色/轮播/主题共用 `shared/qml/foundation/WallpaperCatalog.js`。
颜色生成图属于内部缓存，不进用户图库。预览用缩略图，应用用原图；请求串行防旧响应覆盖新选择。
轮播最多 2000 项，预览暂停，不足两张停播，输出共享随机种子。

主题保留原图供恢复/锁屏，停止轮播和深度，不依赖 AI 模型。`ThemeWallpaperScene` 与前景层共用 host 契约。
普通模式等待无可见窗口的桌面空闲，并受锁屏、输出可用性与减少动态策略约束。
预览立即播放，当前绕过普通空闲及减少动态限制，仍受锁屏、输出可用性和电池节奏影响。
安装的主题包可复用天气共享缓存。负载下不保证独立前后景窗口逐帧同步。

五款内置主题共享 `OpticalScene.qml`，通过 `aurora`、`prism`、`ocean`、`lagoon` fragment shader
在运行时绘制程序化场景，动画时钟和指针输入来自 host。单个 ShaderEffect layer 保持输出宽高比，
纹理长边普通模式最多 1280 像素，`host.economical` 为 true 时最多 800 像素。
这是纹理尺寸限制，不代表实测 GPU 开销或总显存。内置主题没有前景表面，外部主题包保留前景契约。
普通壁纸图库独立保留；旧离线底图、动态遮罩、`StilllightScene.qml` 及其 shader 和生成脚本
已无运行时消费者，但仍保留在工作树，待获准后清理。

保留原主题 ID 以兼容已保存配置：`starfield` = Polar Aurora，`blackhole` = Studio Crystal，
`weather` = Golden Ocean，`underwater` = Crystal Lagoon，`forest` = Moonlit Ocean。
两款海面主题使用不同 shader variant；`weather` 不由实时天气驱动。
修改 shader 后用 `shared/qml/wallpapers/compile.sh` 烘焙 `.qsb`，保留 Qt 兼容。
[素材来源](../shared/qml/wallpapers/assets/thumbnail-sources.txt)记录预览素材状态。

验收 TODO：五份保留的 `assets/preview.png` 仍展示上一版离线画面，须替换为当前运行时场景截图；
在 VM 检查实际渲染、播放策略及竖屏/超宽屏表现，并实测普通与省电模式的 GPU/内存开销。
shader 编译通过不代表视觉或性能验收通过。

## VM 审阅

无模型检查普通图片/接管/恢复、解码失败、服务/能力缺失、快速切换/取消、多屏就绪、预览确认/取消与已确认状态保留。
若声称空间完整支持，另测下载/校验/取消/推理/渲染。主题 GPU 开销实测，不复制历史 demo 观感。
按[开发指南](Development.zh-CN.md)仅 VM/CI 测试及启动真实 Shell。
