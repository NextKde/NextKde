# 自动源码更新独立审查

2026-10-12 Asia/Shanghai；任务：用户要求检测已有安装并自动安装当前本地源码。
执行者：Codex主代理。独立只读审查代理：`/root/review_automatic_upgrade`，未参与编写/实现。
基线：54512887915152c514b9d08f3a45ca14779e1adc；分支codex/notification-center-stacks。
被审未提交范围：`../evidence/automatic-upgrade/SHA256SUMS`；最终清单SHA256：`1074739fe54da2915cf00a46d471c550e93a6b8105cfaa48656f8bbff2b89010`。

初审核对清单匹配，独立运行35项安装事务测试通过；覆盖脚本、升级事务、公开资源、恢复、文档和证据。无P0/P1/P2。审查认可原子交换与提交前恢复/提交后清理，保留首次备份/服务状态和会话基线；旧独立恢复入口可完整卸载app/state，不依赖源码路径。

P3：INSTALL.zh-CN.md验证边界仅引用旧persistent-install审查，缺少自动升级审查。执行者已补本次证据/审查链接。帮助文字“默认启用”明确限定初次安装，避免误解更新会改启用状态。均为文档修正，产品代码/测试无后续变更。

验证：35项install通过；handoff、wallpaper回归通过；sh语法、Python语法、独立bundle构建、git diff --check通过。仅临时root+模拟systemd/logind，未执行宿主安装/启用。

最终独立复审：`/root/review_automatic_upgrade`于2026-10-12只读复审通过，最终清单全部匹配，产品代码/测试与初审一致。P3链接问题已关闭，无未关闭P0–P3。代理明确允许仅保存本结论无需递归审查；完整T14/A19不因本次脚本交付关闭。审查元数据结论本身不纳入循环摘要。

限制：断电、运行中Greeter懒加载/逐帧连续性、跨发行版renameat2、真实PAM/TTY仍未测；T14/A19完整实机验收不关闭。app与state不同文件系统时拒绝原位升级；不更新既有服务配置/恢复代码合同，不拉取远程源码。
