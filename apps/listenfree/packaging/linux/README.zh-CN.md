# KOS ListenFree Linux 构建

[English](README.md)

KOS ListenFree 是 NextKDE 对 ListenFree 的适配，程序/桌面 ID 为 `listenfree` / `listenfree.desktop`。
显式安装后替代旧 `kos-music` 注册，旧源码和用户数据保留。发行保留 `licenses/` 的上游说明，
ListenFree 数据目录和 MPRIS 名保持升级兼容。

在 NextKDE 显式选择音频：

```sh
./tools/kosctl install apps --with-listenfree
```

不传此选项仅装日历、计算器、待办、天气。音频安装器检查依赖并输出 Arch/Ubuntu 缺包命令，
需要匹配的 Qt 6.10+、KF6、数据服务 Go 1.26+。旧 Ubuntu 的 Qt 不足时，重装旧包不能满足版本；
完整兼容工具链通过标准 CMake/pkg-config 路径提供。

私有 `.build/listenfree-sdk` 下载并 SHA256 校验 QuickJS-ng 0.16.2、补丁 Qmmp 2.4.1，
系统 TagLib 不足时另建 2.3.1。不需 root，系统依赖由发行版管理。首次需联网，后续复用有效源码/制品。
仅准备 SDK 用 `./tools/prepare-listenfree-sdk.sh`，现有兼容 SDK 可用 `KOS_LISTENFREE_SDK`。

独立构建，或在 NextKDE 启用 `KOS_BUILD_LISTENFREE`：

```sh
cmake -S apps/listenfree -B .build/listenfree -G Ninja   -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"   -DKOS_LISTENFREE_SDK=/path/to/listenfree-sdk   -DLISTENFREE_BUILD_TESTS=ON
cmake --build .build/listenfree --target listenfree listenfree-sourcehost
cmake --install .build/listenfree
```

独立 ListenFree 仓库改用 `-S .`。SDK 是依赖前缀，不是用户配置副本：`prefix/` 放上述库/插件，
`vendor/qmmp-2.4.1/` 放对应补丁源码，可选 `deps/usr/` 放匹配原生开发包。
补丁顺序见 `licenses/THIRD-PARTY-NOTICES.txt`，源码和二进制插件必须同补丁集，不直接替换系统未修改 Qmmp。
另需 KF6 WindowSystem、FFmpeg、OpenSSL、zlib、ICU 开发文件。
也可用各 `LISTENFREE_*` CMake 路径代替 SDK 结构。

程序及私有运行库安装到前缀内 `opt/listenfree`，启动器设置私有库/插件路径。
安装后执行 `update-desktop-database PREFIX/share/applications`。
NextKDE 的 `tools/register-default-apps.py --with-listenfree` 迁移旧音乐关联、保留其他用户默认、
备份并移除旧音乐程序注册，清理临时 Todo/Calendar/Weather 预览入口。
文件管理器可传多个路径/file URL，后续调用把文件交给常驻实例。

贡献者构建、测试、运行验证只在 VM/托管 CI。该组件依赖/测试独立，普通数据/服务测试预设不会隐式开启。
在配置构建目录执行其 CTest，并正确设置私有库及 Qmmp 插件路径。

## 可选功能与安装体积

默认播放器不要求 Qt WebEngine 或 Qt Multimedia，保留本地/在线音频、Cookie 登录、静态封面、歌词和频谱。
FFmpeg 仍用于音频解码和 HLS，关闭视频不会移除它。

| CMake 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `LISTENFREE_BUILD_WEB_LOGIN` | `OFF` | 编译独立 `listenfree-web-login`，需要 Qt WebEngine。 |
| `LISTENFREE_BUILD_VIDEO` | `OFF` | 启用 MV、动态封面、本地/Wallpaper Engine 视频背景，需要 Qt Multimedia 及其 QML 模块。 |
| `LISTENFREE_BUILD_TOOLS` | `OFF` | 将开发探针和基准工具纳入默认构建。 |
| `LISTENFREE_STRIP_INSTALL` | `ON` | Release 安装时去符号，包含复制的私有音频库/插件；构建目录仍保留符号。 |

视频通过 `./tools/kosctl install apps --with-listenfree-video` 或直接配置 `-DLISTENFREE_BUILD_VIDEO=ON` 开启。
关闭后不编译视频原生源文件，不打包视频 QML，并隐藏相关控件；旧视频设置回退到静态封面/自动背景，歌词和频谱继续可用。
安装器每次显式设置两个可选开关，避免旧 CMake 缓存意外恢复重依赖。

网页登录在用户登录时选择：未找到组件时展示安装说明，Cookie 登录继续可用。
按照[随程序安装的说明](../web-login/install.txt)单独构建/安装组件，无需音频 SDK。
也可在播放器构建中开启 `LISTENFREE_BUILD_WEB_LOGIN=ON`，再显式安装：

```sh
cmake --install .build/listenfree --component listenfree-web-login --strip
```

普通播放器安装始终不包含此组件，即使已开启其构建开关。发行版应把 WebEngine 依赖放在可选软件包上。
播放器先查找同目录组件，再查找 PATH。组件仅接收平台 ID 和已有资料目录，验证登录后保存到同一系统钥匙环命名空间。
退出码 0 触发账户刷新，1 表示取消；异常或十分钟超时不会结束播放器。Cookie 不通过进程参数、日志或临时文件传递。
组件与播放器应来自同一修订，安装到同一前缀。

诊断安装可配置 `-DLISTENFREE_STRIP_INSTALL=OFF`，并且不要传 `cmake --install --strip`。
Debug/RelWithDebInfo 安装默认保留符号，显式 `--strip` 除外。发行版可先从构建目录提取独立调试符号包。
NextKDE 应用安装器显式使用 `--strip`。

功能调整需在 VM/CI 验证 OFF/OFF、ON/OFF、OFF/ON、ON/ON 四种组合。设置 `QT_QPA_PLATFORM=offscreen`、
`QMMP_PLUGINS` 和私有库路径后运行 CTest；视频/渲染测试还需要 VM 图形会话。
检查轻量安装 ELF 的依赖闭包，并在可选运行库/QML 模块不可用时启动，覆盖设置页和已有视频偏好的沉浸界面。
确认普通安装没有登录组件，显式组件安装才会包含它。
