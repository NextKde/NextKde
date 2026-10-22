# KMusic App Store 安装协议 v1

此文档位于 kos-shell/NextKde 仓库，供尚未实现的 kos-settings App Store 下载安装功能接入使用。

安装入口在 **KMusic 仓库**根目录 `install.sh`，实现：`packaging/installer.py`。商店必须一起分发这两个文件并保持目录结构，不能只下载一个入口文件。脚本不调用 sudo、apt、pacman，不安装依赖、不启动 KMusic、不操作桌面 Shell。

## 调用

```sh
./install.sh check
./install.sh install --version <40位小写完整提交SHA>
./install.sh status
./install.sh uninstall
```

以目标桌面用户执行，不支持 root。不要通过 shell 拼接用户输入；商店应以参数数组启动进程。只支持 `/etc/os-release` 的 ID 精确为 arch、ubuntu、debian，架构 x86_64、aarch64；衍生发行版不按 ID_LIKE 自动认定兼容。支持系统识别不代表已完成各发行版安装验收。

`--version` 是源代码提交标识，不是可移动分支，也不是 `latest`。商店可信目录必须固定安装器文件及目标 SHA；使用安装器的这个提交或之后包含安装规则的提交。源码来自 https://github.com/NextKde/KMusic.git ，检查实际 HEAD 与期望一致，并按 gitlink 固定递归子模块。不自动发布 release，不向远端推送源码。尚未推送的提交无法远程安装。

这是源码安装：目标机需要开发依赖。没有二进制包降级、PPA、AUR、依赖下载或第三方包安装。安装过程中会执行所选源码的 CMake 构建规则，所以目录中的 SHA 必须由商店维护者审核，不能接受任意来源输入。Git 提交校验不是发布者签名认证。

## 标准输入输出

不读取标准输入。stdout 仅 UTF-8 JSONL；每一行独立解析，每次正常结束或可捕获失败都产生且仅产生一个 `type=result`。进度不提供伪百分比：

```json
{"schemaVersion":1,"type":"progress","appId":"org.nextkde.KMusic","action":"install","stage":"build"}
```

商店本地化应依据 `code`、`stage` 和结构化 `details`，不要匹配 message 文案。保留原始 message 供诊断。阶段：arguments、bootstrap、check、download、build、install、uninstall。

缺依赖示例（版本仅示例）：

```json
{"schemaVersion":1,"type":"result","appId":"org.nextkde.KMusic","action":"install","success":false,"code":"DEPENDENCY_UNSATISFIED","stage":"check","message":"Required dependencies are missing or incompatible.","details":{"dependencies":[{"id":"taglib","required":">=1.12","installed":null,"reason":"missing"}]},"logPath":"/absolute/path/install.log"}
```

每项含 id、required、installed、reason；reason 为 missing 或 version_too_old。工具链编译探测失败以 installed="probe failed" 表示，详情看日志。能继续检查时一次汇总缺失项；基础工具不能运行时可能提前失败。Python 缺失时由 shell 返回同样的结果格式，action 为 unknown、stage 为 bootstrap，无日志文件。

成功：

```json
{"schemaVersion":1,"type":"result","appId":"org.nextkde.KMusic","action":"install","success":true,"code":"INSTALLED","version":"<40位SHA>","changed":true,"desktopId":"kmusic.desktop","logPath":"/absolute/path/install.log"}
```

相同版本且当前可执行文件存在时返回 ALREADY_INSTALLED、changed=false；仍先检查依赖。status 返回 OK、installed、version；它报告安装记录及路径状态，不证明运行库或图形环境工作正常。uninstall 返回 OK、changed、dataPreserved=true。check 返回 OK、distribution、architecture。

| 退出码 | code |
|---|---|
| 0 | INSTALLED / ALREADY_INSTALLED / OK |
| 2 | INVALID_ARGUMENT |
| 10 | UNSUPPORTED_PLATFORM |
| 11 | DEPENDENCY_UNSATISFIED |
| 12 | PERMISSION_DENIED |
| 13 | INSTALL_BUSY |
| 20 | DOWNLOAD_FAILED |
| 21 | INTEGRITY_FAILED |
| 30 | BUILD_FAILED |
| 31 | INSTALL_FAILED |
| 32 | UNINSTALL_FAILED |
| 99 | INTERNAL_ERROR |
| 130 | CANCELLED |

