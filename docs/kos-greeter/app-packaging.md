# Greeter 安装边界

Greeter 是 `apps/greeter/` 下的独立应用，专用入口为 `tools/install-greeter.sh`，回滚入口为 `tools/rollback-installed-greeter.sh`。普通 apps 合集安装不得顺带切换登录管理器。

具体命令、默认服务选择、仅安装文件、当前桌面激活及恢复说明，以 [安装文档](../../apps/greeter/INSTALL.zh-CN.md) 为准。已有安装的更新保留首次恢复快照及原服务启用状态，不重启当前桌面，不自动拉取远程源码。

安装、升级和回滚必须保留事务检查、依赖检查与失败恢复；模拟 systemd/logind 测试不替代真实 PAM、TTY 与登录验收。可选 compositor handoff 的安装只放置实验文件，不附带启用或服务切换。
