# 登录恢复修复：独立审查

任务：login-recovery-fix。日期：2026-10-12。实施者：`/root/implement_login_handoff`。独立审查者：`/root/review_login_recovery`，未参与实现且全程只读。主代理保存本记录。

最终范围为 [10 文件摘要](../evidence/login-recovery-fix/SHA256SUMS)，清单 SHA256：`ef94f447da1a80643aa901a026165b34a660368ed0b7cbeaf086e748b31237cc`。复审全部匹配；本增量取代历史范围中对应变化文件的摘要。实施和边界见 [报告](../evidence/login-recovery-fix/REPORT.md)。

独立复跑 44 项安装事务、5 项 UI supervisor、15 个真实 Quickshell 配合隔离 mock IPC 场景全部通过。覆盖 auth_error → 自动 cancel 普通错误 → 重新认证 → start_session；真实 Qt 退出码 70/75、有限重启及信号回收。没有使用真实凭据或 PAM，未操作当前桌面及登录服务。

发现 P2：安装说明旧正文仍承诺 Restart=no、沿用旧服务配置，与新恢复策略迁移冲突。实施者统一正文，刷新最终清单；独立审查者复核后关闭。代码及相关测试保持冻结。

最终结论：Passed，未发现未关闭的 P0/P1/P2。结论覆盖源码、隔离验证及文档。真实 PAM、daemon 启动上限与 OnFailure 回原显示管理器尚未实机验收；旧回滚兼容仅为隔离行为模型，未执行宿主 root-only 旧脚本。未部署，不据此声称实际登录故障或黑屏已全部消除。
