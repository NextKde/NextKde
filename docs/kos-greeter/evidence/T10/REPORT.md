# T10 早期 Cover 隔离验收

日期/时区：2026-10-12 Asia/Shanghai。执行者：Codex。状态：完成（实现/隔离 A09/A14-C 及独立复审通过）。
基线：54512887915152c514b9d08f3a45ca14779e1adc；未提交实现按 SHA256SUMS 冻结。分支 codex/notification-center-stacks；仓库原有未提交改动保留。
版本：Quickshell 0.3.2、KWin 6.7.5、Qt 6.12.0、内核 7.2.9-zen1-1-zen。环境：独立 dbus-run-session + virtual KWin，2×1024×768 输出，60 Hz（wl_output.mode refresh=60000），scale 1，非 DRM/VT 登录会话。GPU/驱动不作为本卡呈现验收依据，未测物理 scanout；greetd 未调用。
前置：T07 宿主与 T09 wrapper 已交付；使用临时 app 副本和人工夹具，无密码、用户窗口或真实壁纸截图。恢复为结束隔离进程组，未修改系统服务。

## 步骤与证据

`python3 apps/greeter/tests/cover.test.py`：运行真实 Qt/Wayland 窗口；结果见 results.log，环境日志 virtual.log。每个 `*.log` 保存 WAYLAND_DEBUG、资源/映射/帧提交和退出记录；`*-Virtual-*.png` 仅 grabToImage 的 Cover 自身图层，非整屏/scanout 截图。

| 场景 | 证据 | 结果及恢复 |
| --- | --- | --- |
| 有效静态图、无发布资源 | valid-resource.log / shell-ready.log / 各输出 PNG | 两输出映射、资源事件和帧提交；模拟 ready 后退出 |
| 主动撤罩 | recovery-ipc.log | 模拟 abort 后退出 |
| Cover 自身崩溃 | cover-crash.log | SIGKILL 后 UI 退出，无重启 |
| 输出移除/恢复 | output-removal.log | 实际 KScreen disable/enable，销毁后重新创建/提交；随后 ready |
| Shell 永不 ready | shell-never-ready.log | 自主约 15 秒退出，无 Shell 依赖 |
| 一输出无就绪信号 | one-output-unready.log | 夹具抑制 Virtual-1 readiness/submission 事件；约 15 秒退出。不是物理 GPU 卡住的测量 |
| 图像缺失 | missing-resource.log | 解码错误回退；模拟 ready 后退出 |

协议检查：每输出 `get_layer_surface(..., 3, "kos-early-cover")`、`set_keyboard_interactivity(0)` 和空 `set_input_region`；窗口实际收到 configure，随后 commit。证明虚拟 compositor 接受 overlay 层及输入策略，不冒充真实锁屏/VT 快捷键验证。

`python3 apps/greeter/tests/cover-supervisor.test.py`：见 supervisor-results.log 和 kwin-restart-0/1.log。实际发布夹具字节/hash匹配、引用单次消费、版本替换与撤销回退、socket 对端 PID 拒绝；总期限用真正的无响应 sleep 子进程替代 Qt，确认 TERM 清理；无 socket 的受控短期限退出。两次独立虚拟 KWin：supervisor 在 socket 可连接后实际启动生产 Cover，双输出帧提交后强杀 KWin，supervisor 清理退出（约 0.1–0.3 秒），第二次重启仍能独立运行，无自动重启。

最终测试已补充正常/崩溃退出码及 ShellReady/Recovery 原因断言，经独立审查建议修复后复跑。

清理补强：poll 与 killpg 间进程已退出时忽略 ProcessLookupError，并继续 wait/描述清理；supervisor 与 wrapper 的受控竞态测试通过。

临时打包文件清单增加 cover.qml 与 companion/cover.py，确保未来用户明确启动临时测试时可以携带 Cover；未执行临时切换。switch-scripts.test.py 的隔离文件系统/模拟 systemd 回归通过，见 staging-regression.log。

T09 回归：handoff-regression.log，37 个拒绝用例、权限/生命周期/信号清理通过。无平台/数据/Shell 导入的源码检查覆盖 cover.qml、cover.py；固定 systemd 服务查询仅用于定位 KWin。

## 时间线和视觉范围

见各日志：ResourceReady（包含固定背景决定）、WindowMapped、FrameSubmitted 分别记录，不把任一当作实际呈现。Python monotonic_ns 和 QML Date.now 使用不同时间基准，不能跨时钟直接计算间隔；恢复耗时由测试进程 monotonic 测得。
有效 PNG 夹具 320×200，RGB #b3652a，crop 全矩形，虚拟 scale 1；两输出 Cover PNG 1024×768，中心像素匹配。无资源 PNG 为 #16283b。T07 已覆盖更多 fit/DPR 组合，T10 不重复宣称真实分数缩放协商。
认证/退场/DRM 接管前空白、正式 Shell 门控与揭幕、presentation/黑帧计数、真实快捷键/TTY：未测。没有外部录像，不报告零黑帧，Cover 首显以前的空白不在覆盖范围。不是 Tahoe 视觉验收。真实 systemd Plasma 冷启动、物理拔线仍由 T11/T14 集成验收。

## 故障恢复和残留

隔离测试均 try/finally 终止所属进程组，UI feed 由 Quickshell Process 生命周期回收；临时目录清理，引用关闭，不清其他会话。测试失败过的输出 connector 硬编码和 KWin dumpability 导致的 socket 识别问题已修正后重跑，以当前日志为准。
固定恢复入口：Cover IPC abort / 按相同配置路径 kill；若桌面不可用可切 TTY。物理 TTY 操作耗时未测，此卡未改任何显示管理器或 PAM。持久安装与完整故障矩阵留 T14。

## 结论

A09、A14-C 的隔离 Cover 子项已运行通过，A11 资源变更回退通过；独立代理 /root/review_t10 初审与增量复审通过，P3 测试断言建议已修复关闭，T10 已关闭。真实 Shell 集成、完整 A14、三阶段一致性、scanout 和跨 KWin 黑帧均未测。见 ../../contracts/early-cover.md 与 ../../reviews/T10.md。
