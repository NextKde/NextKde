# 文档索引

[English](README.md)

英文为默认；双语指南顶部提供中文对照。根 [README](../README.zh-CN.md)介绍桌面，详细操作由以下指南负责。

## 用户与发布

| 主题 | 权威入口 |
| --- | --- |
| 依赖、安装、更新、卸载 | [开始使用](GettingStarted.zh-CN.md) |
| NixOS 声明式安装 | [NixOS](nixos-quickstart.zh-CN.md) |
| 维护、验收、发布 | [发布流程](Releasing.zh-CN.md) |
| 各版改动与实际证据 | [v0.1.1](releases/v0.1.1.zh-CN.md)、[v0.1.0](releases/v0.1.0.zh-CN.md) |
| 发布说明格式 | [模板](releases/TEMPLATE.zh-CN.md) |

## AI 贡献者参考

先读[项目上下文](../PROJECT_CONTEXT.zh-CN.md)、[贡献规范](../CONTRIBUTING.zh-CN.md)和
[开发指南](Development.zh-CN.md)。架构文档说明当前契约及源码所有权，不是工作流水账，也不是运行验收证明。

| 模块/主题 | 参考 |
| --- | --- |
| 运行产品、服务边界 | [项目架构](ProjectArchitecture.md) |
| 平台接入与 IPC | [平台架构](PlatformArchitecture.md)、[通信契约](../shared/contracts/platform.v1.md) |
| 持久数据、socket 与并发 | [数据服务](DataServiceArchitecture.md) |
| 外观、Token、图标 | [外观](AppearanceArchitecture.zh-CN.md)、[桌面图标](DesktopIcons.zh-CN.md) |
| 窗口裁剪、阴影、资源限制及 VM 审阅 | [窗口外观](WindowAppearance.zh-CN.md) |
| Dock 输入、生命周期、动画 | [Dock](DockArchitecture.md) |
| 壁纸所有权及主题格式 | [壁纸](WallpaperArchitecture.zh-CN.md)、[主题包](ThemePackFormat.zh-CN.md)、[深度引擎](DepthEngine.md) |
| 网络、PIM、天气 | [网络](NetworkArchitecture.md)、[PIM](PimArchitecture.md)、[天气](WeatherArchitecture.md) |
| 可选应用与旧播放器迁移 | [应用](../apps/README.zh-CN.md)、[ListenFree 构建](../apps/listenfree/packaging/linux/README.zh-CN.md) |
| 可复用 QML 组件、Gallery 与侧栏 Demo | [nextkdeAppDemo](https://github.com/NextKde/nextkdeAppDemo) |

组件 Gallery 与侧栏 Demo 由 `nextkdeAppDemo` 独立维护，NextKde 不再附带它们的预览入口。
主仓库保留运行时使用的共享 QML 组件和 Shell 玻璃实现；Demo 仓库的改动不会自动同步到这里。

## 持续维护

代码改动同步更新权威页面及维护中的译文，用链接代替重复实现细节。
文档与契约/源码冲突时以契约/源码为准，并在同一 PR 修正文档。已知限制、未来计划、实测结果分别说明。

`docs/` 不提交会话日记、过程截图、抓取日志及临时 review 报告。临时资料放忽略的 `tmp/`；
长期发布证据放 CI/Release 制品。保留项目插图、必要资源及第三方来源。
当前树删除文件不等于清除历史 Git 对象；浅克隆可避免下载旧历史。常规文档清理不改写已发布历史。
