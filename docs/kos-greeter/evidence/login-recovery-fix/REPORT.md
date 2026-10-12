# 登录可用性紧急修复

日期：2026-10-12。状态：源码/隔离验证已交付，待独立审查。停止新增黑屏优化，本批没有进一步改动资源降时逻辑。未部署、未重启真实服务/桌面、未触碰真实TTY/PAM或执行真实认证。最终清单见 SHA256SUMS。

## 真实证据与因果边界

只读上一boot -1 a40c…的greetd及kos-greeter-session完整相关日志：15.854 pam_unix authentication failure；17.546 greetd worker AUTH_ERR；17.547前端Idle后同毫秒Quickshell普通Greetd error描述“unable to send message: Connection refused”；19.353 WallpaperDestroyed；20.949 greetd check_children: greeter exited without creating a session，systemd随后Deactivated successfully。无用户wrapper/Plasma阶段，故障发生在认证/恢复链上；不能据此归咎图片优化，也不能完全排除安装其它副作用。

该Connection refused是**daemon发回的普通协议error描述**，不是日志已证明主daemon socket断链。已核对固定版本源码：Quickshell0.3.2收到auth_error先emit authFailure，再自动cancel_session；greetd0.10.3 cancel先configuring.take再请求worker cancel，worker已失效时可能返回拒绝，但context已清空，允许再create。Quickshell available是CONSTANT环境存在标记，原onAvailableChanged不存在、不能用于连接健康/重连。

原界面把普通onError一律视作致命并1.8秒Qt.quit；greetd未安排用户session时看见greeter退出结束主循环，0.10.3 main仅打印错误、最终仍正常退出0。托管服务Restart=no且OnFailure只覆盖失败，留下无人恢复的登录入口。这是源码支持并在同请求序列mock复现的恢复链；无法从PAM AUTH_ERR确认究竟密码、布局、输入法或其它认证条件，未读取/记录响应或试真实密码。密码字符串未trim，respond调用后即时wipe及phase防重复提交保持；本轮不宣称实机输入布局已验收。

固定源码URL/SHA见source-reference.json：[QS连接](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.2/src/services/greetd/connection.cpp)、[QS available](https://raw.githubusercontent.com/quickshell-mirror/quickshell/v0.3.2/src/services/greetd/qml.hpp)、[greetd context](https://raw.githubusercontent.com/kennylevinsen/greetd/0.10.3/greetd/src/context.rs)、[greetd main](https://raw.githubusercontent.com/kennylevinsen/greetd/0.10.3/greetd/src/main.rs)。

register-default-apps.py源码只处理desktop/MIME、按钮、缓存及sycoca，不调用greetd/PAM/登录恢复。用户随后重启成功不证明注册脚本修复登录；当前已成功启动引用阶段0.625ms由主代理复核，是上批降时生效的旁证，与此次认证恢复缺陷分开。

## 修复

1. 明确authFailureRecovery，仅“认证失败后Idle阶段收到自动cancel普通错误”保留UI/清空响应并有限重建；普通其它错误不宽泛忽略。不在signal回调内同步create，继续等待QS Inactive再重建，清除不存在的available信号handler。
2. 后台普通错误/真正断链后无响应/期限失败进入可见BackendUnavailable，停止spinner/自动重试，保持背景与提示，聚焦重连按钮。取消原1.8秒自动退出。按钮Qt.exit(75)，真实QS已确认透传退出码；致命窗口故障Qt.exit(70)，确认launch仍普通退出。退出0并不证明认证成功，最终scheduled session的权威始终是greetd。
3. kos-greeter-ui改成固定qs argv的Python supervisor，保留同一Greeter KWin，只重建UI，最多3次启动含首次；成功正常0退出交由greetd判定，非0有限重启。TERM/INT/HUP转发，2秒后强制回收无响应UI；日志用既有安全诊断，不捕获/记录认证协议，不打开debug。检查/正式bundle必须包含该入口。
4. 托管service改Restart=always/RestartSec=1，总启动预算StartLimitIntervalSec=infinity、Burst=3（含initial），失败上限OnFailure回原恢复入口。systemd人工stop不触发自动Restart。infinity防止慢失败绕过60秒窗口无限重启；reset-failed可显式重置，unit卸载也可能清计数，未声称跨boot绝对限制。
5. 新安装用新策略；已有安装包括相同bundle跳过和app升级后做独立策略迁移事务，保存原drop-in/receipt，policy-updating阶段，原子替换、daemon-reload、提交receipt；失败/中断恢复。保留首份原管理器文件/links备份及选择，无restart。旧rollback没有policy recovery函数时仍按其已有非installed阶段恢复规则恢复原文件，兼容模型回归通过；宿主root-only旧脚本未读/未执行。

## 验证

- ipc.test.py：真实QS + isolated mock greetd socket 15场景通过，包含auth_error→cancel generic ConnectionRefused→create→fresh synthetic response→start_session完整链；普通backend error与disconnect/frame-timeout留可见恢复画面至少2.2秒；显式重连退出75；原认证、取消、多prompt/重复名字/拒绝launch/错误用户场景保持。只保存request type，响应不进日志、无真实PAM。
- ui-supervisor.test.py：5项通过，固定argv、两次重连后0、正常0不重启、3次上限、TERM无响应UI2秒强杀；真实QS offscreen Qt.exit(70/75)透传。无宿主窗口/服务。
- install.test.py：44项fake systemd/logind文件事务通过，新增同bundle/upgrade旧策略迁移、reload失败、receipt提交失败、未提交/已提交中断恢复、管理员修改拒绝、旧rollback行为模型；首份备份与links保留，不调用start/stop/restart/enable改变活动服务。
- systemd-analyze verify：本机原生262解析临时no-op ExecStart units，检查infinity/Restart/OnFailure语法通过，无service job。它不是实际daemon重启/上限/OnFailure回退验收，fake事务测试也不能证明真实管理器流程已通过。运行语义依据本机systemd.service/unit官方man；人工stop与reset-failed边界见安装说明。
- 实际--build bundle含可执行Python supervisor/hash/helper、所有Python编译通过；QML语法/重复声明检查通过。

全部协议测试用临时socket、QT_QPA_PLATFORM=offscreen，删除DISPLAY/WAYLAND_DISPLAY，不触碰宿主greetd/socket。没有真实PAM认证、显示管理器切换或TTY恢复演练。

## 更新与恢复

用户运行原独立安装更新入口即可安装本批app并迁移已有策略，源码任务未代执行。仅daemon-reload，不重启当前桌面。app与策略是分开的恢复事务；策略迁移失败可能保留已升级app但旧策略/receipt已恢复，不能声称整个安装一并回旧app。

已卡死时在TTY3使用sudo systemctl restart greetd；start-limit-hit先sudo systemctl reset-failed greetd，再restart；正式rollback-installed入口恢复原管理器。本批不向当前会话执行这些操作。实机错误认证/取消/重连、daemon退出0与故障上限恢复仍需下次受控验收，不冒充已经验证。

独立预审发现P2文档历史正文仍称Restart=no/沿用旧配置，与本轮策略迁移矛盾；已统一更新原正文，澄清同bundle也检查策略以及app/策略是两个恢复事务。最终关闭结论由独立审查给出。
