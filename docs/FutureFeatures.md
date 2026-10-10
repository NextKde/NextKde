# 后续功能

## QML → KWin 按形状声明玻璃参数

状态：基础能力已实现，独立染色和折射参数尚未实现。

当前由 [`kos_surface_shape_v1`](../shell/native/surface-shape/kos-surface-shape-v1.xml)
传递 surface 内各个形状的几何、圆角、scrim、模糊强度、固定捕获区域、材质透明度和展开动画。
`Kos.SurfaceShape` 是独立的 Qt QML 扩展，由 `kosctl` 构建并部署，使用系统 Quickshell 加载；无需打包自定义 Quickshell。

`LiquidGlassPanel` 使用 `blurOverrideEnabled` 开启独立模糊覆盖，
由 `blurStrength` 和 `AppearanceConfigService.compositorBlurLevel()` 解析最终级别，
通过协议的 `set_blur` 请求发送给 Glass。同一 surface 内的不同形状可以使用不同模糊级别。
协议各项能力按版本协商，旧版服务端继续使用其支持的行为。

待实现部分是按形状独立调整染色、折射和高光强度；这些当前仍使用 Glass 的全局配置。
新增能力应扩展现有协议并保留旧请求的编号，继续由客户端与 Glass 一起发布。
不能依赖 layer-shell namespace 区分这些表面；Glass 使用明确的 surface 形状声明。

已实现的配置和集成约束见 [`AppearanceArchitecture.md`](AppearanceArchitecture.md)。
