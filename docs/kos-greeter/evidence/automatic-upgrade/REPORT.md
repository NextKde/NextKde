# 自动源码更新脚本交付

2026-10-12 Asia/Shanghai；分支codex/notification-center-stacks，基线54512887915152c514b9d08f3a45ca14779e1adc，未提交摘要见SHA256SUMS。执行者：Codex主代理。状态：脚本实现/隔离验证及独立审查交付；完整实机验收仍未测。用户明确要求检测已安装后自动处理安装当前最新源码；本轮只更新脚本，不执行宿主安装、服务切换或PAM变更。

## 行为

专属脚本每次从当前本地checkout构建，不自动git pull、不编译整个Shell。已有合法安装快照时，相同bundle跳过，不同bundle原位更新完整app；升级保留首次原管理器备份、boot/session清理基线、受管配置及服务启用状态，不调用systemctl stop/start/restart/enable/disable。先files-only安装后默认更新也不启用。

Linux renameat2原子目录交换；新/旧app在state/upgrade-app及正式app路径间交换，安装路径不存在的间隙被消除。state/upgrade.json记录新旧inode及唯一事务ID；状态提交前失败/下次重试恢复旧app，提交后中断只清理旧备份。保留现有恢复入口和配置合同，不因升级覆盖原管理器备份；旧版独立恢复代码仍可执行完整卸载，删除app及包含升级暂存的state。

要求app与state在同一文件系统；跨文件系统在修改前拒绝。新版读取检查失败、发布失败或状态提交前故障恢复旧版。配置/别名外部修改、临时测试活动、未完成回滚拒绝覆盖。`--activate-now`不用于已有安装；持久启用的安装不能以`--files-only`直接改变启动选择。

公开数据先保留所有账户副本，当前调用者按新bundle同意刷新/撤销（--no-wallpaper-sync也撤回），其他账户不删除；发布失败恢复旧版公共数据。原位更新不升级系统依赖/PAM/Shell，不更新既有服务配置或独立恢复代码合同。初次安装仍按原明确要求默认选择下次开机greetd。

## 验证与恢复

`python3 apps/greeter/tests/install.test.py`：35项通过，日志install.log。包括旧有23项（原升级拒绝项替换）和新增自动升级：真实临时文件树原子exchange、保留原备份/服务状态、删除废弃文件、同包幂等、copy/readability/publish/commit失败恢复、事务exchange前/后与commit后中断恢复、files-only保持、外部配置/未完成rollback拒绝、其他账户保留、真实Store只撤调用者、跨文件系统拒绝。systemd/logind/greeter可读性检查用mock，没有宿主root/greeter操作。

handoff.log/wallpaper.log原契约回归通过；sh -n、Python语法检查及git diff --check通过。临时root由TemporaryDirectory删除；没有宿主恢复步骤，实际原管理器恢复/升级耗时未测。后续T14完整实机验收仍阻断，不把脚本回归等同A19实机通过。断电、实际活跃登录UI懒加载/跨会话资源变更、跨发行版renameat2及真实PAM/TTY未测，不承诺运行中Greeter逐帧连续。

旧T14/持久安装报告是历史冻结版本；“必须先回滚升级”是当时行为，本轮明确更新它，不改写历史证据或旧摘要。当前操作以apps/greeter/INSTALL.zh-CN.md为准。

## 独立审查

最终范围：tools/greeter-install.py、tools/install-greeter.sh、apps/greeter/tests/install.test.py、apps/greeter/INSTALL.zh-CN.md、app-packaging追加记录、本目录证据。执行者未充当独立审查者。记录见../../reviews/automatic-upgrade.md；初审无P0/P1/P2；P3验证边界缺少本次审查链接，已补自动更新证据/审查链接并送最终复审。
