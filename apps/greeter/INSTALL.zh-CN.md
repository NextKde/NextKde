# 正式安装与回滚

这两个入口与 `/run` 临时测试分开。本页命令由用户明确要求编写；本轮只进行了源码打包和隔离故障测试，没有实际切换宿主显示管理器。

## 安装

在仓库根目录以自己的普通账户执行，脚本仅在安装阶段调用 sudo：

```sh
./tools/install-greeter.sh --check
./tools/install-greeter.sh
```

默认安装独立 Greeter，备份原配置与 systemd 别名/启用链接，禁用原显示管理器的开机启动并启用发行版 `greetd.service`；当前桌面仍运行，**重启后生效**。本机原管理器为 `plasmalogin.service`，脚本运行时查询，不硬编码成 SDDM，也不卸载 Plasma。认证成功后仍启动既有 Plasma Wayland 会话。

Greeter 是 QML/Python 应用，没有自身 C++ 目标；构建检查 Python 语法、校验可信共享主题哈希并生成有限文件的独立 bundle，再安装到 `/usr/local/lib/kos-greeter/app`。不编译/安装天气、音乐等无关应用，也不自动安装系统依赖。依赖需预先具备：发行版 greetd、greetd PAM、非 root greeter 账户、Quickshell、KWin Wayland、KScreen、Plasma Wayland、systemd/logind、D-Bus、Python/Pillow。不会改写 PAM 或自动加 KWallet hook。

若仍在临时测试中，安装预检会拒绝。先保存工作，从 Ctrl+Alt+F3 的文字 TTY 执行：

```sh
sudo python3 /home/wwt/Downloads/NextKde/tools/rollback-greeter.py
```

恢复原管理器、重新登录后再正式安装，不能叠加临时 runtime mask 与持久配置。

需要立即切换时，保存工作并从**文字 TTY3**执行以下命令；它会结束当前桌面：

```sh
./tools/install-greeter.sh --activate-now
```

默认 Greeter 位于 VT1，文字恢复 TTY 必须不同。图形终端或管道执行立即切换会拒绝。`--files-only` 安装 app/greetd 配置而不改变服务 enablement；这是安装与开机选择分离的可选模式，与 `--activate-now` 互斥。

安装写入系统用户级 `kos-shell.service` 路径 drop-in，让已有 T11 Shell 找到独立安装的 Cover；仅 daemon-reload 当前调用者的用户管理器，不重启 Shell、不导入全局认证/DBus环境。该 drop-in 不包含令牌。Shell 自身需已有 T11 模块，脚本不顺带升级整个桌面；历史安装中未接入门控的 Shell 只能依靠独立 Cover 超时撤罩；本轮初装和更新会预检并拒绝不兼容 Shell。当前共享 Shell 仍不支持同 UID 的并发桌面。

## 通用显示默认

随应用安装的 `config/outputs.json` 使用空输出覆盖清单，不包含个人 EDID、固定分辨率、240 Hz 或 1.5 倍缩放。默认选择设备报告的受支持推荐模式，推荐不可用时采用受支持当前模式，并保留已有有效缩放、位置和旋转；两者均不可用则报告无可用输出。HDR/VRR 和主屏优先级仍按首版显示策略处理。

需要机器专属模式时，由管理员配置 `/etc/kos/greeter/outputs.json`，格式见 [显示契约](../../docs/kos-greeter/contracts/machine-outputs.md)。该文件优先于应用默认配置，缺失或校验失败时使用通用策略。它是管理员独立配置，不由 Greeter 安装/升级生成，也不在 app 回滚时自动删除。本次已在虚拟机通过显示规划9项及假KScreen控制器10项回归；未执行实际模式切换或物理显示器验收。

## 更新已安装版本

直接再次运行：

```sh
./tools/install-greeter.sh
```

已有有效安装快照时自动更新，无需先卸载。通过 Linux 原子目录交换替换完整 app，删除旧版源码中已移除的文件；app 替换事务失败恢复旧 app，下一次执行自动处理未完成事务；随后独立服务策略迁移失败只恢复原策略/receipt，app 可能已升级，详见“认证失败与后台恢复”。原位升级要求 app 与恢复快照处于同一文件系统，不满足则在替换前拒绝。断电恢复仍未实机验证。

升级保持原开机选择：曾用 `--files-only` 安装的版本不会因默认更新被启用。更新不接受 `--activate-now`；已有持久启用时也不能用 `--files-only` 改成禁用。当前账户公开图按构建时的明确同意刷新，无同意或 `--no-wallpaper-sync` 撤回当前账户副本，其他账户副本保留。同包被跳过时，壁纸续期/撤回仍使用 `--refresh-wallpaper`。

