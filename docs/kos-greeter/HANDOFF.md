# KOS Greeter 代理交接

日期：2026-10-12。关联 PR：https://github.com/SuceV587/NextKde/pull/185 ，源分支在 skjsbsnq/NextKde 的 codex/kos-greeter。原工作区 /home/wwt/Downloads/NextKde 仍是 codex/notification-center-stacks，存在其他未提交改动，不能整体提交或切换。PR 更新使用独立 checkout /tmp/nextkde-pr185-update；以远端最新提交核对，不把本地旧分支当作 PR 基线。

## 首先读取

完整读取 docs/kos-greeter/ 下的 README.md、tasks/README.md、AGENTS.md、REVIEW_POLICY.md、constraints.md、acceptance.md，以及 apps/greeter/INSTALL.zh-CN.md。T01–T14 有实现，但任务表中缺少实机证据的项目不能标为全部验收通过。每批变更须由未参与实现的子代理独立只读审查，保存最终摘要和审查记录。

## 用户问题与当前优先级

2026-10-13追加：用户明确要求调用独立子代理修复。最新exit-crash-fix批次交付bridge窗口删除/卸载生命周期修复与Greeter专用效果配置/缓存，真实插件编译、离线生命周期回归及96项Greeter隔离测试通过；最终审查见reviews/exit-crash-fix.md，证据见evidence/exit-crash-fix/REPORT.md。未安装或重启，实际登录及黑帧未测。当前优先验证登录KWin正常退出，再追底层持帧；今天及昨晚两次成功登录的旧Greeter KWin均有相同AnimationEffect析构→bridge清理→几何回调SIGSEGV，不能继续假定旧KWin已经正常退出。

本批首次旧session-output测试只mock execv漏拦新execve，意外启动KWin；缺失runtime导致socket初始化失败退出139，完整记录保留。随后修复全部入口mock并加硬失败守卫，经独立审查后重跑通过。宿主greetd/Plasma进程与会话保持，无fixture残留；不得将首次失败计为通过或移除这段事故证据。

用户希望输入密码后连续显示加载背景，等真正桌面就绪再上滑揭开。现状曾是密码框转圈 → 黑屏 → 终端文字 → 黑屏 → 壁纸加载 → 上滑。文字问题用户已确认改善，黑屏仍存在。

最新安装后还出现认证提示错误、随后黑屏和文字卡住，用户从 Ctrl+Alt+F3 执行 register-default-apps.py 并重启后进入桌面。该脚本仅应用/MIME注册，不能认定它修复登录；重启会重新启动 greetd。优先确认登录恢复稳定，再继续底层黑屏工作。

只读 boot -1 a40c9f9c62104da59f8e6831d6c629e5 的日志：PAM AUTH_ERR → Quickshell 自动 cancel_session 收到普通 error（描述 Connection refused）→ 原 UI 延迟退出 → greetd 正常退出0。旧 Restart=no 与 OnFailure 无法恢复退出0。该描述不是已证明主 socket 断开；AUTH_ERR 也不能证明用户手误。故障没有进入用户 wrapper/Plasma 阶段。

## 已完成的四批修复

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
