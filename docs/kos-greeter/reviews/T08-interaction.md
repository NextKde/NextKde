# T08 交互修订独立审查

日期：2026-10-11（Asia/Shanghai）。执行者：/root；独立只读审查代理：/root/t08_review。审查者未参与本轮实现或编辑。分支codex/notification-center-stacks；未提交文件以 ../evidence/T08/interaction-update/SHA256SUMS 冻结。

范围：apps/greeter/shell.qml、tests/ipc.test.py、tests/visual-session、README.md、tools/test-greeter.py、T08任务卡和interaction-update证据。原审查清单摘要5648c817156063229985fb46179d33df500c34777c99bf12535bbb66bb5105ce，全部条目核验成功。

审查结论：通过，未发现P0/P1/P2；独立运行12场景IPC全部通过。单账户自动create、选择账户自动create、响应聚焦和accepted回车提交、错误清secret后等待Inactive重建、创建拒绝不循环、取消/launch拒绝恢复均符合要求。密码框可直接输入，普通界面移除了调试按钮。显式壁纸adapter匹配当前声明，没有扩大系统操作。单用户空输入分镜确认只显示头像、名字和密码框。

最终实测：普通/减少动画offscreen各12、虚拟KWin实际帧IPC12、6组空输入分镜、切换模拟20、输出迁移5通过。此证据不表示真实PAM或scanout。

最终审查批准仅更新报告独立审查状态、保存本结论、刷新清单；不修改实现。未测限制：完整A15仍缺同版本/配置/状态实机基准，完整T08继续阻断。没有在本轮运行系统服务切换。
