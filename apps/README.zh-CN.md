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

`install-apps.sh` 会一次构建全部五个应用，而不只是当前要使用的应用。除仓库
根目录 README 中的基础依赖外，Arch 还需要先安装：

```sh
sudo pacman -S --needed kcalendarcore gstreamer gst-plugins-base-libs taglib
```

其中 `kcalendarcore` 由日历和待办使用；GStreamer 与 TagLib 由音乐使用；天气所需
的 Go 已包含在 KOS 核心构建依赖中。实际播放和转码所需的 GStreamer 编解码/输出
插件需按使用场景另行安装。若仅使用对应的 CMake preset 构建单个应用，只需要该
应用的直接依赖。

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

Todo、Calendar、Weather 在原目录和原 `kos-*` 桌面 ID 上更新界面，沿用原服务和用户数据。测试版 `*-preview` 入口在正式注册时移除。音乐保留两个独立实现：`apps/music` 的旧 KOS Music 与 `apps/listenfree` 的 KOS ListenFree；桌面音乐组件和默认音频文件关联使用后者。

KOS ListenFree 的额外构建依赖及 SDK 布局见 [Linux 构建说明](listenfree/packaging/linux/README.md)。构建全套前设置 `KOS_LISTENFREE_SDK`，其配置与播放引擎保持独立。`tools/install-apps.sh` 安装后执行 `tools/register-default-apps.py` 完成默认关联、窗口按钮配置和测试入口清理；注册前的偏好及测试安装归档到用户状态目录供恢复。旧 KOS Music 的程序及资料不会删除。
