# KOS Greeter 代理交接

更新日期：2026-10-13。**当前状态：三层显示交接实验实现、隔离验证和专用文件安装器已交付并通过独立复审；未由助手安装或启用，真实登录和 NVIDIA 黑屏仍未验收。** 用户已获得安装命令，没有反馈确认执行结果。不能把代码通过、提供命令或文件安装等同于实机黑屏解决。

## 本轮授权与改动

用户最初要求只研究、不修改代码，随后明确要求独立子代理实施并由另一个独立子代理审核，又要求安装命令和更新交接文档。后续实施授权取代原先只研究的范围；附带文档本身不授权部署。当前文档更新按 AGENTS.md 独立审查，下面历史记录中的一次免审要求仅适用于当时那次交接，不适用于本轮。

改动集中在 `apps/greeter/experimental/drm-handoff/`，不是登录 QML 动画调整，也没有覆盖发行版源码或已运行的系统二进制：

| 部分 | 实际实现 | 交付位置 |
|---|---|---|
| KWin 6.7.5 | 旧端在 UI 撤场前绘制可信纯背景，等待每输出 PresentationFeedback；正常退出时有条件保留最终 DRM 状态。新端启动背景十五秒自撤；ARM 三秒超时、nonce/CONFIRM、取消与资源校验 | `kwin-v6.7.5-bootstrap.patch`、父目录 README |
| greetd 0.10.3 | PAM worker 返回真实 UID 后才调用固定 root 授权器；私有 seqpacket FD；固定用户会话入口白名单；交接有效时避免 worker KD_TEXT/终端清屏 | `systemd/greetd-0.10.3.patch` |
| systemd/logind v262 | 十秒有界 VT 保留、后继死亡/取消恢复；原子 VT marker 和启动恢复；恢复失败保留 marker 跨 GC 并拒绝覆盖；可信控制器接管后清理 | `systemd/systemd-v262.patch` |
| 协调与入口 | 只读 PNG FD、当前公开资源/撤销验证、PRESENTED→Prepare→CONFIRM→READY；过期回滚；VM 专用 Greeter 入口和 Plasma wrapper unit 示例 | `systemd/kos-handoff-authorize` 等 |
| 安装器 | 复用已编译产物、重定位私有 ELF、SHA/系统依赖验证、root 管理独立前缀、文件升级/回滚/卸载；升级中断也能恢复 previous | `tools/install-greeter-handoff.py`、`.sh` |

root helper、KWin 和公开资源只使用固定可信路径；不截图密码窗口，不记录凭据，不将私有控制 FD 传给 UI。正常热拔线清理没有全局禁用；现有 CloseFB 不是本轮新加的修复。静态保帧不保证 spinner 连续运动。

## 最终验证与独立审核

- KWin 和 wrapper 编译链接通过；最终八个双虚拟输出场景及十四个 native publication parser 场景通过。
- greetd release 构建和十二项测试通过；logind 构建和八组状态/故障测试通过，包含 SIGKILL、恢复失败重试及取消失败跨 GC。
- 真实 dbus-run-session 的私有 FD 到达/不泄漏 UI 测试通过。真实 VirtualBackend KWin 与真实授权器协议函数的正常提交、延迟 Prepare 过期回滚通过；**bus 是明确的假对象，不是三个真实守护进程同时登录。**
- 真实产物打包、只读 check、wrapper --check，以及隔离安装/权限/升级/回滚/卸载/篡改拒绝测试通过。没有重新全量编译以完成安装器。
- 实施：`/root/implement_frame_handoff`、`/root/complete_coordinator`；独立只读审核：`/root/review_frozen_handoff`。先前发现的 P1/P2/P3 在各自限定的实验实现和文件安装范围关闭，不批准据此部署或关闭实机门槛。

证据入口：[KWin 最终报告](evidence/drm-frame-handoff/KWIN-REPORT.md)、[三层实现复审](evidence/drm-frame-handoff/INDEPENDENT-REVIEW.md)、[安装器复审](evidence/drm-frame-handoff/INSTALLER-REVIEW.md)。初次失败和中途冻结保留在 `KWIN-HISTORICAL-REPORT.md`，不要把旧失败当最终状态，也不要删除事故记录。

