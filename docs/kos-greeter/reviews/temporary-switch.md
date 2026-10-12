> 当前状态（2026-10-11）：用户已明确验收关闭 T01–T06。下文为历史执行快照，文中“T02/T05 保留阻断”已被用户验收取代；历史缺测仅用于追溯，不重新打开任务，也不补造测量数据。任务状态以 [tasks/README.md](../tasks/README.md) 为准。

# 临时测试/回滚脚本独立审查

日期/时区：2026-10-11，Asia/Shanghai。执行者：Codex。
独立只读审查代理：/root/review_switch_scripts，未参与编写或实现，未修改被审文件，未切换宿主服务。

被审范围与版本：../evidence/temporary-switch/SHA256SUMS 全部 12 项；分支 codex/notification-center-stacks，未提交文件摘要冻结。实现包括两脚本、会话 wrapper、13 项测试、说明、中英文 app README 及执行证据。独立复审确认全部摘要一致。

| 问题 | 修复与验证 | 关闭 |
| --- | --- | --- |
| P1 锁争用导致自动恢复过早耗尽 | 自动恢复有界等待锁并最多三次尝试；switch worker 180秒、guard1200秒；真实flock争用及有界重试测试通过 | 独立复审关闭 |
| P2 首次快照写失败/中断残留 | prepare 快照阶段 BaseException 清理，外层异常恢复；写入中失败清理自行创建inode；写失败/KeyboardInterrupt夹具通过 | 独立复审关闭 |
| P2 忽略计时器停止失败 | 严格停止及确认状态，失败保留快照供重试；timer故障夹具通过 | 独立复审关闭 |

独立复审运行 apps/greeter/tests/switch-scripts.test.py，13/13 通过。检查最终代码、说明和证据，未发现新增或未关闭 P0/P1/P2/P3。

结论：脚本编写与模拟检查交付通过，可以报告两脚本完成。本机只读 preflight 和 unit语法检查不证明实机安全切换；本次未运行 --start 或真实 rollback。实机切换、真实PAM、TTY/旧管理器完整恢复、进程树及录像均未测，T02/T05 保留阻断。完整回滚只恢复脚本改变的服务和文件，不恢复已退出窗口或未保存数据。
