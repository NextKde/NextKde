# 独立 NextKde 应用

当前应用目录、第三方来源及后台更新机制见 [签名目录说明](SignedCatalog.zh-CN.md)。下文保留安装边界与历史发行/验收记录。

**安装边界：原生版与 Flatpak 版允许共存。** Settings 的“安装／打开／卸载”只看当前
Flatpak 库存；原生程序、桌面入口、源码安装记录均不得阻止查询、计划或安装。
旧原生清理是独立可选操作，绝不是安装 Flatpak 的前置条件。
卸载入口：点击应用图标或名称展开详情 →“卸载”→确认；仅删除选中的用户级 Flatpak，
保留个人资料、配置和原生应用。系统级或多份 Flatpak 须由对应管理器明确处理。

Calendar、Calculator、Weather 合用独立的 `NextKde/kos-apps` 源码仓库与版本；
ListenFree 继续使用自己的独立仓库。
KMusic 改用统一 Flatpak 控制器（`org.nextkde.KMusic`），不再识别或打开旧原生安装。
推荐后端为下述用户级 Flatpak。显式选择源码安装时，Settings 与独立仓库随代码分发
同一份 `tools/app-installer.py`，只依赖 Python 3 标准库，不下载或执行替代安装器。

| 应用键 | 固定仓库 | 应用 ID | 可执行文件／桌面文件 ID |
| --- | --- | --- | --- |
| `calendar` | `NextKde/kos-apps` | `org.nextks.calendar` | `kos-calendar` |
| `calculator` | `NextKde/kos-apps` | `org.nextks.calculator` | `kos-calculator` |
| `weather` | `NextKde/kos-apps` | `org.nextks.weather` | `kos-weather` |
| `listenfree` | `NextKde/ListenFree` | `org.nextkde.ListenFree` | `listenfree` |

Todo 已整合进 Calendar 的提醒事项视图，不再提供独立启动入口。新版安装器不接管旧 Todo
所有权；只有单独显式旧版清理器处理经确权的旧 Calendar／Todo 产物。

最后一列是可执行命令；前三款新版原生和 Flatpak 桌面文件均用应用 ID，例如
`org.nextks.calendar.desktop`；旧桌面身份不作为启动后备，ListenFree 原生命名不变。
签名目录可指定 GitHub owner/repository，不能指定任意下载 URL、命令、可执行文件名或安装根目录。

前三款共用 VERSION／commit／Release，但各有独立包和源码清单，构建时只选
`-DKOS_APPS=<app>`。旧 `org.nextkde.Calendar`、`org.nextkde.Calculator`、
`org.nextkde.Weather` 是不同的旧应用，不是升级来源。允许 breaking change：新版 source
所有权、原生配置／资料／状态及 Calendar 服务均隔离，不读取、复制或合并旧 profile。
Settings 只管理当前 ID，已移除 remove-retired。旧程序及个人资料由单独的
`tools/maintenance/purge-legacy-apps.py` 人工显式删除，默认仅预览；无法确权的 core／系统文件和共享资料
保留并报告，不猜路径删除。参见 [边界、确切路径与清理用法](ProfileMigration.md) 和
[人工验收矩阵](ProfileMigrationAcceptance.md)。旧的三个单应用 GitHub 仓库已删除，
改用 NextKde/kos-apps；本次 breaking 修改尚未发布签名 Release。

## 历史原生生命周期证据（2026-11-05）

本表及下文生命周期记录针对此前 ee0175f4 候选及当时 core，不代表当前 breaking 工作树。
旧到新所有权升级／资料回读不再是产品要求；历史未完成的回读／重装项不是当前待办门禁。
不声称当前边界或清理器已获运行验收。历史“通过”仅限记录的 VM 路线，不代表已发布 Latest。

| 验收项 | Calculator | Calendar | Weather |
| --- | --- | --- | --- |
| 全新隔离目录冷编译／安装、重复安装／已最新检查、离线卸载 | 通过 | 通过 | 通过 |
| 真实历史 0.1.0 → 0.2.0 程序／所有权升级及卸载 | 通过 | 通过 | 通过 |
| 新安装版本读取真实旧业务资料 | 未执行：计算历史／偏好 | 通过：一条日程和待办 | 通过：城市列表、选中城市、单位 |
| 卸载保留真实业务资料文件 | 未执行 | 通过 | 通过 |
| 历史源码重装／旧资料回读 | 未执行（要求已撤销） | 未完成（要求已撤销） | 历史通过 |