配置/服务链接被管理员修改、快照不完整或回滚未完成时拒绝自动覆盖。自动更新 app 源码/资源并沿用原恢复入口；本轮新增托管 greetd 恢复策略迁移是服务 drop-in 的明确变更，使用独立可恢复事务，详见“认证失败与后台恢复”。不升级完整 Shell、系统依赖或 PAM，不改变开机选择与原管理器备份。

## 回滚

Greeter 正在运行或存在其新登录会话时，从文字 TTY3执行：

```sh
./tools/rollback-installed-greeter.sh
```

源码目录移动或删除后，仍有两个 root 管理的独立恢复入口：

```sh
sudo /usr/local/sbin/kos-greeter-rollback --rollback
sudo python3 /var/lib/kos-greeter-install/rollback.py --rollback
```

`--status` 可从普通终端查看安装快照，不修改服务：

```sh
./tools/rollback-installed-greeter.sh --status
```

回滚停止已装 greetd，清理本次新增的 greetd/logind 会话（保留安装前同一 boot 的会话及其他非 greetd 会话），恢复原 greetd 配置、原 drop-in/恢复入口、systemd 开机链接和必要的 getty 状态，重新启动原管理器并核验 active，再删除已装 app、公开壁纸副本及私有快照。重复回滚无害；不能恢复已经退出的窗口或未保存数据。

快照位于 `/var/lib/kos-greeter-install`，0700；配置备份为0600，保存之前不修改服务或配置。相同 bundle 重复安装跳过 app 替换，但仍检查/迁移恢复策略；检测到不同 bundle 会自动原位更新为当前本地源码，不自动拉取远程源码。升级保留首次安装的原管理器备份、服务启用状态和会话清理基线，不重启 greetd/当前桌面，新版在下一次登录使用。回滚检测到管理员后来修改了管理配置/别名时拒绝覆盖；服务恢复失败保留快照和 app，修正原因后可重试。不要在安装/回滚中手动编辑相关 unit/config。

greetd daemon 意外退出（包含 exit=0）使用 `Restart=always` 重建，`StartLimitIntervalSec=infinity` 与 `StartLimitBurst=3` 限制总启动次数（含首次）；达到失败上限后 `kos-greeter-recover.service` 调用同一恢复代码。它不自行检测仍运行但不可操作的图形界面，本轮 UI 的可见重连/有限监督负责部分前端异常；硬件故障、断电及真实管理器恢复仍需实机验证。

## 壁纸公开副本

默认构建仅读取调用账户已有的明确同步同意及 KOS 当前静态选图；无同意不发布。该图在认证前向其他使用者可见，登录前只读取 root 管理副本，不打开 home。图片经过有限大小校验与去元数据，副本放在独立 app/public-display，回滚一起删除。`--no-wallpaper-sync` 可在安装时跳过公开图。

永久安装版的公开副本**保留到主动更新或撤销**，不再每天过期而恢复深蓝背景；临时测试版仍默认 24 小时过期。没有自动刷新服务，改变选图后使用以下命令更新登录界面的副本：

旧版安装须先运行 `./tools/install-greeter.sh` 升级，再使用以下刷新命令；新安装程序会明确拒绝向旧版消费者写入新版永久副本。

```sh
./tools/install-greeter.sh --refresh-wallpaper
```

它重新读取当前账户的同意与选图，不重新启用管理器；同意已撤销时清理该账户旧 manifest/版本。也可直接撤回已装公开副本：

```sh
./tools/install-greeter.sh --refresh-wallpaper --no-wallpaper-sync
```

这条命令撤回当前已装副本，不改变你桌面的原图或本地偏好。其他账户副本保留；刷新后如在登录中版本变化，旧版本消费者按既有契约降级，不冒充逐帧连续。

## 验证边界

打包、语法、文件系统事务及模拟 systemd/logind 故障测试已执行，初次安装独立审查记录见 `../../docs/kos-greeter/reviews/persistent-install.md`；自动更新的35项隔离验证与独立审查见 [更新证据](../../docs/kos-greeter/evidence/automatic-upgrade/REPORT.md)和[更新审查](../../docs/kos-greeter/reviews/automatic-upgrade.md)。未实际安装、重启、测试物理 TTY/PAM 或开机登录；不把模拟测试当作完整 T14/A19 系统集成验收。

## 密码框玻璃与 KWallet 自动解锁修复（2026-10-12）

