# T08 登录视觉与退场

执行者：Codex 主代理；日期：2026-10-11（Asia/Shanghai）。分支 codex/notification-center-stacks；HEAD 54512887915152c514b9d08f3a45ca14779e1adc。实现为未提交文件，最终冻结范围见 SHA256SUMS。

已完整读取用户指定两份 README、AGENTS/agent、任务卡、约束、research、acceptance、安装方案和 T04 报告。T05/T07 使用既有实现；未更改既有未提交的 Dock、桌面壁纸、发布工具或系统配置。

## 实现与参数

独立 Greeter 仍通过 greetd 认证。上部日期/时钟、下部单用户身份或纵排账户列表、Other user、等待/失败提示均由状态根管理。单账户读取后自动选择，多个账户保留列表。头像缺失保持默认。已知账户不重复显示登录名输入。玻璃面板使用半透明圆角/边框，时钟使用浅色字与轻阴影，完全不依赖 shader；软件渲染也保留认证功能。不分发 Apple 字体。

| 字段 | 值 | 依据 |
| --- | --- | --- |
| 日期中心 | (0.5, 0.108) 屏幕逻辑坐标 | T04 A/B 可见轮廓研究；非字体 bbox 校准 |
| 时钟中心 | (0.5, 0.187) | T04 A/B 研究构图 |
| 时钟字号 | 屏高×0.145，40–160逻辑像素 | KOS 建议，使用本机 Qt 默认字体 |
| 用户区起点 | 0.76屏高，底部16px约束与滚动回退 | KOS 交互建议，非 Tahoe 实測 |
| 选中头像 | 56逻辑像素 | 建议 |
| 列表头像 | 36逻辑像素；头像右侧名字 | 建议，T04 B结构参考 |
| 表单宽度 | ≤340逻辑像素，左右≥16px | 建议 |
| 材质 | 面板白色 alpha 0x24，边框0x45/0x60；背景暗罩0.16 | 建议，无折射实测 |
| 退场 | 默认220ms，KOS_GREETER_EXIT_MS限制180–280ms；InOutQuad | 建议；真实事件差见日志，不把设定当实测 |
| 减少动画 | KOS_GREETER_REDUCED_MOTION=1，1ms目标 | 建议；保留清理、禁输入和帧门控 |
| 帧/launch期限 | 5s / 10s | 超时退出，由登录宿主恢复 |

ReadyToLaunch 清输入并禁用视觉树，ExitStarted 同时淡出整个 UI 与暗罩，不移动壁纸。动画完成记录 ExitComplete，下一事件循环 arm 后，首个 frameSwapped 仅 drain 在途帧并显式请求下一帧，第二次提交检查 UI/暗罩 opacity=0 和后端 ReadyToLaunch，再记录 FrameSubmitted/LaunchRequested 并 launch。测试注入首个旧 swap，确认仍在 Exiting。frameSwapped 只表示帧提交，绝不表示 scanout。launched 立即退出，不等待桌面信号。

认证失败不退场；启动拒绝清输入、取消后端会话，Inactive 后显示重试提示；断连显示诊断1.8s后退出，由现有宿主重建。无帧提交时超时退出，不绕过帧门控。退场冻结当前可信壁纸快照，停止轮询并拒绝在途读取结果；提交门控等待当前背景解码/安全回退完成。壁纸资源/crop/scale不由动画更改，未实现桌面Cover或top切换控制（T10/T11）。

## 验证与证据

环境：Quickshell 0.3.2、KWin 6.7.5、ffmpeg n9.0.2；隔离 dbus-run-session + KWin --virtual，单输出1280×900。渲染夹具使用内置默认背景和合成账户，输入始终为空；没有真实 PAM、密码、桌面窗口或系统服务切换。运行命令：

```
node apps/greeter/tests/lifecycle.test.cjs
python3 apps/greeter/tests/accounts.test.py
python3 apps/greeter/tests/ipc.test.py
python3 apps/greeter/tests/wallpaper-freeze.test.py
KOS_GREETER_REDUCED_MOTION=1 python3 apps/greeter/tests/ipc.test.py
python3 apps/greeter/tests/wallpaper-freeze.test.py
python3 apps/greeter/tests/visual.test.py
```

- IPC 测试覆盖成功、失败后重试、取消、断连、launch拒绝、多轮提示、UID身份、取消恢复以及无帧超时。虚拟输出使用实际 frameSwapped；offscreen 明确注入提交事件，不能作为实际提交证据。ipc-*.log 仅保存状态/视觉事件，不保存请求内容。
- multi/single/waiting/failure/exit/reduced.png 为实际 Qt 合成账户分镜；对应 mp4 为连续 grabToImage 渲染采样，不是外部屏幕录像。视频按回调时间戳以 VFR 编码，捕获会增加渲染负载，不能用于预测生产延迟或物理呈现。各 log 的 CAPTURE 为采样回调时刻，VISUAL 为生命周期事件；Date.now 是同进程墙钟，不是跨进程 monotonic 测量。
- exit/reduced/frame-070.png 像素断言为纯背景 #16283b，没有表单、时钟或暗罩；测试同时检查 ExitComplete → FixtureFrameSubmitted。真实 IPC 另核查 ExitStarted → ExitComplete → FrameSubmitted → LaunchRequested 顺序，避免视觉夹具替代 launch 测试。

| 验收 | 本次边界 |
| --- | --- |
| A08 | 隔离 Qt/模拟 greetd 验证；真实 PAM 与跨会话录像未测 |
| A15 | 概念构图与回退实现；完整同版本/配置/状态基准仍缺失，未通过1:1 |
| A13 | 合成账户、空输入视觉采样；IPC不输出response |
| A16 | 未测，未声明零黑帧 |
| A17 | 独立审查记录见 ../../reviews/T08.md |

最终检查结果：模型与账户测试通过；offscreen普通/减少动画各10场景、虚拟KWin实际帧IPC10场景、6组空输入分镜均通过。wallpaper-freeze.test.py 用实际QML与有延迟的helper验证冻结时停止在途资源替换、解冻后加载新版本，两项通过。T06输出迁移/小屏viewport与T07启动解码/超时回退回归均通过。可读摘要见 *-regression.txt、ipc-offscreen.txt、ipc-reduced.txt、visual-tests.txt。

实测事件差见 timings.json；普通mock IPC正常退场目标220ms，实测事件差以该JSON为准。抓图负载下的exit可能更长，记录其真实值，不写成180–280ms通过。全仓tools/check-docs.py检查遇到既有.build第三方Markdown缺链接；本任务文档相对链接单独检查。

## 恢复与未测

可重复恢复：错误认证留在登录重试；取消等待Inactive；启动拒绝发cancel_session后回Idle；连接异常诊断后退出；无帧超时不发start_session。隔离 compositor 使用 --exit-with-session，测试父进程超时杀独立进程组，不影响宿主登录服务。未测试完整 Tahoe 像素阈值、真实 scanout、240Hz、真实跨KWin切换。T04 GAPS.md 仍需同配置实机素材；现有静态宣传图不能替代。这些缺口不补造，也不重新打开已验收T01–T07。

任务卡保留完整 A15 的验收缺口；完成实现与隔离证据不等于完整 T08 已关闭。
