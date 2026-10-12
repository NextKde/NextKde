# T01 补充：greetd 安装后复核

日期：2026-10-11，Asia/Shanghai。执行者：Codex 主代理。分支：codex/notification-center-stacks。

用户告知已安装后，本次仅进行只读复核。证据：[greetd-installed.txt](greetd-installed.txt)。

- 包版本锁定快照：greetd 0.10.3-2；/usr/bin/greetd 存在且由该包提供。
- greetd --version 不受支持，返回参数解析错误；版本依据为 pacman 包数据库，不声称获得运行时版本输出。
- greetd.service 为 inactive、disabled。
- 当前 display-manager.service 仍指向 plasmalogin.service，状态 active。

此前 REPORT.md 和审查记录中的“未安装”是安装前快照，予以保留；当前依赖缺口中的 greetd 包缺失已解除，以本补充为准。安装不表示真实 PAM/IPC、seat/VT、独立 KWin 生命周期或恢复已验证；T02 仍需隔离环境证据。没有启动/启用 greetd，没有切换显示管理器、修改 PAM 或配置；无需恢复操作，耗时不适用。

本次补充独立审查见 [记录](../../reviews/T01-installed.md)。原冻结摘要和关闭摘要保留不变；本次摘要见 SHA256SUMS.installed。