密码框采样其所在窗口的同源静态壁纸，保留高斯模糊、圆角和高光；移除双重蓝色染色并减弱焦点边框。软件渲染或效果模块不可用时仍使用可读的回退底色。隔离渲染已验证实际 WallpaperHost、data URL 和真实 shell 中的采样，实机观感仍须更新后确认。

本机日志显示 `pam_kwallet5(greetd:session): not a graphical session, skipping`。greetd 的 PAM 会话早于 Plasma 图形会话，已有 `auto_start` 并不足够。独立修复脚本为 optional auth/session 钩子补充 `force_run`（KDE 模块在 auth 阶段解析参数），保留原配置并生成 root 专属备份，不保存或接收密码。安装器仍不自动改写 PAM。

在本仓库普通终端执行：

```sh
./tools/install-greeter.sh
sudo python3 tools/fix-greetd-kwallet.py
```

更新不会重启当前桌面。退出后重新用账户密码登录，检查密码框是否透出当前壁纸，并打开 Chrome 验证钱包是否自动解锁。钱包密码须与账户登录密码一致；本轮未访问钱包内容，也未执行真实认证测试。

PAM 备份路径由脚本输出，位于 `/var/backups/kos-greeter/greetd-pam-*`。需要撤回时用 `sudo cp -p` 将该次备份恢复至 `/etc/pam.d/greetd`；Greeter app 回滚不自动撤销这次独立 PAM 修复。

## 登录交接版本同步（2026-10-12 修复）

Greeter 独立升级不会自动升级桌面 Shell。缺少 T11 就绪协议或新版本组件帧门控的旧 Shell，会被安装/更新/`--check` 预检拒绝，并显示缺失文件。此前仅 Greeter 安装完整不能推导桌面侧也包含 T1–T14。

在仓库根目录，以桌面普通用户执行：

```sh
python3 tools/sync-greeter-shell.py --check
python3 tools/sync-greeter-shell.py
./tools/install-greeter.sh
```

第一条列出新增、更新、移除文件及备份位置，不修改安装目录。第二条仅同步 `~/.config/quickshell/kos/desktop` 和可信 `Kos/Ui`；保留 Kos 原生插件、其他 apps、platform/data 二进制、Shell 根入口及用户配置。它把 shared QML symlink 转成真实文件，不留下指向源码树的安装链接。覆盖上述目录里的手工 QML 改动，先检查列表。

同步使用同文件系统暂存和目录 rename，每个目录替换为完整新目录；异常时恢复两个旧目录，成功保留 `~/.config/quickshell/kos-shell-backup-时间-随机值/`。多目录切换不是断电事务。生产 `kos-shell.service` 已设置 `QS_DISABLE_FILE_WATCHER=1`，当前会话不重载；新文件在下次 Shell 启动/登录生效。此命令不重启进程、不修改服务/显示管理器/PAM，也不安装其他应用。

需要恢复 Shell 时，先停止 Shell，再从打印的备份中恢复 `desktop` 和 `Kos` 两个目录；不要在其运行并开启文件监听时手工逐文件恢复。Greeter 仍使用原独立回退入口。

## 登录 VT 诊断输出修复（2026-10-12）

生产 Greeter 和认证后的用户入口在运行检查/启动子进程前，将 stdout/stderr 接到 libsystemd 的 journal stream，分别使用 `kos-greeter-session`、`kos-user-session` identifier；stdin 仍是原来的 TTY，固定启动 argv、进程/信号关系不变。Greeter 的独立 KWin、dbus、Quickshell，以及用户 startplasma/Cover 继承这些输出，不向登录 VT 写初始化/退出日志。系统服务托管的用户 KWin 本来就使用 journal，本修复没有改它。

```sh
journalctl -b -t kos-greeter-session -t kos-user-session -o short-monotonic
journalctl --user -b -u kos-shell.service -o short-monotonic
```

固定事件 `KOS_SESSION_PHASE GreeterCompositorStarting/PlasmaStarting/CoverSupervisorStarting` 和 Cover 的 `SocketConnected` 可用于定位加载画面出现之前的阶段；帧提交仍不等于 scanout。`--check` 诊断模式继续直接输出，便于安装预检。

