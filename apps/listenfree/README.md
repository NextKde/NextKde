# KOS ListenFree for NextKDE

此目录维护 NextKDE 的可选 Linux 音乐播放器。默认安装及 `./install apps` 均不包含 ListenFree；只有显式选择安装时才执行旧 KOS Music 迁移。旧播放器源码已移除，标准升级保留已安装文件、用户数据和音频关联。桌面 ID 为 `listenfree`；应用和用户资料保持独立。安装边界见 [应用说明](../README.zh-CN.md)。

构建、安装及依赖说明见 [Linux 构建说明](packaging/linux/README.md)。下方保留 ListenFree 上游说明及原有归属信息。

“本地音乐 / Local Music”只展示扫描到的本地文件；在线收藏仍在“我的收藏”，不再合并到本地曲库。侧栏不再提供 Artists 页面。歌曲列表与播放队列标注酷我、酷狗、QQ 音乐、网易云、咪咕、哔哩哔哩或本地音乐；脚本搜索结果同时保留原脚本名称。

后台以 `trackUid` 统一管理歌曲：平台歌曲按平台和原始 ID 区分，本地文件按规范化路径区分，脚本搜索 ID 按脚本隔离。队列的 `entryId` 独立持久化，用于定位和操作具体条目。旧队列和收藏在读取时补全身份并去重，不按歌名合并不同版本。

新用户的在线播放音质默认为 128K，已有音质选择保持不变。播放解析失败时尝试同平台的其他已导入音源及较低音质；最多 24 次尝试、总计 4 分钟，每次音源操作最多 90 秒。脚本专属歌曲保持绑定原脚本。等待期间歌名右侧显示转圈标识，停止或切歌会取消原请求及重试。

侧栏页面创建、在线内容请求或本地扫描期间，对应菜单项右侧显示加载环，内容区仅保留背景。切换到其他页面可继续操作；请求完成或失败后恢复页面。页面缓存仍保留选择和滚动位置，恢复封面的等待最长为 3 秒。


# ListenFree

