# KMusic App Store 安装协议 v1

本文说明 kos-settings 应用商店接入 KMusic 独立源码安装器时使用的协议。商店端的目录固定、下载校验和进程控制见[应用商店实现说明](../../apps/settings/app-store/README.md)。

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

## 验证与证据

仅在虚拟机或托管 CI 中运行测试。安装器契约测试位于本仓库 `tests/app-store/`；
它需要独立的 KMusic 源码，不自动下载，也不等同于商店的下载/安装端到端验收。
在 NextKDE 源码根目录运行：

```sh
KMUSIC_SOURCE_DIR=/path/to/KMusic python3 -m unittest discover -s tests/app-store -p test_kmusic_installer.py
```

默认查找与 NextKDE 仓库并列的 KMusic 文件夹；也可显式指定实际路径。
`run_kmusic_installation.py` 驱动安装生命周期和故障场景，`run-kmusic-container.sh`
负责容器内执行。`provision-kmusic-ci.sh` 仅为临时 CI 环境安装依赖，不属于分发给用户的安装器。

KMusic 的 `installer-matrix.yml` 工作流在托管 VM 内运行发行版容器，并固定测试套件提交。
检查实际工作流、镜像 digest 和上传的 JSONL/日志制品；不要把旧记录或启动工作流当成当前提交验收。
历史记录可查 [2026-10-22 工作流](https://github.com/NextKde/KMusic/actions/runs/39783294345)
及其[固定提交中的结果记录](https://github.com/NextKde/NextKde/blob/45d45dc63684125b84a773acb81ba982a75f65c3/docs/app-store/KMusicInstallerTestResults.json)。
机器生成的测试结果和本机交接信息不再复制到当前源码文档中。

容器中的安装成功或 offscreen 启动不能证明真实音频、凭据库、桌面交互或 GPU 视觉表现。
ARM64 实机、断电/SIGKILL 恢复、商店端完整安装/卸载流程需要各自的实际验收；
协议测试和历史工作流不能替代这些验证。
