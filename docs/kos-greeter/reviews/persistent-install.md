# 持久安装与回滚脚本：独立审查

日期：2026-10-12。执行者：主代理。独立只读代理：`/root/review_persistent_install`，未参与实现，未修改文件。冻结范围14文件及SHA256见 `../evidence/persistent-install/SHA256SUMS`，操作说明见 `../../../apps/greeter/INSTALL.zh-CN.md`。

初审未通过：P1目录权限受umask077影响，P2快照准备失败残留、failed daemon会话遗漏、公开壁纸24小时TTL缺刷新。执行者修复为显式运行目录权限和greeter身份读取检查、完整私有快照先rename后系统变更、独立会话清理及bootID隔离、当前同意的壁纸刷新/撤销入口。二轮P3快照rename后的父目录fsync已修复。

最终独立复审通过：无剩余P0/P1/P2；冻结14文件摘要全部匹配；代理独立重跑22项文件系统事务/模拟systemd-logind故障测试全部通过。文档与实现一致：默认禁用原开机管理器、下一次启动使用greetd；立即切换需文字TTY。原配置/开机别名和链接/getty状态恢复，备份保留重试，独立恢复副本不依赖源码。保留壁纸24小时有效期并明确无自动刷新。没有顺带安装无关app、改PAM或执行部署。

限制：本轮没有真实root安装、systemd/PAM、物理TTY、开机登录或断电恢复验收。恢复guard仅处理greetd daemon服务失败，不检测daemon活着但图形UI失效；模拟测试不能宣称T14/A19完成。既有T11的完整三阶段录像缺口未被本轮修改关闭。