KWin 最终补丁 SHA256：`bded1a76f0f0bd4b27913a5fa49e35eac1d9cfae674148e1d6cbe5bf9ecf60a0`；systemd 最终补丁 SHA256：`95e1d995bfb4b100589fff8a3cbeff0b0eff908451987105a7f80457b7831056`。KWin 文件/产物清单见 `evidence/drm-frame-handoff/KWIN-SHA256SUMS`、`KWIN-artifacts.json`；协调及安装器清单分别在实验 `systemd/` 的 `FROZEN-SHA256.json`、`INSTALLER-SHA256.json`。安装器追加文件后总清单有更新，旧审核记录中的总清单摘要是当时快照；不要要求历史总清单摘要始终匹配新增后的清单。

## 已提供的安装命令与边界

普通用户执行（助手未执行）：

```sh
cd /home/wwt/Downloads/NextKde
./tools/install-greeter-handoff.sh --check
./tools/install-greeter-handoff.sh
```

默认从 `~/.cache/nextkde-builds/drm-handoff` 读取当前已编译产物，只在安装阶段调用 sudo，目标 `/opt/kos-handoff`。**不会自动启用修复、切换登录器、重启服务或覆盖 `/usr/bin`。** 需已有 root 管理的 `/usr/local/lib/kos-greeter/app`；依赖 python3、patchelf、readelf、ldd、sudo 及匹配的系统库。构建缓存缺失/系统依赖改变会拒绝。原有 `tools/install-greeter.sh` 仅更新普通 app，不安装这次三层补丁。

操作和文件回滚见 [安装器说明](../../apps/greeter/experimental/drm-handoff/systemd/INSTALL.md)。`rollback` 需要 previous；全新安装用 `uninstall`。已有 previous/displaced 不覆盖。启用的 VM 必须先恢复原服务配置，才能回滚或卸载文件。

systemd 的 `auto_features=disabled` 构建是隔离原型，不能作为发行版 systemd 的直接替代。说明中的启用命令仅限一次性 VM，不能在当前桌面执行。不需要录屏才能继续开发或隔离验证；物理显示连续性仍须取得实机证据。

## 接手优先级与工作区

1. 先读取本页最新段落、实验 README、systemd/README、INSTALL.md、最终审核记录，按限定范围核验文件/产物摘要。不无理由重跑已通过的全量编译。
2. 只读确认用户是否实际安装、安装 manifest 和当前各服务二进制；尚无部署反馈，不能沿用旧 PID 或 boot ID。当前运行服务仍可能是发行版版本。
3. 下一阶段先在可恢复的一次性 VM 完成真实 PAM、三个真实守护进程共同登录和故障恢复验证，再考虑 NVIDIA 实机 DRM/VT 连续性；这轮未交付可直接启用宿主的完整发行版修复包。
4. installed 根选择已有授权器测试，但真实 KWin installed 根选择/Live 撤销尚未单独行为验收；旧端退出后硬件持帧撤销、多 GPU、输出切换与物理黑帧未测。A16/A18/G5 等原实机门槛仍不关闭，不承诺零黑帧。

工作区 `/home/wwt/Downloads/NextKde` 当前分支 `codex/notification-center-stacks`，有无关修改，不能整体提交、切分支或直接 pull 覆盖。构建缓存为 `/home/wwt/.cache/nextkde-builds/drm-handoff/`。用户随后授权将本分支尚未提交的 Greeter/greetd 改动提交到 PR 185；以远端 `codex/kos-greeter` 的 `5bff331e6ecbbdce9877f4aca017a527ad2db986` 为追加基线，保留其 Ubuntu Plasma/输出策略/TTY 冲突修复及 #188 拆分。使用独立 checkout `/home/wwt/.cache/nextkde-pr-checkouts/pr185-update` 处理，原工作区索引和无关改动不整体提交。当前 PR 仍 OPEN（本次只读核验），新实验交付对应此基线之后的追加提交；下方 `60934dc` 属于早先批次。不要自动 restart greetd/logind/KWin、切 VT 或修改 PAM。

