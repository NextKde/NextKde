# 登录交接修复：独立审查

日期：2026-10-12。分支：codex/notification-center-stacks。
实施代理：`/root/implement_login_handoff`。独立审查代理：`/root/audit_login_handoff_fix`，未参与实现，始终只读。主代理保存此审查记录。

## 被审范围

最终 16 文件及 SHA256 见 [冻结清单](../evidence/login-handoff-fix/SHA256SUMS)，全部经独立审查核对匹配。实现及隔离图形证据见 [报告](../evidence/login-handoff-fix/REPORT.md)。原有未提交用户变更保留，不将整个工作树差异视作本批新实现。

## 独立验证与结论

审查代理独立复跑 cover-readiness.test.py、shell-sync.test.py、entry-protocol.test.cjs，以及 install.test.py 的 36 项 fake systemd/logind 测试，均通过。复跑仅使用临时目录、模拟服务和测试 socket，未连接宿主图形；实施者的虚拟 KWin/真实 wrapper 双输出及 T11 七项隔离图形证据另经审阅。

确认可信服务/会话树中的 wrapper 识别与有界 wl_display.sync；确认 provider、配置、映射、几何变化清空 bar/Dock 帧登记；确认无 Cover 时 progress 为 1，独立恢复期限保留；确认初装、升级、同包跳过之前先校验 Shell 能力；确认显式用户 QML 同步保留其它 app/原生组件及根入口，提供备份和失败回滚。

未发现 P0/P1/P2。两项 P3 已由实施者修复，更新冻结摘要后独立复审关闭：

- desktop-ready.md 的 280ms 过期描述改为两端实际 620ms，reduced motion 为 1ms。
- INSTALL.zh-CN.md 明确历史无门控安装的超时行为与新版初装/升级预检拒绝的区别。

结论：本批源码修复和隔离验证交付通过独立审查。

## 边界

本批未部署、未操作 PAM/显示管理器、未重启用户桌面或执行真实认证。真实 provider 完整链路、物理登录、冷热录像、跨 KWin 黑帧、VT/DRM/presentation 未验证。wl_display.sync 和 frameSwapped 不等于 scanout，不宣称零黑帧，不据此关闭 T08、T11–T14 的实机主项。

旧测试夹具一次误连宿主 Cover 的情况、清理方法及修复后测试隔离边界，保留在实施报告中；原失败日志后来被覆盖，仅工具记录可追溯，不宣称已保存该日志。
