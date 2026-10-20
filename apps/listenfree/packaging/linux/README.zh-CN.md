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
另需 Qt WebEngine、KF6 WindowSystem、FFmpeg、OpenSSL、zlib、ICU 开发文件。
也可用各 `LISTENFREE_*` CMake 路径代替 SDK 结构。

程序及私有运行库安装到前缀内 `opt/listenfree`，启动器设置私有库/插件路径。
安装后执行 `update-desktop-database PREFIX/share/applications`。
NextKDE 的 `tools/register-default-apps.py --with-listenfree` 迁移旧音乐关联、保留其他用户默认、
备份并移除旧音乐程序注册，清理临时 Todo/Calendar/Weather 预览入口。
文件管理器可传多个路径/file URL，后续调用把文件交给常驻实例。

贡献者构建、测试、运行验证只在 VM/托管 CI。该组件依赖/测试独立，普通数据/服务测试预设不会隐式开启。
在配置构建目录执行其 CTest，并正确设置私有库及 Qmmp 插件路径。