## 历史交接快照（本轮之前）

以下原文保留用于追溯。其“当前”“本次”、一次免审、尚未实施底层交接及下一步优先级均对应旧批次；有冲突时以上最新状态为准。旧 PR/boot/PID/硬件版本须重新核验，历史文本不是新的执行授权。

更新日期：2026-10-13。PR：https://github.com/SuceV587/NextKde/pull/185 。已推送 `60934dc82e52b554d60595426397b8b6232e874d` 并更新PR说明；当时仍OPEN，接手重新核对远端。源分支为 skjsbsnq/NextKde 的 codex/kos-greeter。

原工作区 `/home/wwt/Downloads/NextKde` 仍是 `codex/notification-center-stacks`，有无关未提交修改，不能整体提交、切分支或直接pull覆盖。旧 `/tmp/nextkde-pr185-update` 已不存在；新独立checkout是 `/home/wwt/.cache/nextkde-pr-checkouts/pr185-update`，提交后干净，只交付本批已审32文件，没有带入通知中心/Dock等前置修改。

**本轮用户明确要求“写一个交接文档，不要审查，因为没有额度了”。仅本次交接文档免审：不调用子代理，不部署，不再推送PR。此前实现与编译已有独立审查，本次没有新增审查结论。用户明确指令优先于下文历史审查规则。**

## 当前结果与接手优先级

- exit-crash-fix已进入PR：bridge窗口删除/卸载生命周期修复、Greeter私有配置/缓存、安装清单及测试防穿透守卫。证据 `evidence/exit-crash-fix/REPORT.md`，审查 `reviews/exit-crash-fix.md`。96项Greeter隔离测试通过，实际登录/物理黑帧仍未验收。
- 用户随后要求编译bridge，已完成。产物 `/home/wwt/.cache/nextkde-builds/kos-bridge/kos_bridge.so`，SHA256 `fa89e5ff87c0cb7b0715a6aa22b38f92829d805ba6732a89678c1646c768babe`。RelWithDebInfo、x86_64、依赖无缺失。构建审查在该目录 `compile-review.txt`。规则433项检查及生命周期测试通过；CTest显示3/3，其中AppStream因未安装跳过，不能称三个检查全部实际执行。
- 助手没有安装/热重载这个插件，也未重启KWin。用户已获手工安装与Greeter更新命令，但没有确认实际执行、重启或黑屏改善。不要把“给过命令”当部署证据。
- 下一步先只读确认已安装版本、实际登录旧Greeter KWin是否正常退出，再量化剩余黑屏。已通过的离线回归不需无理由重复，不得宣布零黑帧。

## 安装与后续正常更新

本机插件路径 `/usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so`，桌面kwinrc已有 `kos_bridgeEnabled=true`。用户获以下步骤，助手没有执行；逐条运行，失败即停。备份不覆盖已有备份，新文件先暂存再rename，避免原地写坏当前已加载inode：

```sh
sudo cp -n /usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so /usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so.bak
sudo install -m 0644 /home/wwt/.cache/nextkde-builds/kos-bridge/kos_bridge.so /usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so.new
sudo mv -f /usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so.new /usr/lib/qt6/plugins/kwin/effects/plugins/kos_bridge.so
```

保存工作、正常重启后生效，不热重载当前KWin。独立构建目录的安装前缀为 `/home/wwt/.cache/nextkde-builds/kos-bridge-stage`，CMake布局为 `prefix/lib/plugins/...`，不可误以为直接 `cmake --install --prefix /usr` 会安装到本机 `lib/qt6/plugins/...`。

用户问过合入后的常规操作：合入NextKde main后，在干净main检出pull最新源码，`./tools/kosctl install`默认自动编译/安装bridge与核心KWin插件，不设置 `KOS_BUILD_KWIN_PLUGINS=OFF`。Greeter仍需单独 `./tools/install-greeter.sh` 更新，核心安装不代替它；Greeter更新不编译C++ bridge，但登录私有配置禁用bridge，因此登录端隔离修复不要求先安装新bridge。