SIGINT/SIGTERM 尝试返回 CANCELLED 并清理暂存目录。SIGKILL、断电、解释器损坏等无法保证最终 JSON：商店若未收到 result，必须显示“安装中断/结果未知”，不能推断成功。stderr 留给解释器/系统级诊断，商店应同时收集。最终结果与非零退出码矛盾时按失败处理。

## 依赖检查

Python >=3.9；CMake >=3.21；Node >=22.19；Git、pkg-config、Make、C++20 编译器；Qt >=6.8 的 Core/Gui/Qml/Quick/QuickControls2/QuickDialogs2/Concurrent/DBus/Network/Sql/Svg/ShaderTools/Core5Compat；Qt6Keychain；TagLib >=1.12；libqrencode；GStreamer core/audio/pbutils 开发库。

还检查 QML 模块、SQLite/SVG 插件、Wayland 或 XCB 平台插件，以及 playbin、autoaudiosink、audioconvert、audioresample、vorbisdec、flacdec、mpg123audiodec。第一版要求以上具体解码元素，不自动寻找替代解码器。

检测实际能力，不用包名代替库检查。发行版包名及用户安装命令由商店自己的发行版映射负责；脚本不会自动执行它们。Qt/编译器不满足也属于依赖失败。check 会在临时目录执行 CMake 和极小 C++20 编译，不启动 GUI/音频，不证明真实音频输出、凭据库可用或应用视觉正确。

## 安装事务和路径

- 应用根目录：`${XDG_DATA_HOME:-$HOME/.local/share}/kmusic-app`。
- 每次构建产物存入 `versions/<SHA>-<唯一后缀>`；`current` 是原子切换的符号链接。
- 桌面入口：XDG data 下 `applications/kmusic.desktop`；图标在 `icons/hicolor/scalable/apps/kmusic.svg`。
- Exec 指向 current 下绝对路径，不要求修改 PATH；不提供系统级 `kmusic` 命令。
- 日志/锁：`${XDG_STATE_HOME:-$HOME/.local/state}/kmusic-installer`；日志权限 0600。
- manifest 保存版本、上一个版本路径和子模块版本；不保存账号凭据。

下载、构建、暂存完成前不切换 current。注册桌面入口或提交 manifest 失败时尝试恢复原链接。旧版本目录保留，不自动删除正在运行版本；正在运行的 Music 不被关闭。断电期间的多文件事务没有完全原子保证，不能将断电恢复等同于正常异常回滚。

遇到已有的非本安装器桌面入口/图标时拒绝覆盖。卸载仅删除本安装器的应用目录及其链接，不删除 Music 的配置、缓存、曲库、音频文件或系统凭据库。旧版手动安装在 ~/.local/bin 或系统目录的文件不会被卸载；可能仍有另一个系统级桌面入口。

## kos-settings 接入建议

1. 从可信应用目录获取 appId、完整 SHA、安装器文件及其校验值。
2. 用当前用户运行 check；失败时显示依赖列表和日志入口。
3. 点击安装后调用 install，按 stage 显示阶段，不凭构建日志猜成功。
4. 收到 INSTALLED/ALREADY_INSTALLED 且退出码为 0 后，更新安装状态；用户点击“打开”时通过桌面入口启动。
5. 同一应用操作串行执行；INSTALL_BUSY 提示已有操作。卸载成功后重新调用 status。

没有自动安装依赖选项；也不提供隐藏的忽略依赖参数。

## 验证状态

已在 GitHub 托管虚拟机中的 Arch、Ubuntu 26.04、Debian 13 容器完成安装成功及失败场景验证；Ubuntu 24.04 验证依赖过旧时拒绝安装。未在开发宿主机运行测试。测试文件位于 `tests/app-store/`，实际结果见下方记录。

## 本机交接路径

- kos-shell 仓库：`/home/amao/OneDrive/quickshell`
- 安装器仓库：`/home/amao/OneDrive/KMusic`
- 安装入口：`/home/amao/OneDrive/KMusic/install.sh`
- 当前测试是 KMusic 安装器契约单元测试，不是尚未实现的商店下载/安装端到端测试。

在虚拟机上，进入 kos-shell 仓库后运行：

```sh
KMUSIC_SOURCE_DIR=/path/to/KMusic python3 -m unittest discover -s tests/app-store -p test_kmusic_installer.py
```

默认查找与 kos-shell 仓库并列的 KMusic 文件夹；也可用 KMUSIC_SOURCE_DIR 指定实际路径。测试不自动下载 KMusic。

## 持续集成安装测试矩阵

