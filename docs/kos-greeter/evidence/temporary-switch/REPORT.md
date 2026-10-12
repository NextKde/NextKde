# 临时测试与完整回滚脚本交付

状态：实现与模拟检查通过；实际切换未测。
执行者：Codex。日期/时区：2026-10-11，Asia/Shanghai。
分支：codex/notification-center-stacks。基线：54512887915152c514b9d08f3a45ca14779e1adc；未提交文件摘要见 SHA256SUMS。

授权：用户明确要求编写“暂时的测试脚本，禁用默认的显示管理器，然后启用目前的”以及“完整回滚”脚本。本次仅编写、只读预检和模拟测试，没有运行 --start、实际 rollback、sudo、服务切换或系统文件写入。本授权不把 T02/T05 未测项改为通过。

交付：tools/test-greeter.py、tools/rollback-greeter.py，说明 apps/greeter/TEMPORARY-TEST.zh-CN.md。运行入口补充 --temporary-seat，加入 dbus-run-session 为独立 KWin 建立独立 D-Bus；不导入用户 bus。源文件安全副本按有限清单写入 root 管理的 /run 路径。仅临时停止/runtime mask 原管理器、临时启动专属 greetd unit，保持原管理器持久 enable/alias 与 greetd/PAM 配置不变。脚本需从与测试 VT 不同的文字 TTY 启动。

回滚：保存原管理器名称、enable 状态、测试 VT getty 活跃状态及测试前 logind 会话 ID；停测试 daemon/测试新增 greetd 会话，恢复原管理器/必要 getty；清理 runtime 文件、计时器、app副本、控制快照及锁。不恢复已结束的桌面窗口或未保存数据。无快照重复回滚无害；外部并发修改/恢复失败保留快照，不覆盖。

自动恢复计时器先于停止原管理器启动；切换工作交给独立 systemd transient service，最长运行 180 秒。恢复程序等待锁最多 240 秒，再最多三次恢复尝试，避免争锁过早放弃及无界重启。自动恢复服务上限 1200 秒；持续系统故障仍须 TTY 手动重试。重启自然清理 /run，原持久默认未修改。

## 实测证据

- preflight.txt：本机只读预检通过，原管理器 plasmalogin.service，VT1、默认600秒；此项不等同真实启动检查。
- tests.txt：13 个临时文件系统 + 模拟 systemd/logind 测试通过。覆盖切换/完整/重复恢复、计时器未启动拒绝、服务启动失败、部分 unit 写入失败、快照写入失败/中断、恢复失败保留快照、停止timer失败、外部runtime编辑拒绝、自动锁等待及有限重试、真实flock争用、restrictive umask、安全入口与独立 D-Bus wrapper。系统服务调用全部替换为 fake；文件所有权用合成值，不是root安装证明。
- unit-verify.txt：systemd-analyze verify 检查临时目录生成的 unit 语法，不启动unit。
- final-state.txt：宿主默认管理器仍 active/enabled；greetd inactive/disabled。

组件版本沿用 ../T05/environment.txt：greetd 0.10.3-2、Quickshell 0.3.2-1、KWin 6.7.5-3、Qt 6.12.0、systemd 262-1、Python 3.14.7。环境：当前桌面用户 + 临时目录，无真实 seat/VT、认证或模式切换。

## 恢复与未测边界

故障为夹具注入，恢复耗时未用于真实 SLA；夹具测试约0.3秒。真实 A01/A02/A14-P/G1、PAM、TTY旧管理器恢复、greeter权限、真实会话终止/无双KWin、录像均未测，T02/T05 保留阻断。没有实际密码、截图、PAM修改或原管理器配置备份恢复，因为本次没有修改这些配置。当前会话未退出，无需恢复宿主。

认证成功/退场/launch/KWin退出/桌面首帧的真实时间线、scanout、Cover、黑帧、视觉精度未测。不可声明零黑帧或部署验收完成。

## 独立审查

代理 /root/review_switch_scripts 未参与编写，只读审查。初审 P1 自动回滚锁争用过早放弃、P2 快照首次写入失败残留；补充计时器停止失败/中断处理。执行者修复并补故障测试，最终摘要交复审；记录见 ../../reviews/temporary-switch.md。
