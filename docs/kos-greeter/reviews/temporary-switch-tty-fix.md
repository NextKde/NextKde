> 当前状态（2026-10-11）：用户已明确验收关闭 T01–T06。下文为历史执行快照，文中“T02/T05 及真实 PAM、服务切换、会话终止、完整恢复验收仍阻断”已被用户验收取代；历史缺测仅用于追溯，不重新打开任务，也不补造测量数据。任务状态以 [tasks/README.md](../tasks/README.md) 为准。

# sudo TTY 兼容修复独立复审

日期/时区：2026-10-11，Asia/Shanghai。执行者：Codex。
独立审查代理：/root/review_switch_scripts，未参与编写/实现，只读且未修改产物或切换系统服务。
被审版本：../evidence/temporary-switch/tty-fix/SHA256SUMS，全部8项摘要一致。

问题：旧脚本的TTY检测没有兼容 sudo use_pty，照片中已登录tty3仍被拒绝。
修复：在锁、preflight、prepare之前检查交互输入；仅stdin为pts且有sudo数字UID标记时使用SUDO_TTY原始终端，保留同VT、图形环境、无sudo元数据pts、图形来源pts和管道拒绝。

独立执行14项模拟测试全部通过。说明与报告正确区分照片一致的根因推断和未执行的真实sudo/切换复测；旧版本摘要边界明确。
结论：未发现P0/P1/P2/P3，该TTY兼容修复交付通过。T02/T05及真实PAM、服务切换、会话终止、完整恢复验收仍阻断。本次未执行真实切换。