KMusic 仓库 `.github/workflows/installer-matrix.yml` 在 GitHub 托管虚拟机内运行发行版容器，测试源码位于本仓库 `tests/app-store/`，由工作流固定完整提交引用。它不是宿主机验证，也不是三种发行版的完整桌面视觉验收。

| 环境 | 预期验证 |
|---|---|
| Arch Linux / x86_64 | 缺依赖失败 + 完整依赖后的真实下载/编译/安装/覆盖升级/卸载 |
| Ubuntu 26.04 / x86_64 | 同上 |
| Debian 13 / x86_64 | 同上；成功夹具显式预装官方 Node 22.19，不能把发行版默认 Node 20 当成满足条件 |
| Ubuntu 24.04 / x86_64 | 缺依赖及系统 Qt 版本过低时统一拒绝安装 |

`provision-kmusic-ci.sh` **仅用于临时测试环境**，由 CI 的 root 安装成功场景所需依赖；实际被测 `install.sh` 以普通用户运行，仍然绝不自动安装依赖。它们不是同一个脚本，也不应把测试环境准备脚本分发为商店安装器。

- 契约单元测试覆盖：支持/不支持平台、缺依赖/旧版本、参数/root/权限/锁错误、首次安装、重复安装、升级、下载/校验/构建/暂存失败、发布阶段回滚、取消、卸载与用户数据保留。
- 真实安装测试覆盖：实际 Git 固定提交和子模块下载、实际 CMake 编译、安装文件及桌面入口、动态库解析、无界面启动冒烟检查、两不同提交的覆盖升级、重复安装、下载/编译故障注入、锁冲突、目录权限、卸载幂等及非托管桌面入口保护。
- `results/unit.log` 是模拟契约测试；`missing/summary.json`、`old/summary.json`、`full/summary.json` 是实际调用脚本的结果，不能混为一类。每个调用都有 JSONL、stderr 和安装日志。
- `container-image.json` 记录实际镜像 ID/digest，便于追溯 Arch 滚动版本和可更新镜像标签。
- 尚不覆盖 ARM64 实机、断电/SIGKILL 恢复、桌面菜单自动刷新、真实音频输出或登录凭据库；不要依据安装成功推断这些能力通过。

当前结果以工作流及上传的证据为准；增加测试文件或启动工作流不等于通过。

## 2026-10-22 实际验证结果

[最终工作流：四项全部通过](https://github.com/NextKde/KMusic/actions/runs/39783294345)。
详细机器可读结果及镜像 digest：[KMusicInstallerTestResults.json](KMusicInstallerTestResults.json)。

- 被测 KMusic：`49264b0d45a6f8958e8d8b6eb4e5da1ee3e655d0`。
- 固定测试套件：`0a7edebf3991a7cf8326eb125b7bf88374a5298c`。
- 覆盖升级起始版本：`ab37baf98ec76f88b6204ac86ddb8d5d9f0fd03f`。

| 真实环境 | 契约单元测试 | 实际脚本测试 | 结果 |
|---|---:|---|---|
| Arch Linux | 19 项 | 缺依赖 3 项；安装生命周期及启动 17 项 | 通过 |
| Ubuntu 26.04 | 19 项 | 缺依赖 3 项；安装生命周期及启动 17 项 | 通过 |
| Debian 13 | 19 项 | 缺依赖 3 项；安装生命周期及启动 17 项 | 通过 |
| Ubuntu 24.04 | 19 项 | 缺依赖 3 项；旧依赖拒绝 3 项 | 通过（预期安装失败） |

Ubuntu 24.04 实测 Qt 6.4.2，正确返回 DEPENDENCY_UNSATISFIED，Qt6Core 的 installed 为 6.4.2、required 为 >=6.8、reason 为 version_too_old，未创建应用目录。这不是 Ubuntu 24.04 成功安装认证。

失败用例涵盖无效版本、缺 Python/依赖、旧依赖、下载/编译错误、锁冲突、权限拒绝、非托管桌面入口冲突；契约测试还注入校验、暂存/发布、取消和卸载失败，验证最终结果与退出码和旧版本保护。首次测试发现 Ubuntu/Debian 成功夹具缺 SVG 独立插件，补齐后通过；同时修正安装器对旧 Qt 错报 missing 的诊断。

启动冒烟测试仅在隔离环境运行 offscreen/software Qt，检查存活和 QML 启动错误，不模拟交互、不截图，不替代桌面、GPU、声音和视觉验收。
