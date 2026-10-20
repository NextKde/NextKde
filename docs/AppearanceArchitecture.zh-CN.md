# 外观架构

[English](AppearanceArchitecture.md)

面向 AI 贡献者。改动前读[项目边界](ProjectArchitecture.md)及[窗口渲染](WindowAppearance.zh-CN.md)。
本文说明当前设计，不是运行验收报告。

## 所有权和源码入口

| 所有者 | 契约 |
| --- | --- |
| `shell/desktop/modules/common/AppearanceConfigService.qml` | Shell 外观校验、迁移、快照 |
| 同目录 `AppearanceTokens.qml` | 派生视觉 Token，版本 9；消费者用 Token，不重复样式分支 |
| `IconAppearanceService.qml`、`BundledIcons.qml`、`BundledIcon.qml`、`SystemIconResolver.qml` | 图标持久化、命名资源、系统主题集中回退 |
| `shell/desktop/DesktopEnvironment.qml` | `appearance-settings` IPC |
| `apps/settings/` | 独立进程，经 IPC 编辑，不导入 Shell 内部 |
| `shared/qml/colorize/` | 可移植纯 JS 调色/HCT，不依赖 Quickshell |
| `shared/qml/controls/` 与 Shell 公共组件 | 通过显式主题输入复用表面和控件 |

配置归 `AppearanceConfigService`，颜色/几何/透明度/动效由 `AppearanceTokens` 派生。
Shell 形态（`windows12`/`macos`/`material`）、组件样式、玻璃预设（`liquid`/`soft`/`frosted`）、
Bar 融合/布局/显示及 Dock 配置相互独立。切换样式不重置 Dock 固定项、尺寸或独立状态。
独立应用偏好尚未与 Shell 同步，见[项目上下文](../PROJECT_CONTEXT.zh-CN.md)。

## 持久化与 IPC

`Quickshell.stateDir/appearance/config.json` 当前写入 schema **30**；完整字段以源码
`serialize()` 和加载迁移为准，不用不完整示例覆盖用户整份 JSON。保留旧版迁移、各预设光学值、校验及范围裁剪。
图标另存 `appearance/icon-appearance.json`（schema 1），含旧 Dock 一次性迁移。
经防抖、`JsonConfigStore` → 平台 `state.write` → `QSaveFile` 保存，不从 QML 执行 shell 命令。

Settings 调用 `appearance-settings` 快照/更新并取得完整快照。新增项检查端点、范围、兼容别名及 Shell/平台不可用路径。
切换玻璃应用完整预设，Material 有独立模糊策略；重置玻璃强度不等于重置所有偏好。

## 色彩与对比度

用 `AppearanceTokens.isDarkTheme` 和语义内容 Token，特别是 `content.glassInk`，不直接用系统明暗标志选文字色。
`glassFollowsAppearanceMode` 为 false 时浅色桌面仍可能有深色玻璃，需要浅色文字。
材质填充透明度、scrim、背景模糊分开处理；染色/填充透明不意味着关闭模糊；协议材质透明度则衰减包括模糊在内的完整效果，协议见[窗口外观](WindowAppearance.zh-CN.md)。

`shared/qml/colorize/` 本地生成 Material 配色：`monet` 用 CAM16/HCT，`chinese`、`japanese` 用传统色数据和共用对比策略。
保持 sRGB 字节舍入、HCT 色域和对比度回归，不换成外部 `matugen` 或近似 Lab。
从原壁纸取色，不采 Plasma 黑白占位图；通过 `plasmashellrc` 当前 ShellPackage 定位配置，不硬编码旧 appletsrc。

源码 colorize 目录不是编译后的 `Kos.Ui` 模块。Shell/Settings 两种运行方式均需正确别名、`qmldir`、资源部署、相对导入。
共享/应用代码不导入 Quickshell 专属适配器。Material 卡片表面/花瓣模糊走公共组件，不把样式分支散落各控件。

## 图标、几何、动效

Shell 图案在 `BundledIcons` 用稳定名称登记，通过 `BundledIcon` 或注册表来源绘制，不依赖本机绝对路径或字体字形。
应用图标、媒体封面、文件缩略图各有契约。Dock 回收站等系统主题例外经 `SystemIconResolver` 集中候选和内置回退。

Dock、Bar、组件统一使用几何/动效 Token。窗口动画目标使用合成器全局坐标中的稳定槽位中心及静态图标尺寸，悬停放大不改变最小化落点。
桌面间距见[桌面图标](DesktopIcons.zh-CN.md)。Material 表面与连续窗口圆角渲染所有者不同，不重复裁剪或阴影。

## 验证与审阅

按[开发指南](Development.zh-CN.md)仅 VM/CI 验证。覆盖迁移、快照/IPC、浅/深/系统主题、浅桌面深玻璃、
玻璃/Material/配色、Bar/Dock 融合、源码/安装模块路径、图标回退、减少动态效果。
全屏/最大化/混合缩放另见[窗口外观](WindowAppearance.zh-CN.md)。offscreen Token 测试不能证明实时模糊、GPU 性能或多屏行为。
