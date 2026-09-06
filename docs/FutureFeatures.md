# 后续功能

## QML → KWin 分 surface 玻璃参数

状态：暂缓。

目标是在 QML 中为单个 Wayland surface 发送 `blurMinimum`、染色和液态强度等参数，例如全屏启动台的最低模糊，而不影响 Dock、Bar 或其他启动台形态。

不能使用 layer-shell namespace：在当前 KWin 中它不会暴露给 effect，实测启动台只显示为 `resourceClass="quickshell"`、`resourceName="quickshell"`。

正确实现需要私有 `kos_surface_style_v1` Wayland protocol：KWin Glass 注册全局并保存每个 `wl_surface` 的状态；Quickshell 增加 `SurfaceStyle` QML 附着对象并把属性实时发送到同一 surface。

部署前提：KOS 必须打包并启动带该模块的自定义 Quickshell，而不能依赖系统 `/usr/bin/qs`。`kosctl` 也需同时构建、安装该 Quickshell 和 KWin effect。只有这两端一起发布时才能启用。
