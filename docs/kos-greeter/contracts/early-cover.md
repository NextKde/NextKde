# T10 早期桌面 Cover

入口为 `apps/greeter/cover.qml`。认证 wrapper 在固定 Plasma 子进程启动后，立即并行启动 `companion/cover.py --supervise <child-pid>`，并局部继承 T09 引用。不增加 platform/data、plasmashell 或 kos-shell 服务依赖，也不 import systemd/DBus 环境。资源安装/启用仍属 T14；此次未安装服务、切换显示管理器。

## 启动和输出

supervisor 等待实际可连接的、当前 UID 的 `wayland-*` socket，使用 SO_PEERCRED 对端 PID 匹配 wrapper 子树中的 KWin；Plasma systemd boot 则匹配固定 `plasma-kwin_wayland.service` MainPID 子树。KWin 禁止 dumpability，因此在这些限定子树内用 `/proc/<pid>/comm` 判定进程名，而不是要求读取 exe 链接。服务查询单次最多 0.5 秒。失败不阻塞 Plasma，25 秒总预算（含 socket 等待）结束，不重启 Cover。共享用户服务仍只支持 T09 排他的单桌面会话，未扩展同 UID 并发支持。

Quickshell.screens 每输出创建一个全屏 overlay layer PanelWindow，namespace=`kos-early-cover`，exclusion Ignore、keyboard focus None、空 input region；不抢输入或保留区，不 modeset。热移除销毁窗口，重新出现创建新实例。复用 WallpaperHost 的静态构图和每屏 DPR。此层级用于遮住普通桌面/bar 初始化，不承诺覆盖锁屏、安全界面或 KWin 接管前空白。

## 资源

QML 的独立 Python feed 单次消费 T09 引用，忽略 KOS_HANDOFF_PATH，校验 UID/session/digest/有效期、当前公开授权及版本。不让 QML 打开描述中的路径。每 0.5 秒重新验证授权和实际发出的图片字节/hash/fit；任何撤销、替换、描述不合法或到期锁存固定 `#16283b`，不跳到不同版本。无授权从首帧使用同一固定背景。feed 超过 2 秒不更新或退出，QML 清空图像；图像解码超时沿用宿主 3 秒回退。不执行主题或任意用户 QML。

## 撤罩与恢复

- 自身 QML 计时器 15 秒撤罩，与输出数量、资源、Shell 状态无关。
- Python 总期限 25 秒包含 socket 等待，能终止卡住的 QML；TERM 后最多 1 秒再 KILL。
- wrapper 退出/收到信号在 finally 终止 supervisor；supervisor finally 终止 Cover。wrapper 最多等待 2 秒再 KILL；其异常被强杀时，QML 自身期限仍生效。
- T11 已通过 `cover describe` / `cover reveal` 接入匹配就绪协议，见 [桌面就绪契约](desktop-ready.md)。`qs -p /绝对安装目录/cover.qml ipc call cover ready` 仅保留 T10 模拟信号/人工恢复兼容，不作为生产就绪依据。`... ipc call cover abort` 是人工撤罩入口。可用相同路径 `qs -p ... kill` 结束实例。Cover 无键盘抓取，TTY 切换仍由 compositor/系统处理。
- KWin 断连时 UI 退出，supervisor 不自动重建；KWin 重启后不重新遮盖初始化。无永久罩、无重启循环。真实 VT 快捷键和真实 Shell 就绪门控留 T11/T14 验证。

## 事件及计时边界

Python 事件 `SocketConnected/SocketTimeout/Deadline/SessionEnded/Exited` 使用 monotonic_ns。QML 的 `ResourceReady/WindowMapped/FrameSubmitted/OutputRemoved/Timeout/ShellReady/Recovery` 使用 Date.now 毫秒，WAYLAND_DEBUG 为协议时间线；二者不能直接相减。测试恢复耗时由外部 Python monotonic 测量。ResourceReady 在此包含已决定的固定回退；WindowMapped 是 backingWindowVisible，FrameSubmitted 是 frameSwapped。未接 presentation-time，均不是 scanout，不能推出零黑帧。

T08 最终资源 hash 尚未显式传入 wrapper，因此 T10 只能校验 T09 描述相对活跃版本；不能证明认证终帧/Cover/桌面三阶段在 launch 前后更新时一致。该缺口保留 T11/T14。

## 2026-10-12 生产 wrapper 修复

限定树内允许 `kwin_wayland` 及 Linux comm 截断名 `kwin_wayland_wr`。后者创建并 listen socket，再把 fd 传给 KWin，因此 SO_PEERCRED 是 wrapper。对端验证通过之后，还执行最多 150ms 的 `wl_display.sync` callback 协议往返；仅 socket connect 不足以触发 Cover。未响应、协议错误/断连均继续有界发现，不启动 UI。它不是首帧或 scanout 证据。

隔离 supervisor 回归显式禁止固定用户服务 fallback，只发现测试 compositor 子树；分别运行直接 KWin 与实际 KWin wrapper，防止测试误连正在使用的桌面。

## 2026-10-12 资源重复工作消除

消费者首次对该内容hash完成严格canonical字节检查之后，可在进程内复用hash/尺寸验证结果；每次仍读取live授权/版本与实际文件bytes并校验权限、SHA256、尺寸，不缓存图片/授权，不绕过撤销。128项上限。source/fit/crop/首帧settled门控保持；不是低清占位策略。新增SocketPeerMatched仅表示可信listener被发现，不等于Wayland响应/可绘制。性能与底层研究见 evidence/handoff-latency-fix/REPORT.md。