## 新研究结论与下一步边界

本机今天及昨晚两次成功登录的旧Greeter KWin存在相同退场SIGSEGV：AnimationEffect析构释放窗口引用 → windowDeleted → bridge恢复外观删除Item → 同步几何回调重新进入动画。具体失效对象没有core调试确认，不能把全部黑屏归因于崩溃。scale默认开启且关闭窗口包含缩放/透明度两条动画，是优先嫌疑但未证明唯一触发者。空配置不会禁默认效果，已交付helper显式关闭包括bridge在内17个效果；QML自己的玻璃/动画保留。

底层持帧还应覆盖更早的UI撤场：shell.qml收到launched立即Qt.quit，背景surface一起销毁，旧KWin结束前可能先渲染空场景。四处待跟踪点为登录壁纸撤场、旧KWin输出清理、logind VT文本恢复、新KWin首帧。须在UI销毁前武装可信交接，并确认每输出纯背景已实际呈现；frameSwapped不是scanout。本次未实施持帧、logind协调或资源预取。

今天LaunchRequested32.944538 → PlasmaStarting35.304702 → SocketConnected37.513658 → Cover FrameSubmitted38.343904，5.399秒是软件事件间隔，非录像黑帧时长。socket到首资源消息0.617秒包含进程/QML启动、校验及通信，不能全部算PNG耗时或承诺并行全部节省。greetd等Greeter退出后才启动用户会话，不能让Greeter等待新桌面就绪再退出。

历史冻结摘要对应当时交付。本次仅HANDOFF更新使此文件不再匹配旧exit-crash-fix/SHA256SUMS的文档摘要，属于预期；代码没有变化，不改写已发布PR的证据或原审查记录。下面保留历史背景与恢复约束。

## 首先读取

完整读取 docs/kos-greeter/ 下的 README.md、tasks/README.md、AGENTS.md、REVIEW_POLICY.md、constraints.md、acceptance.md，以及 apps/greeter/INSTALL.zh-CN.md。T01–T14 有实现，但任务表中缺少实机证据的项目不能标为全部验收通过。正常实现批次按已有规则独立审查；本次仅交接文档按上方用户明确指令免审。

## 用户问题与当前优先级

2026-10-13追加：用户明确要求调用独立子代理修复。最新exit-crash-fix批次交付bridge窗口删除/卸载生命周期修复与Greeter专用效果配置/缓存，真实插件编译、离线生命周期回归及96项Greeter隔离测试通过；最终审查见reviews/exit-crash-fix.md，证据见evidence/exit-crash-fix/REPORT.md。未安装或重启，实际登录及黑帧未测。当前优先验证登录KWin正常退出，再追底层持帧；今天及昨晚两次成功登录的旧Greeter KWin均有相同AnimationEffect析构→bridge清理→几何回调SIGSEGV，不能继续假定旧KWin已经正常退出。

本批首次旧session-output测试只mock execv漏拦新execve，意外启动KWin；缺失runtime导致socket初始化失败退出139，完整记录保留。随后修复全部入口mock并加硬失败守卫，经独立审查后重跑通过。宿主greetd/Plasma进程与会话保持，无fixture残留；不得将首次失败计为通过或移除这段事故证据。

用户希望输入密码后连续显示加载背景，等真正桌面就绪再上滑揭开。现状曾是密码框转圈 → 黑屏 → 终端文字 → 黑屏 → 壁纸加载 → 上滑。文字问题用户已确认改善，黑屏仍存在。

历史安装后曾出现认证提示错误、随后黑屏和文字卡住，用户从 Ctrl+Alt+F3 执行 register-default-apps.py 并重启后进入桌面。该脚本仅应用/MIME注册，不能认定它修复登录；重启会重新启动 greetd。优先确认登录恢复稳定，再继续底层黑屏工作。