Settings 实际交互与普通桌面激活仍未验收。整个 NextKde 历史升级／卸载／Plasma 恢复／重装，
因缺少已核实的系统恢复点而阻塞；这些未完成门禁不使上述单项通过结果失效。

## GitHub 签名 Flatpak 单文件包（尚未正式发布）

发行路线为：独立应用仓库 → GitHub Release 的 `.flatpak` 附件 → Settings／`kos-apps`。
不要求自建公开 NextKde OSTree 应用源，也不以上架 Flathub 为前提。不承诺 Discover 自动发现
GitHub 包更新。Flatpak 管理文件及 ref，外部 Flatpak 工具能卸载同一份安装；Settings 每五秒
复查本地状态。唯一用户级安装可离线卸载，普通卸载保留数据与 runtime；系统级或多份安装须先消除歧义。

前三款使用 `<appId>.flatpak-release.json`，ListenFree 保留 `flatpak-release.json`；
每个应用在同一 Release 中有独立附件。schema 2 包含 appId、稳定数字版本 X.Y.Z、源码 revision
和架构表；每个包锁定 ref、OSTree commit、附件名、字节大小、SHA-256、原始 metadata 及其摘要、
安装大小、runtime 和必需扩展。开发者签名可选；目录指定 publisher 时，清单原始字节和包内
OSTree commit 均必须验签，失败不降级。应用发布者公钥由签名目录条目提供，不再是 core 的固定应用数组。
五款种子条目保留主指纹 `3751DC833ED4BC7E797A9766ADF7411B531A56B4`，种子存在不代表包已发布。
runtime 专用策略于 2026-11-05 按[官方安装文档](https://docs.flathub.org/docs/for-users/installation)
及其 HTTPS 仓库文件审核，接受 `https://dl.flathub.org/repo/` 与完整主指纹
`6E5C05D979C76DAF93C081354184DD4D907A7CAE`，主密钥于 2027-06-14 到期。
此项仅授权运行库，不接受 Flathub 应用更新；未知额外主密钥、关闭校验或其他 URL 仍拒绝。
用户点击安装／更新后，缺少依赖来源时由 Settings 自动准备，不弹配置窗口、不要求终端操作。
仅查询库存或检查更新不改来源；正常下载确认仍保留，签名包安装／更新仍待人工验收。

正常更新检查读取签名目录内嵌的固定发行清单，验证签名、版本及本机架构 stable ref，不扫描应用仓库；直接 GitHub 发现仅用于测试模式。
元数据上限 256 KiB、签名 64 KiB、包 2 GiB；下载只允许固定 GitHub HTTPS 端点与附件 CDN，
最多五次重定向，不接受任意地址或凭据。元数据单次 30 秒、发现总预算 90 秒；包下载空闲 30 秒、
单次十分钟、最多三次、下载总预算三十分钟。仅瞬时网络／5xx 有限退避重试，签名／散列／TLS／404／
限流不重试。取消覆盖请求与退避等待，清理半包；大包流式写入，部署前重验签名清单和散列。
日志不记录带签名参数的 CDN 地址。

候选绑定真实本地安装快照。低于已装 AppStream 版本、无法解析已装版本、同版本不同 commit 均拒绝；
首次安装没有历史基准，不声称完全防止旧签名重放。更新要求现有 commit 的已配置发布者签名通过核验，或无发布者条目匹配本客户端安装记录；
origin 必须是没有在线 URL 的本地 bundle 来源，不能接管第三方在线源安装。
新安装不检查原生可执行文件／桌面入口／ownership，也不迁移原生资料；Flatpak 系统级／多份／其他分支或架构／
并发状态变化都不会静默解决。

下载包之前，后端通过隔离且有时限的 `kos-apps` 子进程检查签名包事务的销毁，不执行安装。
部分 libflatpak 软件包（包括未打补丁的 1.16.6）错误地把公钥 `GBytes` 当作 GObject 释放，
导致事务销毁时崩溃。探测失败或崩溃时返回 `FLATPAK_INCOMPATIBLE`，而不是让 Settings 崩溃
或留下部分部署。请更新到包含[上游修复 95b70b71](https://github.com/flatpak/flatpak/commit/95b70b71e366c78d16abadaa7e33f6d6bcdc01f4)
的发行版 Flatpak/libflatpak 软件包。探测实际行为而非硬编码版本号，支持发行版回移补丁；
不运行事务、不改用户 Flatpak 安装。直接手动使用 Flatpak CLI 同样需要上游修复，不能靠省略
认可公钥或签名校验规避崩溃。

修改安装的事务在固定伴随 `kos-apps` 进程中执行，保留原有包／发布者／runtime／所有权检查。
取消先请求正常终止，两秒后强制结束不响应的伴随进程；进程退出并复查真实库存前仍保持忙碌。
这也覆盖 libflatpak 下载 runtime 元数据时未传递 GCancellable 的路径。中断不代表回滚，真实库存才是准数；
伴随程序缺失、崩溃或返回损坏协议时报告 `RESULT_UNKNOWN`，不虚报部署成功。

包的 app/ref/commit 必须与签名清单一致，禁止嵌入在线 origin 或 runtime-repo URL；显式向 libflatpak
传入认可公钥，认证前后检查完整计划。目标必须是锁定 commit 的 INSTALL_BUNDLE，拒绝其他应用或卸载。
按 ID／架构／分支检查已安装的 Flatpak 运行库，优先用户级、再系统级；匹配且来源受认可则复用，
不要求再配置同一份用户源。原生 Qt／KDE 库不计入复用。计划记录安装范围、origin、commit，
部署前再次核对；只明确加入缺少的依赖，不顺带升级已有兼容组件。
缺少组件时自动准备已审核的用户级 Flathub 来源，精确 URL、公钥及 commit／summary 校验仍须符合策略。
不覆盖已有源。用户只需正常确认下载，复用项显示“已安装，无需下载”，不计入新增占用。
来源准备可能在取消安装后保留；不承诺取消会回滚配置。

libflatpak 在事务 ready 前可能创建**无在线 URL 的本地 origin 记录并导入传入公钥**，拒绝／取消后可能留下，
不假称会回滚；这不等于需要托管应用源。下载加部署总时限为六十分钟，伴随事务进程按上述方式受监督。
结束后始终复查实际 ref／commit，不承诺整笔事务或已部署 runtime 原子回滚。
隔离 runtime-ready 事务结果见下文；交互式桌面验收仍未完成。

manifest 不是完整的最终权限清单。本次开发构建所用 KDE 6.11 runtime 还继承了只读
`xdg-config/kdeglobals`，以及 `com.canonical.AppMenu.Registrar`、`org.kde.kconfig.notify`、
`org.kde.KGlobalSettings` 的 talk 权限。每次发布须检查最终导出 metadata，不能宣称完全没有
宿主配置文件或 session-bus 访问。

### 发行用源码与构建记录

三款共用出包脚本与独立 ListenFree 脚本已增加 flatpak-builder 自带的 Sources 导出：应用包之外，
另存并签名 `APP_ID.Sources-VERSION-ARCH.flatpak`，保留声明的模块源码输入。
同时保留固定 revision 的应用源码归档、补丁、构建清单、最终权限 metadata 和文件清单；
`build-info.json` 记录构建用用户级 SDK/runtime ref 与 commit，构建期间 commit 变化则拒绝签名。
`SHA256SUMS` 递归记录交付材料散列，并另有发布者独立签名。完整材料另打成直接签名的
`release-materials.tar.gz`，保留嵌套补丁路径；归档不递归包含自身。旧源码协议的 `app-release.json`
也由原有准备器按同一 revision 的 GitHub codeload 原始字节生成，避免新版成为 latest 后破坏源码入口。

截至 2026-11-05，这套脚本已从同一受审源码 `ee0175f4` 准备 Calendar、Calculator、Weather 的签名
应用／Sources 候选。专用 VM 已核验清单／材料签名、校验和与包身份；生产 `kos-apps` 能识别已安装
commit 的签名，并在卸载后保留隔离资料哨兵。这些离线检查仅对相关进程使用带上游清理修复的
libflatpak，未替换系统软件包。另一个隔离 runtime-ready 目录中，三应用均完成生产后端的签名发现／下载／安装、
当前版本与重复操作检查、offscreen 沙箱启动、持续 503 后保留安装、卸载及资料／runtime 保留。
发现使用进程内 TLS 夹具与真实发布者签名材料，不是真实已发布 Latest。Calculator、Weather 已通过外部
Flatpak 卸载／定时库存刷新／重新安装；Calendar 在加入事务进程监督后也通过这条流程。
通过的重跑不能解释先前传输超时。offscreen／portal 与可选 compositor 模块警告仍保留。
Calculator 另已通过两版本签名 metadata 夹具的生产发现／下载、受监督安装／更新、已最新检查和卸载，
资料与 runtime 保留。该流程按独立用户操作分段，部署之间通过标准查询预热 runtime 缓存；两个版本
仍使用同一份可执行源码。先前在诊断时限取消的冷缓存流程仍未完成，不因这次通过而改记成功。
这不是真实历史可执行版本／资料格式升级验收。Calculator 源码路线另已用真实原生产物完成安装、
重复安装／已最新检查、清理预览及离线卸载，资料保留；使用保留的 codeload 下载材料和持久 CMake
源码／构建路径夹具。随后另用全新隔离目录，在不改构建命令／路径、不复用编译产物的条件下，约 134 秒完成
冷配置／编译／安装，并启动实际安装的程序，完成重复安装／已最新／清理预览／离线卸载，资料保留。
下载仍使用已核验的原始 codeload 材料，不是真实已发布 Latest；先前短诊断超时仍保留为未完成尝试。
随后 Calendar、Weather 也分别用全新隔离目录完成未修改的冷编译／安装，耗时约 247、206 秒，
重复安装／已最新／清理预览／prune／离线卸载均通过，资料哨兵保留，受管启动入口和构建状态清除。
这两次未启动实际窗口或验证业务资料；三应用共用同一已核验原始归档，但各自使用空构建目录，
不代表已发布 Latest、未配置系统依赖的空白操作系统或历史升级。
随后另已用真实历史 `0.1.0`（`9432b21d`）及其原始安装器安装 Calculator，再用当前安装器更新到
`0.2.0`（`ee0175f4`）。两版均全新编译并启动实际程序，二进制散列不同；所有权与桌面启动器从
退役身份切换为 `org.nextks.calculator`，重复安装／已最新检查与离线卸载两版受管程序均通过，
原始资料哨兵保留。下载使用已核验归档替代尚未发布的 Release。这验证的是源码程序／所有权升级，
不是真实历史 Flatpak 更新，也不代表真实计算历史／偏好设置跨身份兼容。
Calendar 另已完成真实原生源码 `0.1.0`（`ce8b36b5`，原安装器）到 `0.2.0`（`ee0175f4`，当前安装器）升级，
两版全新编译且可执行文件散列不同；所有权切换为 `org.nextks.calendar`，旧受管 Todo 程序／桌面激活链接清除。
实际旧版 PIM 服务在私有 bus、隔离资料目录创建了一条日程和待办；旧服务退出后，新服务读回的两条记录
逐字段一致，`calendar.ics` 与 `metadata.json` 散列不变。重复安装／已最新检查与离线卸载均通过，
两版受管程序及激活状态删除，真实业务资料文件完整保留。历史归档来自合并仓库保留的精确提交，
不是已删除旧仓库的原始发布字节。这只证明上述记录的原生源码／资料兼容，不代表历史 Flatpak 身份迁移、
全部 PIM 资料形态、Calendar 窗口或桌面激活验收。
Weather 也已完成真实原生源码 `0.1.0`（`de8f9769`，原安装器）到 `0.2.0`（`ee0175f4`，当前安装器）升级，
两版应用全新编译、可执行文件散列不同，所有权／桌面入口切换为 `org.nextks.weather`。实际旧后端保存的
选中城市、两城市列表与英制单位，由新版安装的后端从同一隔离原生状态路径读回，偏好字段一致。
两版 Go 后端散列相同，不把它当作后端资料格式已变化的证据。天气请求刻意阻断，重启会改变天气状态／
时间戳及整文件散列。重复安装／已最新检查及离线卸载通过，两版受管程序和入口删除，真实 state／snapshot
文件保持卸载前散列。这不覆盖 Weather 窗口交互或历史 Flatpak 身份迁移。
Weather 随后在卸载状态下约 197 秒完成全新源码重装，安装过程未改动保留的真实 state／snapshot 文件；
重装后端读回的原城市列表、选中城市与单位一致。再次离线卸载清除了受管程序和激活状态，
两份资料文件保持此次卸载前散列。
Calendar 真实 PIM 写入也已通过应用自己发布的沙箱摘要到达 core 组件；卸载保留资料，但组件不再暴露该摘要。
Weather 已发布自己的摘要，无当前读数时组件正确显示缺失，窗口正常退出后未留沙箱后端进程。
临时前缀另安装了同一上游修复的 Flatpak CLI，未替换系统版本；三应用的未修改桌面 Exec 命令均能在
加入隔离 offscreen／应用截图参数后启动并正常退出。这不等于真实桌面点击或单实例激活验收。
延长应用自带截图窗口后，Weather 已取得真实在线天气，发布 ready 摘要，当前读数与生产组件 payload 一致；
随后受监督卸载保留资料和 runtime。三个签名包也在 VM 的真实 Wayland 会话中启动并正常退出，生成了非空的应用自有截图，且没有残留沙箱进程。
目视可见 Calculator／Weather 内容。Calendar 在强制软件后端时截图为黑色；去掉该覆盖后界面正常，
配合隔离激活 bus，原生渲染窗口已显示保留的合成日程。这不代表软件渲染支持、普通桌面激活、portal、
通知或单实例验收。真实签名 Calendar／Weather 安装与夹具自有的模拟原生启动器并存时，组件会屏蔽歧义资料；
卸载 Flatpak 保留该启动器和沙箱资料，原生来源不会消费沙箱摘要。这不覆盖两个真实运行应用或 user/system 重复安装。
Settings 实际操作验收和稳定 Release 仍未完成。

发行时要保留完整目录及相对路径，不能只上传应用包而丢掉源码／补丁／构建材料。
Sources 包不是应用运行依赖，Settings 不会安装它。它也不自动提供外部 SDK/runtime 的对应源码；
完整性、实际链接配置及各组件许可／告知义务仍须维护者审核。

### 不通过 Settings 安装

推荐使用下面共用后端的 `kos-apps`。也可手工装包，但必须先通过受信 core 或独立认证渠道取得公钥，
在私有 keyring 中用 `gpgv` 核验清单原始字节的独立签名，再核验包大小／SHA256 及 app/ref/arch/commit。
不要信任与下载包一起提供的公钥，显式传入已认可公钥，禁止跳过校验：

```sh
flatpak --user install --gpg-file=/trusted/publisher.gpg ./application.flatpak
flatpak --user uninstall org.nextks.calculator
```

更新重复“核验后安装新版 bundle”。没有在线 origin 时，`flatpak update`／Discover 不能自动发现 GitHub 新包。
普通卸载不用 `--delete-data`。公钥、同源签名候选和 runtime 策略已准备；完整 runtime／桌面体验与真实版本升级仍待验收。

## 各应用打包状态

下表保留**旧 ID** 的历史准备结果。新 `org.nextks.*` 已在托管 CI 原生编译并运行注册回归。
固定源码 `03c92edd0b0c9f54013ba8c63ee1e591482eb928` 的三款应用也已在
[run 41945820505](https://github.com/NextKde/kos-apps/actions/runs/41945820505)
全部完成 KDE 6.11 SDK 的 app／Sources 导出。
这些未签名候选不代表签名、沙箱生命周期或生产交付已验收。

| 应用 | 本地准备 | 仍缺 |
| --- | --- | --- |
| Calculator | 身份选项、manifest、签名出包脚本、仅产物工作流；本机与 KDE 6.11 SDK 编译完成，已导出未签名开发包 | 经审核的固定源码版本、签名资源、正式 Release、沙箱人工验收 |
| Weather | 私有后端／数据身份选项、固定 Go 工具链、签名出包脚本、仅产物工作流；本机与 KDE 6.11 SDK 应用／后端编译完成，已导出清理构建工具后的未签名开发包 | 经审核的固定源码版本、签名资源、正式 Release、沙箱人工验收 |
| Calendar | 独立 PIM／激活／私有存储、读库前所有权锁、后台 portal 授权、固定依赖 manifest、出包脚本／工作流；本机与 KDE 6.11 SDK 编译完成，已导出未签名开发包 | portal／后台／重登录验收、有限 ICS 交换及宿主 widget 限制告知；经审核的固定源码版本、密钥和正式 Release |
| ListenFree | 身份／MPRIS／独立凭据命名空间、可选功能边界、声明式依赖与补丁、必要许可证检查、出包脚本／工作流；本机与 KDE 6.11 SDK 应用／sourcehost 编译完成，已导出清理构建目录后的未签名开发包 | 实际依赖／许可／对应源码交付审核、portal／音频／凭据验收；经审核的固定源码版本、密钥和正式 Release |

身份选项本机编译不等于完成 Flatpak 出包或验收。共享后端已接线，发布者公钥已接入本地 core，
并已审核 runtime 专用来源策略，但尚无正式签名 Release；上述准备不代表生产安装已经可用。

### 待人工完成的 bundle 验收

以下场景均未因本机编译或旧源码安装器记录而算作通过。应使用专用用户／隔离环境、
认可的 runtime 来源、经审核公钥和签名包；不要复用个人资料、凭据或生产安装。

| 场景 | 人工需要确认 |
| --- | --- |
| 首次安装 | Settings、`kos-apps`、外部 Flatpak 的用户级 ref／commit 一致，导出桌面入口可启动 |
| 新稳定 Release | 显式检查能发现签名新版，无需升级 core；相同 commit 无变化，降级和同版本替换被拒绝 |
| 下载失败 | 断网、404、限流、TLS 错误、停滞／慢速传输和临时 5xx 有明确且可操作的提示；重试／时限有效，半包不部署 |
| 取消／空间不足 | 分别在退避、下载、部署时取消，检查真实安装状态和半包；尚未发生部署变更时旧应用保留，磁盘满有诊断 |
| 非法包 | 清单／包篡改、未知密钥、错误签名、错误 app／arch／branch／commit 和越界重定向均在应用部署前拒绝 |
| runtime／归属冲突 | 缺失或未认可 runtime、意外事务／远端、系统／重复 ref 和外部 Flatpak 并发变更不被静默接管 |
| 外部卸载 | Settings 卸载后检查外部 Flatpak，再反向操作；Settings 刷新状态，个人数据和共享 runtime 保留 |
| Calendar | 后台权限拒绝／部分允许／超时／允许、关窗、重新登录、提醒激活与重复服务拒绝；原生数据不受影响 |
| ListenFree | portal 选文件后重启访问、播放／跳转／音频设备、MPRIS、凭据保存失败／退出账号和网页登录不可用提示，使用隔离非个人输入 |

逐项记录实际版本／commit、可见错误文案和诊断日志路径。截图、工作流文件或编译成功
不能代替生命周期验收。未发布的跨身份资料复制和 Calendar 最终化已撤除；
见[兼容与手动过渡说明](ProfileMigration.md)。已加入本地只读组件摘要联动，非资料迁移或提醒接管；契约与待人工验收项见 [WidgetIntegration.md](WidgetIntegration.md)。

## 统一 Flatpak CLI

`kos-apps` 与 Settings 链接同一后端，随 core Settings 安装，不需要图形会话：

```sh
kos-apps status --app calculator
kos-apps check-update --app calculator
kos-apps install --app calculator --yes
kos-apps update --app calculator --yes
kos-apps uninstall --app calculator --yes
./tools/kosctl install apps status --app calculator
```

修改安装前要求终端确认或显式 `--yes`；无 TTY 且未给 `--yes` 时拒绝执行。SIGINT／SIGTERM 请求取消，
等待真实状态复查，不谎称一定回滚。stdout 输出一个 JSON 结果，包含实际状态和诊断日志路径；进度写入
stderr。`tools/install-apps.sh` 默认使用此后端，缺公钥或包不自动配置在线源／回退源码；批量执行遇错停止，保留已完成项。

下述源码 CLI 仍是显式的历史兼容／开发入口，不代表 Discover 软件包。如需经包装脚本使用，指定
`./tools/install-apps.sh --backend=source status --app calculator`。版本选择及构建依赖检查仅属于源码模式。
不自动迁移或复制个人数据。

## 命令接口

```sh
python3 tools/app-installer.py --app calculator check-update
python3 tools/app-installer.py --app calculator check
python3 tools/app-installer.py --app calculator install --version 0.2.0
python3 tools/app-installer.py --app calculator status
python3 tools/app-installer.py --app calculator update
python3 tools/app-installer.py --app calculator uninstall
```

可选参数 `--version X.Y.Z` 用来确认发现的最新稳定版本与请求一致，不是任意 tag 或
revision 选择器。版本必须是三个数字组成的语义版本，不接受预发布或构建后缀；比较时
按数字比较，拒绝降级，也拒绝在版本号不变时替换 revision。

- `check-update`：发现并验证版本元数据，不构建。
- `check`：额外下载并校验源码，执行真正的 CMake configure，检查应用开发依赖；
  不编译、不安装。
- `install`／`update`：配置、构建、安装到不可变版本目录，成功后再发布。
  已安装相同 revision 时幂等返回；`update` 要求先有受管理的安装。
- `status`／`uninstall`：完全离线。卸载只删除经校验属于安装器的入口链接、
  不可变版本和所有权清单；保留应用设置、用户数据和诊断日志。

安装器不使用 sudo，不安装系统包，不自动重跑失败构建，也不启动应用。
请自行通过发行版包管理器安装 Python 3、CMake、Ninja、C++ 编译器和应用文档列出的
开发依赖。缺少工具时会列出名称；配置失败返回 `DEPENDENCY_UNSATISFIED`，并给出
仅当前用户可读的完整日志路径。

ListenFree 还需要校验和固定的私有音频／JavaScript SDK。请按独立仓库文档，使用其
SDK 准备脚本将 SDK 构建到稳定目录，并在启动 Settings 或 CLI 时导出 `LISTENFREE_SDK`。
源码安装器不会自动构建这份 SDK；缺失时以 `DEPENDENCY_UNSATISFIED` 停止，配置日志
会给出准备指令。后续更新也需要相同的 SDK 环境。

## 结果协议

标准输出为 JSON Lines。每次操作恰好以一条 `type: "result"` 结束，此前可以有
`type: "progress"`。子进程输出只写入权限为 0600 的日志，不混入 JSON 协议。
所有记录包含 `schemaVersion: 1`、`appId`、`action`、`stage`、`type`、`success`、
`code`、`version`、`revision` 和对象 `details`。

`details` 提供 `installed`、`managed`、`available`、`version`、`revision`、
`currentVersion`、`currentRevision`、`desktopFile` 和 `root`。
其中 `available: true` 只表示本地安装引擎支持该应用，**不表示远端已发布版本**。
成功的 `check-update` 额外提供 `latestVersion` 和 `updateAvailable`。
版本发现失败仍然是失败，不能用商店内置版本号伪造安装状态；已知的本地安装信息会保留。

冲突返回 `EXTERNALLY_MANAGED`，并以 `installed: true`、`managed: false`、
`externalInstallation: true` 标记外部安装；找到固定桌面文件时提供 `desktopFile`。
安装器不会接管、升级或卸载外部安装。

退出码：0 成功，2 预期失败（依赖、版本、冲突、状态），3 子进程超时，130 取消，
1 未预期的安装器错误。无效命令参数也输出一条 JSON 结果；`--help` 正常打印帮助。

## 发布格式与信任边界

以下为旧式**源码安装后端**的协议，不是目录 Flatpak 更新器；其版本发现端点固定为：

```text
https://api.github.com/repos/NextKde/<仓库>/releases/latest
```

必须是已发布、非草稿、非预发布的稳定 release，tag 为 `vX.Y.Z`，并且有且仅有一个
属于所选 kos-apps 应用的 `<appId>.app-release.json` 附件（ListenFree 仍用
`app-release.json`）。清单示例：

```json
{
  "schemaVersion": 1,
  "appId": "org.nextks.calculator",
  "version": "0.1.0",
  "revision": "0123456789012345678901234567890123456789",
  "archiveSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

示例散列值必须替换为实际 SHA256。可选 `archiveUrl` 必须严格等于：

```text
https://codeload.github.com/NextKde/<仓库>/tar.gz/<revision>
```

每份 JSON 响应最多 256 KiB，压缩源码最多 256 MiB，展开源码最多 1 GiB／100,000 项。
先校验 SHA256，再解包；拒绝路径穿越、符号链接、硬链接、特殊文件和重复路径。
压缩包必须只有一个顶层目录，并在根目录提供 CMake 项目。

初始 URL 只接受固定仓库的 HTTPS GitHub/API/codeload 路径；重定向另外允许 GitHub
固定附件域名，拒绝其他主机、非 HTTPS、URL 内凭据和非标准端口。
连接读取超时为 15 秒；Unix 主线程信号为完整请求提供元数据／源码每次尝试
45／300 秒的绝对时限，覆盖 DNS、重定向和响应头。整个版本发现过程（两份 JSON
及其重试）另外受 90 秒总时限约束；嵌套时限不会延长外层时限。
瞬时网络失败最多尝试三次并有限退避；TLS、完整性、404 和限流错误不重试。
404 返回 `RELEASE_UNAVAILABLE`；429 或 GitHub 403 限额耗尽返回 `RATE_LIMITED`，
在 GitHub 提供时附带 `retryAfter` 和 `rateLimitReset`。

**信任来自固定 NextKde GitHub 仓库的 HTTPS 发布，不是密码学发布签名。**
SHA256 将源码字节与该发布清单绑定，但不提供独立的发布者身份保证。
CMake 是可执行的构建逻辑，安装操作意味着信任白名单发布者；构建并未沙箱隔离。
不要通过改白名单来安装不可信来源。

## 存储、启动入口与所有权

前三款 KEY 为完整 `org.nextks.<app>` ID，ListenFree 仍为 `listenfree`。
不接管旧短键根目录。新版原生业务／配置路径和单独旧版清理见
[边界文档](ProfileMigration.md)。

- `${XDG_DATA_HOME:-~/.local/share}/nextkde-apps/KEY/versions/REVISION/`
- `.../KEY/current`：指向已发布不可变版本的原子切换链接
- `.../KEY/ownership.json`：版本与入口链接的准确所有权清单
- `${XDG_STATE_HOME:-~/.local/state}/nextkde-apps/KEY/{lock,logs/}`
- `~/.local/bin/EXECUTABLE`：经过 `current/bin` 的受管理链接
- `$XDG_DATA_HOME/applications/ID.desktop`：经过 `current` 的桌面入口链接
- `$XDG_DATA_HOME/dbus-1/services/NAME.service`：只为应用实际安装的服务创建

CMake 安装前缀直接使用最终版本路径，不是安装后再改名的临时路径。
发布前保留旧 `current`；配置、构建、安装失败会清理候选目录，旧版本继续可用。
升级成功后仍保留旧版本，直到显式 prune 或卸载。普通取消会向整个子进程组发 TERM，必要时再发 KILL；
配置、构建、安装各自的子进程时限为 30 分钟。

不会覆盖已有用户桌面文件、命令或服务文件；会检查 PATH 以及系统 XDG 桌面／D-Bus
位置中的发行版或 Nix 入口。Calendar PIM 服务必须直接使用不可变前缀中的
受管理可执行文件，不能通过可能指向另一安装的 systemd 服务启动。
当前服务／命令实际冲突不会被替换；旧 org.nextkde.Kos.Pim1 名称本身不再是相同激活身份，
但旧 kos-pim-service 命令占位仍须人工处理。

应用状态目录中的私有 `transaction.json` 在修改前记录明确归属的候选版本及新旧清单。
后续调用取得锁后先恢复中断操作，离线状态检查／卸载也一样：所有权元数据提交前
回滚到旧版本，提交后向前完成新版本发布和旧服务入口清理；中断卸载按日志清单继续。
写入日志／清单和修改发布目录后进行持久化刷新，再丢弃恢复记录。
因此提交后的取消可能保留已经安装的新版本，不会假称始终保留旧版本。

日志损坏、入口被其他程序替换，或没有有效恢复日志的所有权清单／当前链接损坏时，
都拒绝猜测归属。不要通过删除或篡改清单强行继续。多文件卸载可恢复，但不是瞬间整体
原子操作；磁盘故障或外部替换仍可能需要人工恢复。直接 SIGKILL 安装器可能留下后台
构建进程，普通 TERM 取消才有清理机会。不自动回收旧版本；显式 cleanup-plan/prune 保留 current 和一个回退版本，见兼容说明。

## 人工验证

实际体验前使用隔离 HOME/XDG 目录。确认版本发现与缺依赖提示，安装后通过桌面入口
启动应用，升级到更新版本，取消构建后确认旧入口仍可用。离线检查状态、卸载后确认
应用用户数据保留。已有发行版／Nix／核心 PIM 服务入口时应报告冲突而不是替换。
安装器自身不要求重启合成器。