Windows 10/11 x64 原生音乐播放器，使用 Qt Quick、Qmmp、QuickJS-ng 和 TagLib。
安装版见 [Releases](https://github.com/Tabris-Ayanami/ListenFree-desktop/releases)。运行成品无需安装 Qt、Node.js 或 Python。

## 构建输入

- Qt 6.11.2 MinGW x64，包含 Quick、Multimedia、ShaderTools、Sql 和 Test；MinGW 13.1、CMake 3.28+、Ninja。
- 使用根目录 vcpkg.json 固定版本安装 QuickJS-ng、TagLib 及 zlib，依赖前缀为 .vcpkg_installed/x64-mingw-dynamic。
- 构建 Qmmp 2.4.1 及 FFmpeg、libcurl 等依赖。先应用 patches/qmmp/2.4.1/0001 和 0003，再按编号应用 patches/qmmp/0004 至 0020；不应用已撤销的 0002。
- Qmmp 的 FFmpeg、HTTP、WASAPI、Crossfade 插件及 libqmmpui 需与补丁后的 libqmmp 一起构建。Qt Multimedia 修复脚本为 scripts/build-patched-qtmultimedia.ps1。

第三方源码、SDK、依赖安装目录和二进制不纳入 Git。默认外部依赖布局如下，也可通过 CMake cache 参数覆盖：

```text
../_vendor/
  qmmp-2.4.1/                 # 已应用补丁的源码
  qmmp-stage-qt/              # libqmmp.dll、导入库和 Input/Output/Transports/Effect
  qmmp-build-qt/src/qmmpui/   # libqmmpui.dll 和导入库
  qmmp-build-qt/src/plugins/Transports/http/  # 新版 http.dll
  qmmp-vcpkg-installed-qt/x64-mingw-dynamic/ # FFmpeg/libcurl 等头文件、库和运行库
```

## 编译与部署

在 PowerShell 中执行，可根据 SDK 位置调整参数：

```powershell
./scripts/windows/package-portable.ps1 -QtRoot 'F:/QT/6.11.2/mingw_64' -QtToolsRoot 'F:/QT/Tools' -VendorRoot '../_vendor'
```

脚本通过 CMake 构建 Release，部署到 dist/ListenFree-Portable 并做隔离启动检查。重新部署保留该目录的个人 data。CMakePresets.json 提供当前工具链的 portable 预设，可用 CMakeUserPresets.json 覆盖本机路径。

安装 Inno Setup 6 后生成 0.3.8 安装版：

```powershell
./scripts/windows/package-release.ps1 -Version 0.3.8 -InstallerOnly -SkipChecksums
```

省略 `-InstallerOnly` 并安装 7-Zip 时，脚本仍可生成便携 ZIP；0.3.8 的 GitHub Release 提供一个安装程序和应用内更新必需的签名清单。改动见 [更新说明](packaging/release-notes-0.3.8.txt)。

使用已经验收的运行库目录可传入 `-RuntimeDirectory <目录>`；追加 `-SkipChecksums` 可只生成安装包和便携 ZIP，不生成校验文件。

发行脚本只收集程序、运行库、使用说明和许可，排除个人数据与用户音源；输出目录必须是尚未生成过的版本目录，也可指定 OutputDirectory。

src/、music_player_desktop/、ui/ 是应用与资源；tests/ 和 tools/ 保留构建引用的验证代码；patches/、scripts/、packaging/ 和 licenses/ 为依赖修改及打包输入。个人文档、开发规划、生成物和测试结果不进入仓库。组件归属与许可见 licenses/THIRD-PARTY-NOTICES.txt。

## 软件更新与发布

“设置 → 关于 → 检查软件更新”使用 [WinSparkle 0.9.4](https://winsparkle.org/guides/getting-started/) 提示新版、展示更新说明、下载并验证签名，用户确认后启动 Inno Setup。只在手动检查时加载组件，关闭定期检查。安装版原目录升级；便携版原目录覆盖程序文件，保留 portable.mode 与 data，且不创建卸载项或快捷方式。0.3.2 及更早版本需先手动升级一次；0.3.3 起支持应用内更新。

CMake 从官方 Release 获取已固定 SHA-256 的 WinSparkle x64 包，也可设置 `LISTENFREE_WINSPARKLE_ROOT` 指向解压目录；运行时只分发 DLL 和许可。更新信息地址固定为本仓库 `releases/latest/download/appcast.xml`，文件中指向明确版本的 Setup.exe。比较后选择 WinSparkle 的原因是它已经提供 EdDSA 验签和原生更新界面，可直接配合现有安装器；QSimpleUpdater 仍需另接签名校验，Velopack 则需要迁移安装布局。

安装版打包脚本同时生成已签名的 appcast.xml，核对签名私钥与 `src/app/update_public_key.h` 中的公钥是否一致，并重新验签。默认私钥位置为 `%LOCALAPPDATA%/ListenFree/ReleaseSigning/winsparkle-private.key`，可用 `-SigningKeyFile` 指定工作区外的备份。**务必备份原私钥；不要提交、上传或重新生成替代密钥，否则已发布版本无法信任后续更新。**

发布时把 Setup.exe 和 appcast.xml 上传同一个 GitHub Release，全部校验完成后再标记为最新正式版。预发布不要设为 latest；无需额外上传 SHA 文件。可单独调用 `scripts/windows/new-update-appcast.ps1` 对安装包签名并生成更新信息。

`-InstallerOnly` 表示只生成安装程序分发形式；appcast.xml 是应用内更新接口的必需元数据，必须随安装包发布。发布验收还须从 `releases/latest/download/appcast.xml` 实际下载清单，核对版本、安装包地址、大小与签名，不能只检查安装包资产。

## 自定义音源兼容验证

SourceHost 的浏览器 API 使用已提交的离线静态资源，成品无需 Node。生成方式与固定依赖见 src/third_party/sourcehost_browser/README.md。

```powershell
python tools/test_sourcehost_contract.py --standalone --host dist/ListenFree-Portable/listenfree-sourcehost.exe
```

该契约回归使用本机 HTTP 测试服务，覆盖字节与加密、URL、HTTP 错误正文、异步初始化、取消及脚本异常。真实音源可用性还依赖其服务、曲目与权限。

旧版发布记录及上游界面截图见 [ListenFree 上游](https://github.com/Tabris-Ayanami/ListenFree-desktop)。本目录只保留当前 0.3.8 打包所用的更新说明；历史版本应从对应 Git 修订构建。
