# 独立桌面应用

**[English](README.md) | [中文](README.zh-CN.md)**

每个直接子目录都是独立的 Qt Quick 应用和进程。应用可以导入 `shared/`，
通过已记录的契约与 `services/` 通信，但绝不能导入 `shell/desktop/`。

应用工作区从仓库根目录配置。五个构建开关和对应 CMake preset 使各应用可
独立管理：

| 应用 | 目标 | 配置 preset |
| --- | --- | --- |
| 日历 | `kos-calendar` | `calendar-dev` |
| 待办 | `kos-todo` | `todo-dev` |
| 天气 | `kos-weather` | `weather-dev` |
| 音乐（旧版，保留） | `kos-music` | `music-dev` |
| KOS ListenFree（默认音乐应用） | `listenfree` | `listenfree-dev` |

使用 `apps-dev` 可一次构建五个应用。每个应用拥有自己的可执行文件、QML
模块、桌面入口、测试和中英文文档。`apps/common/` 只是很小的应用运行时，
不是功能层；应用之间不会互相导入。天气 preset 还会构建并安装 Go 数据服务，
应用会在需要时自动启动它。

## 开发调试：QML 热重载

基于 `apps/common` 的四款 KOS 应用支持直接从源码树加载 QML 并热重载，改 QML 不需要重编或重启：

```bash
.build/music-dev/apps/music/kos-music --watch-qml apps/music/qml
# 或者用环境变量省去参数
KOS_APP_QML_DIR=apps/music/qml .build/music-dev/apps/music/kos-music
```

参数指向存放 `Main.qml` 的目录（或入口文件本身）。监视树内的
`*.qml`/`*.mjs`，保存后 300ms 防抖重建窗口；新代码会先在一次性引擎上
完整编译校验（含被引用的兄弟组件），编译不过就报错并保留当前窗口。
由 C++ 创建、经 initial properties 注入 QML 的控制器（如 music 的
`music`）跨重载存活，播放、队列、数据库连接与 MPRIS 注册不会中断；
QML 自己拥有的状态（当前页面、打开的对话框）会重置。`shared/qml`
（Kos.Ui）编译在二进制里，改动它仍需重编。

watch 运行是独立的开发实例：不与已运行的正式实例争单例激活。
各应用的 C++ 改动仍需重编；只有 QML/JS 改动走热重载。

要在 Plasma 开发机上注册为持久的用户级系统应用，请运行：

```sh
./tools/install-apps.sh
```

`./tools/kosctl install apps`（或 `install-apps.sh`）一次构建日历、待办、天气和 ListenFree。
安装前检查系统依赖，缺少什么就提示什么，并给出对应的 Arch `pacman` 或 Ubuntu `apt`
命令。执行提示的命令后重新安装即可；安装器不会自动执行 sudo。

Arch 滚动版本和 Ubuntu 26.04+ 提供所需的 Qt 6.10+。Ubuntu 22.04/24.04/25.10
自带 Qt 版本不足，需完整且兼容的 Qt/KF6 工具链。数据服务还要求 Go 1.26+。
检查范围包括开发库、编译工具、QML 运行模块和 SQLite 驱动。
只检查依赖可运行 `python3 tools/check-apps-dependencies.py`。

安装器自动下载并校验 QuickJS-ng、Qmmp 源码，应用仓库内的音频补丁，并在
`.build/listenfree-sdk` 构建私有 SDK。系统 TagLib 低于 2.3.1 时也会自动补建到私有目录。
首次安装需要联网且编译较久，后续在构建指纹一致时复用缓存，无需手动准备 SDK。
已有兼容 SDK 时仍可用 `KOS_LISTENFREE_SDK=/path/to/sdk` 指定。
依赖和架构均在目标设备上检查，构建脚本不使用本机专属路径。

脚本会完成 Release 构建，安装到 `~/.local`，注册桌面入口、hicolor
图标和 AppStream 元数据，启用核心 `kos-data.service`、注册由 D-Bus 按需激活的
PIM 服务，并刷新 Plasma 应用缓存。桌面入口使用绝对可执行路径，因此重新登录后无需回到源码目录构建。
后续升级可重复运行同一个脚本。

每个应用都可通过平台“首选项”快捷键（通常为 `Ctrl+,`）打开统一外观设置，包括跟随系统/浅色/深色、
自动/玻璃/实色材质、不透明度、强调色、减少透明度和减少动画。偏好保存在
四个 KOS 应用共用的配置中，并会同步到其他正在运行的应用。在 KDE Plasma
上，应用运行时会在合成器支持时通过 `KWindowEffects` 请求原生背景模糊和
背景对比；不可用时会自动切换为保证可读性的实色方案。

`settings` 早于该工作区存在，在它依赖源码路径的 QML 加载方式单独迁移前，
仍沿用现有构建路径。

## 默认应用与升级

Todo、Calendar、Weather 在原目录和原 `kos-*` 桌面 ID 上更新界面，沿用原服务和用户数据。ListenFree 替换安装包中的旧 KOS Music；旧源码暂时保留在仓库中。桌面音乐组件优先唤起当前 MPRIS 播放器，没有播放器时启动 ListenFree。

直接执行 `./tools/kosctl install apps` 即可；私有 SDK 布局和手动构建方式见 [Linux 构建说明](listenfree/packaging/linux/README.md)。安装器在部署前检查依赖并完成编译；新播放器通过运行检查后，注册脚本备份并移除旧播放器的程序、桌面入口、图标和 AppStream 元数据。旧用户数据保留。其他播放器的默认关联及后续用户选择不会被覆盖。
