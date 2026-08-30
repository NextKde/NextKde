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
不是功能层；应用之间不会互相导入。

`settings` 早于该工作区存在，在它依赖源码路径的 QML 加载方式单独迁移前，
仍沿用现有构建路径。
