# 登录 VT 输出修复：独立复审

日期：2026-10-12。实施者：`/root/implement_login_handoff`。独立审查者：`/root/audit_login_handoff_fix`，未参与实现，始终只读。主代理保存本记录。

## 范围与证据

最终 10 文件 SHA256 全部核对匹配，见 [冻结清单](../evidence/session-output-fix/SHA256SUMS)。事实、修改和隔离证据见 [实施报告](../evidence/session-output-fix/REPORT.md)。本增量摘要替代上一批重叠文件的摘要；bar/Dock 未改。

独立复跑最终 session-output.test.py 12 项、handoff.test.py 37 拒绝场景和生命周期/信号恢复、install.test.py 36 项 fake systemd/logind 事务，以及 Cover socket readiness 回归，全部通过。验证未触碰实际 TTY、PAM、显示管理器或用户图形会话。

## 问题与关闭

- P2：初版 journal 连接后断线使 prepare/phase 的 print 抛 BrokenPipeError，可能中断登录。审查代理用无 reader pipe 的独立子进程复现。实施者增加安全 diagnostic，覆盖两入口及 Cover 自有事件；null/dup2 失败采用静默末级恢复，复审关闭。
- 相关 SIGPIPE：Plasma、Cover 及其 qs 子进程保留 Python 的 SIGPIPE 忽略，TERM/INT/HUP 保持原契约。文档明确第三方自行改变信号或将 EPIPE 视作致命错误的边界。
- P3：VT 清理 finally 的 close 异常可能中断入口。改用 close_quietly，增加 mock close 错误回归，复审关闭。

确认 fd0 和控制终端保留，生产输出在诊断前重定向；--check 保持输出。VT 清理仅针对继承 tty1–tty63，核对设备、KDGETMODE 与重开后 inode/device；不切换 VT、不设置显示模式。helper 已进入共同打包和正式 bundle 必需清单。无新增凭据/原始认证协议日志或全局环境导入。

结论：无未关闭 P0/P1/P2/P3，本批源码与隔离验证交付通过独立复审。

## 未测边界

未部署，未验证实机 VT 清理、真实登录、冷热启动录像或跨 KWin 黑帧。清旧文本不会保持图形帧；直接打开 TTY 的其它进程、内核及认证管理器自有输出不由 stdout/stderr 重定向覆盖。native journal 初始化和 stream 保留标准阻塞语义，无硬启动时限保证。本结论不代表实机文字已完全消失或零黑帧，不关闭此前缺实机证据的任务主项。
