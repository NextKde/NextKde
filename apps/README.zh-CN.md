# 独立桌面应用

**[English](README.md) | [中文](README.zh-CN.md)**

每个应用有独立的 Qt Quick 窗口与进程；`todo/` 是日历提醒事项的兼容启动入口，不再提供独立应用。应用可以导入 `shared/`，
通过已记录的契约与 `services/` 通信，但绝不能导入 `shell/desktop/`。

应用工作区从仓库根目录配置。构建开关和对应 CMake preset 使各应用可
独立管理：

| 应用 | 目标 | 配置 preset |
| --- | --- | --- |
| 日历 | `kos-calendar` | `calendar-dev` |
| 计算器 | `kos-calculator` | `apps-dev` |
| 提醒事项兼容入口（自动构建日历） | `kos-todo` | `todo-dev` |
| 天气 | `kos-weather` | `weather-dev` |
| KOS ListenFree（显式安装的音乐应用） | `listenfree` | `listenfree-dev` |

使用 `apps-dev` 可构建日历（含提醒事项）、计算器、天气及待办兼容入口。每个应用拥有自己的可执行文件、QML
模块、桌面入口、测试和中英文文档。`apps/common/` 只是很小的应用运行时，
不是功能层；应用之间不会互相导入。天气 preset 还会构建并安装 Go 数据服务，
应用会在需要时自动启动它。

贡献者构建、测试、启动和图形验证仅在专用 VM/托管 CI，见[开发指南](../docs/Development.zh-CN.md)。

## 开发调试：QML 热重载

基于 `apps/common` 的 KOS 应用支持直接从源码树加载 QML 并热重载，改 QML 不需要重编或重启：

```bash
.build/calendar-dev/apps/calendar/kos-calendar --watch-qml apps/calendar/qml
# 或者用环境变量省去参数
KOS_APP_QML_DIR=apps/calendar/qml .build/calendar-dev/apps/calendar/kos-calendar
```

参数指向存放 `Main.qml` 的目录（或入口文件本身）。监视树内的
`*.qml`/`*.mjs`，保存后 300ms 防抖重建窗口；新代码会先在一次性引擎上
完整编译校验（含被引用的兄弟组件），编译不过就报错并保留当前窗口。
由 C++ 创建、经 initial properties 注入 QML 的控制器跨重载存活；
QML 自己拥有的状态（当前页面、打开的对话框）会重置。`shared/qml`
（Kos.Ui）编译在二进制里，改动它仍需重编。

watch 运行是独立的开发实例：不与已运行的正式实例争单例激活。
各应用的 C++ 改动仍需重编；只有 QML/JS 改动走热重载。

要在 Plasma 虚拟机中注册为持久的用户级系统应用，请运行：

```sh
./tools/install-apps.sh
```

`./tools/kosctl install apps`（或 `install-apps.sh`）默认只构建日历、计算器、待办和天气。
预检只检查选中应用的依赖：标准安装要求 Qt 6.5+、兼容 KF6、Go 1.26+、QML 运行模块和 SQLite 驱动。
缺少依赖时给出 Arch `pacman` 或 Ubuntu `apt` 命令，不会自动执行 sudo。

ListenFree 和私有音频 SDK 必须显式选择：

```sh
./tools/kosctl install apps --with-listenfree
```

该选项额外要求 Qt 6.10+ 和音频依赖，首次下载、校验并构建 QuickJS-ng、Qmmp，必要时还构建 TagLib，耗时较长。
后续构建指纹相同时复用 `.build/listenfree-sdk`；已有 SDK 可用 `KOS_LISTENFREE_SDK=/path/to/sdk` 指定。
标准安装不准备 SDK，不移除已有音乐应用，也不改音频文件关联。
详见 [ListenFree 构建指南](listenfree/packaging/linux/README.md)。

脚本会完成 Release 构建，安装到 `~/.local`，注册桌面入口、hicolor
图标和 AppStream 元数据，启用核心 `kos-data.service`、注册由 D-Bus 按需激活的
PIM 服务，并刷新 Plasma 应用缓存。桌面入口使用绝对可执行路径，因此重新登录后无需回到源码目录构建。
后续升级可重复运行同一个脚本。

每个应用都可通过平台“首选项”快捷键（通常为 `Ctrl+,`）打开统一外观设置，包括跟随系统/浅色/深色、
自动/玻璃/实色材质、不透明度、强调色、减少透明度和减少动画。偏好保存在
四个 KOS 应用共用的配置中，并会同步到其他正在运行的应用。在 KDE Plasma
上，应用运行时会在合成器支持时通过 `KWindowEffects` 请求原生背景模糊和
背景对比；不可用时会自动切换为保证可读性的实色方案。

应用安装保留核心 Settings 及共享运行 QML，应用专用前缀不要求已安装核心。

`settings` 早于该工作区存在，在它依赖源码路径的 QML 加载方式单独迁移前，
仍沿用现有构建路径。

## 默认应用与升级

标准四款应用沿用其 `kos-*` 桌面 ID、服务和用户数据。
旧 `kos-music` 的源码和构建目标已移除，普通安装与升级仍保留已安装的旧播放器、曲库和音频关联。
只有 `--with-listenfree` 会注册 ListenFree，
通过运行检查后备份并移除旧 KOS Music 的程序与注册文件。用户数据、其他播放器的默认关联和后续用户选择保留。
桌面音乐组件优先唤起当前 MPRIS 播放器，没有播放器时尝试打开 ListenFree；未安装时需要自行选择播放器。
