> 当前状态（2026-10-11）：用户已明确验收关闭本任务。下文为历史执行快照，原阻断/不关闭结论已被用户验收取代；历史缺测不重新打开任务，不补造测量数据。

# T05 身份与认证界面执行记录

状态：阻断（实现及离线检查已完成；真实验收未测）。执行者：Codex。
日期/时区：2026-10-11，Asia/Shanghai。分支：codex/notification-center-stacks。
提交基线：54512887915152c514b9d08f3a45ca14779e1adc；未提交产物见 SHA256SUMS。

用户明确授权 T05 实现，并在发现 T02 未通过后明确允许“先实现 T05，保留验收阻断”。T03 隔离发布侧已完成；T02 的真实 PAM/seat/VT/进程退出/恢复与 G1 仍阻断。本次没有修改 PAM、系统登录配置、服务、home 权限或创建真实账户。

## 接口与状态机

实现位于 apps/greeter/。companion/accounts.py 通过固定 argv 的 busctl --system 只读 ListCachedUsers，并逐账户读取 Uid/UserName/RealName/IconFile；不读取密码提示、历史等额外字段，不写账户。UID 去重、校验并作为 selectedUid 配置关联键；UserName 是认证身份，RealName 空白时回退 UserName。列表最多 32 项，有时间预算和前端 10 秒终止；失败/部分列表保留其他用户。刷新是显式操作，不改当前选择；账户删除后须重新刷新，认证仍以 greetd/PAM 最终结果为准。没有从桌面用户配置导入身份或授权。

头像仅接受 /var/lib/AccountsService/icons 下 root 所有、不可由组/其他用户写入的常规文件；所有父目录检查、禁止链接、文件读取限 1 MiB、PNG/JPEG 单帧解码限 1048576 像素，缩至 96×96 并重新编码为无元数据 PNG data URL。拒绝 home IconFile、不存在/不可读/损坏/超预算/不可信路径时用默认头像，不加载用户 QML。Pillow 缺失时同样回退；进程超时保留其他用户入口。此策略不消费 T03 的头像副本，发布副本接入留待消费端集成。

列表滚动、Tab/Shift+Tab 和按钮 Enter/Space 使用 Qt Quick Controls；字段和账户按钮具有可访问名称。已选择账户禁止编辑登录名，其他用户允许手工输入。返回列表先清响应，活动认证先 cancelSession 并等待 Inactive；返回列表清登录名和 UID，普通取消保留身份并恢复可操作按钮/字段焦点。

信息及可恢复错误提示仅显示，不从 error 推断结束；仅 responseRequired 显示输入并提交响应，echoResponse 控制明文/密码及敏感输入法标志。Quickshell 对 info/error 的协议确认空响应由其接口内部处理，不是 UI 提交凭据。authFailure 清响应、回 Idle，下一次继续创建新会话；不自动无界重试。提交/新提示/取消/失败/退场/终止即时清字段；日志只有有限状态，不包含用户名、PAM提示或响应。Qt/JS 不承诺底层内存零化。认证 60 秒、launch 10 秒超时退出前端；真实 greetd 恢复仍依赖 T02 验收。

## 检查与证据

环境：当前桌面用户，Qt offscreen + 模拟 Unix greetd IPC；不是隔离 seat 或真实 PAM。组件见 environment.txt，显示器/VT/输出模式不适用。无截图/录像、真实密码、用户窗口捕获或跨会话帧测量。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| 身份归一化 | 两账户、同名、UID 去重、空 RealName、无效 UID、服务失败通过 | accounts-tests.txt、apps/greeter/tests/accounts.test.py |
| 头像 | home 不打开、缺图、权限拒绝、不可信父目录/链接、坏图、超像素预算、正常重新编码通过；部分权限/所有权以 mock 注入 | accounts-tests.txt |
| 系统 AccountsService | 实际只读快照 1 项，字段结构正确；只记录计数，不保存账户字段 | environment.txt |
| QML/mock IPC | 成功、失败后重建、取消返回列表、选中账户取消恢复键盘焦点、断连、launch 拒绝、多轮 secret/info/error/visible、两个同名账户认证通过 | ipc-tests.txt |
| 生命周期模型 | 退场/launch 顺序、取消屏障、失败与超时通过 | lifecycle-tests.txt |
| 隐私有限检查 | 虚构响应未出现在测试捕获日志；无实际密码 | ipc-tests.txt、测试断言 |

A02/A06/A07/A13 完整验收均阻断/未测：真实两账户和 Other user、不存在账户、home 不可读、PAM 多轮、真实失败取消重试录像、屏幕阅读器及人工隐私审查尚未执行。离线夹具通过不替代这些证据，不关闭 T05。

## 故障恢复与最终状态

模拟认证失败后再继续，创建新会话；取消等待后端 Inactive 并允许选择账户；断连测试把 watchdog 缩至 500ms，受控退出，无 start_session；launch 拒绝同样退出。失败注入仅独立 offscreen 进程和临时 IPC，测试结束临时目录删除，未触及宿主管理器。实际恢复耗时、TTY/原管理器恢复、真实进程树与录像未测。宿主服务状态见 environment.txt。

认证成功/退场/launch 等真实时间线、scanout、Cover/揭幕、黑帧、Tahoe 精度均未测或不属本卡。无零黑帧/1:1 声明。

## 独立审查

只读独立代理 /root/review_t05 未参与编写。初审两项 P2：取消后的可操作键盘焦点；允许路径头像解码故障覆盖。执行者修复并补测试，最终版本 SHA256SUMS 已交复审。审查记录见 ../../reviews/T05.md；审查不能解除真实验收阻断。