只读历史失败 boot a40c9f9c62104da59f8e6831d6c629e5 的日志：PAM AUTH_ERR → Quickshell 自动 cancel_session 收到普通 error（描述 Connection refused）→ 原 UI 延迟退出 → greetd 正常退出0。旧 Restart=no 与 OnFailure 无法恢复退出0。该描述不是已证明主 socket 断开；AUTH_ERR 也不能证明用户手误。故障没有进入用户 wrapper/Plasma 阶段。

## 此前四批修复（另有上方exit-crash-fix）

- login-handoff-fix：接受可信 session 树中的 kwin_wayland_wrapper socket peer；有限 Wayland sync 探测；桌面 provider/bar/Dock 首帧门控；独立 tools/sync-greeter-shell.py。用户此前已同步 Shell。
- session-output-fix：会话标准输出/错误转 journal，保留stdin及控制终端，安全诊断与失效回退；用户确认终端文字改善。
- handoff-latency-fix：wrapper 元数据流程和完整消费者验证分开，有限 canonical尺寸缓存，减少重复 PNG 编解码。局部 CPU 路径约节省2.15秒，不等于实机黑屏缩短。当前成功启动日志已看到引用阶段约0.625ms，证明该版曾安装。
- login-recovery-fix：认证失败后的自动取消错误保留UI并有限重建；真正后台异常保留画面、显式重连；固定命令 Python UI supervisor 保留 Greeter KWin；service Restart=always、infinity窗口总启动预算3含初次；已有安装独立策略事务迁移，保留原备份。最新源码已独立审核，但尚无用户反馈确认安装本批。

每批详情、证据及冻结摘要见 evidence/ 同名目录；审查见 reviews/ 同名.md。最新审查记录给出通过结论，REPORT 中冻结时的“待独立审查”不是当前最终状态。后续批次取代相应文件的历史摘要，不能要求所有旧 manifest 同时匹配新源码。最新登录恢复为44安装事务、5 UI监督、15真实QS+mock协议场景通过；真实PAM、daemon上限/OnFailure回原显示管理器未验收。旧rollback兼容仅隔离行为模型，未执行宿主旧root-only脚本。

## 部署和恢复

当前会话不要自动 restart greetd 或切换显示管理器。用户执行 tools/install-greeter.sh 更新，已有安装不重启当前桌面，迁移 daemon 策略。Shell源码更新需用户运行 python3 tools/sync-greeter-shell.py，查看INSTALL中的适用步骤。不要改 PAM；独立 KWallet工具不应隐式运行。

只有实际卡在登录入口时，从TTY3执行 sudo systemctl reset-failed greetd 后 sudo systemctl restart greetd。正式回退入口 tools/rollback-installed-greeter.sh 从文本TTY使用。sudo需要用户密码，不应读取凭据或代填。安装app和策略为分开事务，策略失败不保证app同时回旧版。

## 黑屏研究下一步

evidence/handoff-latency-fix/DRM-HANDOFF.md 给出底层三环方案。旧Greeter KWin结束到新Cover背景首帧是实际空档；frameSwapped只是提交，不是scanout。KWin v6.7.5已有CloseFB fallback RmFB，不能把添加CloseFB当新方案。退出时output清理/异步modeset、systemd262 logind vt_restore KD_TEXT及新KWin空首帧均可能覆盖保留画面，需跟踪定位。

实际内屏曾为NVIDIA RTX4070 card2/eDP-2，615.78.08 nvidia-open-dkms；AMD eDP-1 disconnected，fbcon为NVIDIA。接手时重新只读核验。trace-only patch已git apply --check，未编译安装；不要在真实KWin直接跳过全局hotplug清理。先独立前缀/隔离环境跟踪旧compositor清理、VT恢复、新compositor首帧，再设计有限超时和可恢复的保帧交接。此前无qemu/virsh、无现成VM镜像，/dev/kvm存在。

协议测试必须临时GREETD_SOCK、offscreen并清除宿主DISPLAY/WAYLAND_DISPLAY，绝不连真实认证socket。图形fixture只能发现自身虚拟父树socket，不能回退到宿主固定service；历史曾误显示短暂Cover，已修测试隔离并记录。不得凭隔离测试宣布零黑帧或真实认证通过。
