# 独立桌面应用

**[English](README.md) | [中文](README.zh-CN.md)**

每个直接子目录都是独立的 Qt Quick 应用和进程。应用可以导入 `shared/`，
通过已记录的契约与 `services/` 通信，但绝不能导入 `desktop/`。

应用工作区从仓库根目录配置。四个构建开关和对应 CMake preset 使各应用可
独立管理：

| 应用 | 目标 | 配置 preset |
| --- | --- | --- |
| 日历 | `kos-calendar` | `calendar-dev` |
| 待办 | `kos-todo` | `todo-dev` |
| 天气 | `kos-weather` | `weather-dev` |
| 音乐 | `kos-music` | `music-dev` |

使用 `apps-dev` 可一次构建四个应用。每个应用拥有自己的可执行文件、QML
模块、桌面入口、测试和中英文文档。`apps/common/` 只是很小的应用运行时，
不是功能层；应用之间不会互相导入。天气 preset 还会构建并安装 Go 数据服务，
应用会在需要时自动启动它。

要在 Plasma 开发机上注册为持久的用户级系统应用，请运行：

```sh
./tools/install-apps.sh
```

脚本会完成 Release 构建和测试，安装到 `~/.local`，注册桌面入口、hicolor
图标和 AppStream 元数据，启用 PIM 与共享数据的用户服务，并刷新 Plasma
应用缓存。桌面入口使用绝对可执行路径，因此重新登录后无需回到源码目录构建。
后续升级可重复运行同一个脚本。

每个应用都可通过平台“首选项”快捷键（通常为 `Ctrl+,`）打开统一外观设置，包括跟随系统/浅色/深色、
自动/玻璃/实色材质、不透明度、强调色、减少透明度和减少动画。偏好保存在
四个 KOS 应用共用的配置中，并会同步到其他正在运行的应用。在 KDE Plasma
上，应用运行时会在合成器支持时通过 `KWindowEffects` 请求原生背景模糊和
背景对比；不可用时会自动切换为保证可读性的实色方案。

`settings` 早于该工作区存在，在它依赖源码路径的 QML 加载方式单独迁移前，
仍沿用现有构建路径。