journal 初始化不可用时丢弃 stdout/stderr，并尝试发送固定 syslog 故障码，不向 VT 回退。入口和 Cover 自有诊断写入遇到断线也安全降级，不因诊断异常中断固定启动；连 `/dev/null` 打开/重定向失败时关闭 fd1/2，并静默处理 Python 诊断。生产子进程保留 SIGPIPE 忽略，避免仅因日志管道关闭而被该信号终止；子程序自行更改信号或将写入错误视为致命的行为不能由入口保证。已启动子进程的 stream 无法由父进程事后更换，journal 断线可能丢失其后日志。stream 使用标准阻塞写语义，API 初始化/写入不承诺硬实时期限。不会启用认证协议 debug 或记录认证数据。

入口仅在 fd0 确认是继承的 Linux `/dev/tty1`–`tty63`、KDGETMODE 成功且重新打开的是同一设备时清除该 VT 的旧文本/滚屏缓存。它不切 VT、不清理 PTY 或别的终端、不修改显示模式。来自内核、greetd/PAM 或其它进程的独立输出仍可能出现；消除它们需要另行定位。两 KWin 接管期间的黑屏不因日志重定向而自动消失。本批无显示管理器/PAM/全局服务更改，正常独立 app 更新后下次登录生效。

## 认证失败与后台恢复（2026-10-12）

错误认证后保留登录画面、清空响应，再建立新的认证会话。Quickshell 在 auth_error 后自动 cancel；若 greetd 已清掉失败 worker、该 cancel 返回普通错误，本界面只在明确的认证失败恢复阶段重试，其他后台错误不一律忽略。后台异常或等待超时保留可见提示及“重新连接登录服务”按钮，不再1.8秒自动退出到黑屏。按钮只重建Quickshell UI，保持原Greeter KWin；UI入口最多启动3次（包括首次），不无限重连，不重启已启动的用户桌面。

安装/更新还会迁移托管 greetd drop-in：Restart=always、RestartSec=1、StartLimitIntervalSec=infinity、StartLimitBurst=3。它覆盖daemon意外exit=0，包括本机这次“greeter未创建会话退出”后的正常退出码；3次总启动预算包括第一次启动，达到限制后OnFailure使用原恢复入口。人工systemctl stop/回退停止不会被自动Restart打断。预算可由reset-failed显式重置，systemd卸载unit时计数也可能清除，不宣称跨开机永久计数。

迁移只daemon-reload，不restart/切换当前会话；同bundle更新也检查策略。它使用单独迁移记录保存旧drop-in和receipt，失败恢复原策略/receipt，不覆盖首份原管理器备份。app升级与策略迁移是两个可恢复事务；后者失败时app可能已经升级，但原策略被保留。旧恢复实现遇到policy-updating阶段仍可按首份文件快照回退。

如果登录已经卡死，在文字TTY3恢复（这些操作会重启登录入口，别在正常桌面随意执行）：

```sh
sudo systemctl restart greetd
```

若报告start-limit-hit，先执行：

```sh
sudo systemctl reset-failed greetd
sudo systemctl restart greetd
```

要回原显示管理器，使用 `./tools/rollback-installed-greeter.sh` 的正式入口；原备份保留。`register-default-apps.py`只注册应用、MIME、按钮和sycoca缓存，不是登录恢复命令；随后重启恢复不能归功于该注册脚本修复PAM/greetd。

## 登录 KWin 退出崩溃与专用配置（2026-10-13）

登录入口在Greeter UID的可信0700运行时目录创建私有配置/缓存/data目录，明确关闭包括kos_bridge、scale在内的桌面效果。密码框QML玻璃和既有输出同步保留；专用环境不传给认证后Plasma wrapper，不读取桌面kwinrc，不修改账户HOME。配置准备失败退出70，交给既有有限恢复策略；`--check`只读，不创建这些目录。

通过现有 `./tools/install-greeter.sh` 更新可安装新helper；已有安装更新不会重启当前桌面，新入口在下一次Greeter会话生效。本批没有安装或重启。runtime缓存由logind UID runtime生命周期清理，同UID其他会话或linger可能延后回收，不能保证compositor退出就立即删除。

项目kos_bridge源码同时修复了已删除窗口清理与活窗口卸载恢复。Greeter installer不编译/安装这个C++插件；插件需独立构建更新，不能替换当前已加载的`.so`后热重载。本批仅在 `/tmp/kos-bridge-exit-crash-build` 编译，未安装；登录配置隔离本身可先随Greeter app更新生效。

编译、生产场景Item离线回归与96项Greeter隔离测试通过；实际登录、DRM/VT连续背景和黑帧时长仍未测。证据及测试隔离事故记录见 [修复报告](../../docs/kos-greeter/evidence/exit-crash-fix/REPORT.md)，不能将本批理解为已保证零黑帧。
