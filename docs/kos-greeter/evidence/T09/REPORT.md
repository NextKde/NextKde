# T09 会话 wrapper 与交接证据

任务/验收：T09；A11/A13（有限描述、文件隔离与本地进程范围）。
状态：通过（T09范围；独立复审通过）。
执行者：Codex 主代理。日期：2026-10-12，Asia/Shanghai。
分支：codex/notification-center-stacks；基线、Python、内核见 environment.txt。工作区包含之前任务未提交改动，只冻结本次路径，SHA256 见 SHA256SUMS。
环境：本机临时目录及 Python 子进程，无 seat/VT/modeset；未运行真实 greetd/KWin/GPU 或登录显示模式；另外运行 Quickshell offscreen + mock greetd IPC 回归，组件版本见 environment.txt。真实 XDG_RUNTIME_DIR 在生产入口读取；测试用隔离0700目录模拟结构。
前置条件：Python3、Pillow；固定 Plasma desktop allowlist 的 `--check` 已通过；T02/T03/T06 已关闭。测试不会安装或切换系统服务。

## 操作与实测

`python3 apps/greeter/tests/handoff.test.py`；脱敏结果见 tests.txt：JSON/版本/未知字段/重复字段/过期/跨 session/UID/任意路径/穿越/错误hash/超长/输出数值/文件替换/修改/symlink/权限/资源撤销/版本替换全部拒绝。发布图像19×13，消费 hash 与T03活跃发布值一致。

同 UID 两份描述：session nonce及0700目录各异、0600文件；单次消费与清理A后B仍在，退出B后没有session目录。仅文件隔离，未声称两套完整桌面并发。

原子写入使用 O_EXCL 临时文件、fsync和目录fd replace；消费校验 inode/摘要。拒绝第二个 flock 持有者；mock共享Shell活动、logind其他图形会话与检查失败均拒绝，不触碰真实服务。

子进程夹具验证局部三个展示引用；非法描述时记录固定拒绝代码，并移除陈旧引用，仍启动子进程默认背景。正常退出、exit7、可执行路径不存在及TERM均清理本session；其他session文件保持。目标是夹具，不是真实 Plasma 启动。

回归：wallpaper.test.py通过；resources.test.py 12项通过；lifecycle.test.cjs通过；kos-user-session --check通过；Python编译通过。静态人工审查：描述无密码/token/命令/DBus字段，拒绝日志不输出原输入，无 systemd/dbus import展示字段。既有 Plasma 启动行为不在本卡重构范围。

## 故障恢复与最终状态

每项非法描述：忽略并使用内置背景；测试夹具立即进入可用命令，恢复耗时包含在tests.txt总耗时，不伪造真实桌面恢复时间。并发/图形实例拒绝：关闭新建session目录，保留既有会话。命令失败/TERM：finally按持有fd清理；TERM最长5秒升级KILL。最终测试无session目录/夹具子进程残留，只有隔离runtime内的持久锁文件，TemporaryDirectory退出时删除。系统登录配置和服务未变。

SIGKILL/断电：未测即时清理；finally不可运行，过期描述拒绝消费，runtime注销时删除。真实XDG_RUNTIME_DIR桌面启动、T10 Cover消费、T11揭幕、T14持久安装与完整多会话拒绝实测留给对应任务。T08终帧资源引用尚未传入wrapper，不声称跨launch画面连续。

真实 Quickshell mock IPC 12个场景通过，断言 start_session argv 为 wrapper绝对路径、env为空；结果见 ipc.txt。这是协议夹具，未执行真实wrapper桌面启动。

时间线/录像/视觉/scanout：未测，不声称零黑帧或Tahoe 1:1。

## 独立审查

独立代理 /root/review_t09 全程只读，未参与实现。初审发现巨整数异常P2及UTF-8契约P3，均修复并经独立复审关闭；37个拒绝案例和12个Quickshell mock IPC场景独立复跑通过。完整记录见 ../../reviews/T09.md，功能被审摘要见 REVIEWED-SHA256SUMS，关闭记账后的摘要见 SHA256SUMS。没有遗留P0/P1/P2/P3。真实集成未测边界保持不变。
