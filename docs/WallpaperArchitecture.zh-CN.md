# 壁纸架构

[English](WallpaperArchitecture.md)

面向 AI 贡献者。壁纸失败不能阻塞 Shell/Dock 启动。[深度引擎](DepthEngine.md)负责模型/worker，
[主题格式](ThemePackFormat.zh-CN.md)负责 host 契约，本文负责运行编排。

## 所有权

- `WallpaperService.qml` 管原图、模式、过渡、最近使用、轮播和接管；`WallpaperImageLayer.qml` 按输出绘制，限制过渡纹理并延后清理。
  不为局部动画强制全局 Qt 渲染循环。
- `WallpaperPreviewService.qml` 管多输出可取消草稿：Enter 确认，Esc/关闭取消；与已确认状态隔离。
- `SpatialWallpaperService.qml` 请求素材，`DepthWallpaperLayer.qml` 显示；失败保留普通壁纸。
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
普通模式等待无可见窗口的桌面空闲，预览立即播放，锁屏/离屏/减少动态策略仍生效。
天气复用共享缓存。负载下不保证独立前后景窗口逐帧同步。
保留[资源来源](../shared/qml/wallpapers/vendor/README.md)及着色器 Qt 兼容。

## VM 审阅

无模型检查普通图片/接管/恢复、解码失败、服务/能力缺失、快速切换/取消、多屏就绪、预览确认/取消与已确认状态保留。
若声称空间完整支持，另测下载/校验/取消/推理/渲染。主题 GPU 开销实测，不复制历史 demo 观感。
按[开发指南](Development.zh-CN.md)仅 VM/CI 测试及启动真实 Shell。
