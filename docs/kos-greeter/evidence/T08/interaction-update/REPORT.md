# T08 登录交互修订

2026-10-11，Asia/Shanghai；执行者 /root；分支 codex/notification-center-stacks。状态：独立审查通过（交互修订与隔离验证；完整T08仍受A15阻断）。由用户实机反馈授权：初始画面应直接输入密码回车登录，不显示“继续”“退出原型”等调试按钮。

## 最终行为

单账户加载后自动选择并开始 greetd 认证；多账户点击身份即开始认证。后端密码提示到达后自动聚焦密码框，回车提交，立即清除字段。没有启动认证按钮、取消按钮、刷新按钮或退出原型入口。普通单用户画面只有头像、名字和密码框；多用户及手工登录保留低强调度“切换用户”，Esc也可返回用户列表。Other user用登录名回车发起认证，再输入后端要求的响应；仍支持echoResponse、info/error、多轮提示，不预先缓存密码。

失败后清空响应，保留错误提示，等后端Inactive后自动重建认证，再聚焦输入，不自动提交密码。取消/launch拒绝同样等待后端Inactive；重新开始使用80ms轮询，最多60次，不允许无限等待。启动认证就被拒绝时不自动循环创建会话，显示“无法开始认证，请按回车重试”。未连接时只显示连接异常提示；连接恢复可启动已选身份。

UI：默认头像由圆点改为人物轮廓，72px圆形头像、17px名字、250×40px圆角居中密码框；用户区建议起点0.79屏高，保留小屏滚动边界。日期统一中文星期，时钟字重Medium。普通密码提示放入输入框，错误单独显示；不重复展示“输入登录名或继续认证”。保留原T08的清secret、禁输入、壁纸冻结、纯背景提交门控和launched立即退出。

临时脚本仍在每次新启动时复制当前源码；修复显式--wallpaper预览adapter与现有冻结声明的匹配，避免该可选预览路径因代码更新而拒绝。没有运行真实系统切换、修改PAM或部署持久服务。

## 验证

- `python3 apps/greeter/tests/ipc.test.py`：实际Quickshell + mock greetd。12场景，覆盖单用户自动开始/聚焦、手工登录名回车、密码accepted信号、错误后自动重建、启动拒绝诊断与重试、取消返回列表、多轮提示、旧帧门控/无帧超时、认证创建失败不循环。普通/减少动画分别执行。
- `KOS_GREETER_EVIDENCE=<本目录绝对路径> python3 apps/greeter/tests/visual.test.py`：独立虚拟KWin，6组空输入分镜和VFR抓图视频，加实际frameSwapped的12场景mock IPC。单用户分镜使用单账户；多用户分镜使用合成账户。没有捕获真实密码或用户窗口，抓图不是外部scanout证据。
- `python3 apps/greeter/tests/switch-scripts.test.py`：20项模拟切换/回滚/复制检查；不会切换宿主服务。
- `python3 apps/greeter/tests/virtual-display.test.py`：输出迁移、缩放和小屏viewport五组回归。

本目录保存本轮实际日志、分镜与视频。上级T08目录是初轮历史证据，原SHA256SUMS对应当时版本；本轮当前版本使用本目录SHA256SUMS，不把旧证据套用到新代码。完整A15同状态实机基准、真实PAM/跨KWin呈现仍未测，保留原任务阻断；用户照片只用于界面问题反馈，不作为完整A15校准。

独立审查记录：../../../reviews/T08-interaction.md。

最终执行结果：offscreen普通/减少动画各12场景，虚拟KWin实际frameSwapped的12场景及6组分镜通过；模拟切换20项通过；显示迁移5组通过。相应*-regression.txt、ipc-*.txt、visual-tests.txt保存可读结果。
