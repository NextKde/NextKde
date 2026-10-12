# T03 发布侧验收

状态：完成（隔离发布侧）。执行者：Codex 主代理。日期：2026-10-11，Asia/Shanghai。
分支：codex/notification-center-stacks；HEAD：54512887915152c514b9d08f3a45ca14779e1adc。新文件以 SHA256SUMS 冻结。T01 完成，版本补充见 T01/UPDATE-installed.md；T02 隔离登录阻断不作为 T03 依赖。

环境：本机普通 UID 1000 的 TemporaryDirectory 隔离夹具；无新增 seat/VT/窗口。Python/Pillow 版本见 environment.txt；greetd/Quickshell/KWin/Qt/GPU 基线见 T01，当前版本快照见 environment.txt。本卡不启动这些组件。

运行：`python3 apps/greeter/tests/resources.test.py`。12 个测试通过，详见 tests.txt。每个用例临时目录结束后自动清理，所有故障可通过同一命令重复。

| 验收 | 实测 | 证据 |
| --- | --- | --- |
| A03-P | 副本独立于源、处理后 hash/尺寸、UID、权限、版本、fit/crop 契约及消费夹具通过 | test_copy_and_permissions，publication.md |
| A11 发布范围 | 缺图、损坏、过期、schema 升级、未知字段、任意路径/符号链接拒绝；返回默认分支 None | test_bad_manifest_and_corruption、test_symlinks_and_writable_store |
| A13 发布范围 | manifest 无源路径，有限字段；无密码/token输入，元数据重新编码，未读取用户私人图 | tests/resources.test.py、resources.py 人工检查 |
| A18 发布侧 | 拒绝未同步；切图清理旧版；撤销/账户删除复用 revoke，reload 返回 None；中断后 recover 清理 | test_consent、test_interrupted_publish_and_gc、test_revoke_delete_and_cleanup_recovery、test_committed_cleanup_interruption |

缺图/损坏/过期/schema错误恢复为 None，调用方使用 shell.qml 现有内置渐变及后续默认头像。删除源文件夹具代表副本与源目录可读性脱钩；真实加密 home、外盘拔除未操作。拒绝格式、超预算与提交前发布中断不覆盖前版；提交后清理中断保留新 manifest，recover 清理旧版。恢复调用 recover，同步执行无重试循环；整组测试耗时见 tests.txt，不声称真实登录恢复时延。清理中断后 manifest 已撤回，复原清理无旧版本残留。没有系统服务/PAM/home 权限修改，当前管理器状态见 final-state.txt。

完整 A03 三阶段图、实际 Greeter/Cover 缓存失效、系统 root 服务部署/鉴权、真实不可读 home、所有认证/退场/launch/scanout 时间线、视频/黑帧/Tahoe：未测，归后续任务。本卡通过仅指 A03-P、A18 发布侧及 A11/A13 本范围。生产资源目录 root 所有权和跨 UID 消费由集成验收；当前不部署。

独立审查及修复记录见 ../../reviews/T03.md；审查者未参与实现。摘要排除报告状态和审查记录，避免结论自引用；关闭状态变化交由同一审查者确认。
