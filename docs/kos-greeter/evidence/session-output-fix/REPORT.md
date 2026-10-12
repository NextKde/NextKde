# 登录 VT 输出修复

日期：2026-10-12。状态：实现/隔离验证已交付，待独立审查。未部署、未重启实际会话、未触碰实际 TTY。本批最终文件见 SHA256SUMS。

## 事实与范围

用户真实体验是密码加载后黑屏、几行终端代码、再次黑屏、壁纸 spinner，随后上滑揭幕。主代理复核安装版本已匹配上一批源码；本次真实日志显示 ResourceReady 27.678s、ResourceMatched 28.243s、Frame 28.388s、Reveal 28.407s、Complete 29.117s，证明后段交接运行，不能用它推导前段无黑帧。

只读 fd 证据由主代理取得：kos-user-session PID1498 与 startplasma-wayland PID1522 的 fd0/1/2 全部是 /dev/tty1；systemd 托管的 kwin_wayland_wrapper PID1540 stdin=/dev/null、stdout/stderr=journal socket。源码确认 Greeter 运行 check() 会先打印，再 exec dbus-run-session/direct KWin/UI；用户 wrapper、Plasma、Cover Popen 继承终端输出。系统托管用户 KWin 日志不应被误归为本次泄出源。

## 实现

session_output.py 使用已安装 libsystemd 的 sd_journal_stream_fd(identifier, priority, level_prefix=0)，dup2 仅 stdout/stderr，stdin/控制终端/PID、固定命令、会话退出及信号契约保持。两个生产入口在第一条运行诊断之前设置；--check 模式仍打印安装检查结果。子进程直接继承 stream，无新增 logger 子进程。失败关闭已开 stream，并使用 /dev/null，尝试固定 syslog 故障码，不回退写终端、不输出异常详情/环境。入口/Cover 自有固定诊断统一使用安全写，已建立 stream 后断线时同样降级，不因 BrokenPipeError 中断启动。null open/dup2 失败的末级降级关闭 fd1/2 并用 Python SilentOutput；清理 close 的 OSError 被安全捕获。没有新增认证日志或 greetd debug。

初始化/stream 写是系统标准阻塞语义，不承诺硬期限；journald 不可用会减少诊断；本批保证入口自有诊断错误不阻断固定启动。生产 Plasma/Cover/qs Popen 保留 Python 的 SIGPIPE 忽略，Greeter exec 保留原忽略状态，不改变 TERM/INT/HUP。子进程自行重设信号或将日志写入错误作为致命条件的行为不在入口可保证范围；已启动子进程不能事后由父进程替换 stream，断线后可能持续丢日志。继承 fd 与常规系统服务 journal stream 行为相同。

Linux VT 清理只针对 fd0 的 /dev/ttyN、major4/minorN，范围1–63；KDGETMODE确认LinuxVT，重新打开同一pathname带NOFOLLOW/NOCTTY并核对dev/ino/rdev，写固定清屏/滚屏缓存序列。失败不阻断登录。未切VT/模式，不打开其它TTY、不读取终端输入、拒绝PTY。清旧缓存不代表消除内核/greetd/PAM/其它程序未来写入。

新增 journal identifiers 为 kos-greeter-session/kos-user-session；单调时钟固定事件 GreeterCompositorStarting、PlasmaStarting、CoverSupervisorStarting，加上 Cover SocketConnected/FrameSubmitted 可定位下一次实际登录空档。未修改 Cover 资源 feed/image settled 规则、没有 KWin/DRM 底层补丁。

helper 已纳入临时/正式共同打包清单及正式 bundle 必须文件；安装回归 fixture 对应更新。

## 验证

- session-output.test.py 12 项通过：PTY/其它路径拒绝；LinuxVT仅同一设备清理；设备替换/ioctl失败不写；独立子进程stdout/stderr传入stream且fd0不变；journal初始化失败无终端输出；生产检查在exec之前已重定向；两入口--check保持可见；初始化即断线/ready后断线/null open与dup2失败安全继续；实际/bin/sh 保留 SIGPIPE 忽略；VT close 异常不阻断。所有VT验证采用mock，未打开实际VT。
- 独立 subprocess 实际连接 journald，三个固定测试marker（parent stdout/stderr、child stdout）可通过唯一identifier查询，原capture pipes完全空；fd0是pipe，未清终端。journal-stream-test.txt。
- handoff.test.py：37拒绝场景及文件/lock/进程失败/信号回收通过。handoff-tests.txt。
- install.test.py：36 fake-systemd/logind 事务通过。install-tests.txt。
- --build --no-wallpaper-sync 构建实际bundle，helper与manifest hash相符，两入口导入存在；临时bundle检查后移除，无安装。bundle-test.txt。

本轮 BarWindow/DockWindow 未修改，主代理已核对其 SHA256 与上一批冻结一致；前段 VT 修复不更改桌面就绪逻辑。

## 未测与恢复

未做真实登录/真实VT清理/冷热启动录像，不宣称可见代码完全消除或零黑帧。某进程主动打开/dev/tty而非stdout/stderr、内核或认证管理器自有输出不在本批重定向覆盖范围；应按新journal时序及外部录像继续定位。

正常 app 升级/回退沿用现有原子安装与恢复脚本；helper存在于同一app bundle。不改Shell、系统服务/PAM/显示模式。入口诊断失败安全降级，不永久罩住桌面。

## 独立审查修复

审查发现 P2：journal 连接成功但对端断开时原始 prepare/phase print 可抛 BrokenPipeError 阻断启动；另 null/dup2 失败可能留下终端诊断。已修统一安全诊断、末级静默降级和 SIGPIPE 保留，新增故障回归；本节记录修复事实，最终关闭结论由独立审查给出。Cover event及UI Popen 也属于本次追加受审范围。
