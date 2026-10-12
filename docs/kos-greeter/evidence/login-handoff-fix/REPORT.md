# 登录交接生产修复

日期：2026-10-12。状态：实现/隔离验证已交付；独立审查记录见 ../../reviews/login-handoff-fix.md（待最终复审）。分支 codex/notification-center-stacks；未提交源码与既有用户变更共享工作树，本批范围以 SHA256SUMS 为准。

## 确认的缺口与修复

1. 本机 SO_PEERCRED 是创建 socket 的 kwin_wayland_wrapper（comm 为 kwin_wayland_wr），旧过滤只允许 kwin_wayland。现在仍限定固定会话/服务树，允许 wrapper，且执行有界 wl_display.sync 才启动 Cover，不将 listen 等同就绪。
2. 本机安装 desktop 缺少 SessionEntryService.qml；仅 Greeter 安装版本完整不等于整个桌面包含 T11。初装、更新、相同 bundle 跳过和 --check 均新增只读 Shell 能力检查。独立 app 不隐式升级 Shell；提供用户级显式同步入口及干运行清单。
3. 统一揭幕等待初始 WindowService provider 与 bar/Dock 初始化后的窗口帧提交。配置、映射、尺寸等变化清空组件帧登记。pending 保留 0.001 covered opacity 使子树继续绘制，不把提交声称为 scanout。

同步范围为完整 desktop QML 依赖闭包及 Kos/Ui 可信共享 QML，不更换 Shell 根入口、原生插件、其它 apps 或服务二进制/用户配置；目录暂存、备份、替换失败回滚。对手工安装 QML 改动先用 --check 看清单。多目录操作不宣称断电原子性。

## 验证

- cover-readiness.test.py：可信 wrapper 树；提前 listen 但无响应的 socket 在 150ms 左右失败；真实 callback、分片事件、其他 peer 拒绝。readiness-tests.txt。
- cover-supervisor.test.py：直接虚拟 KWin 和真实 kwin_wayland_wrapper 双输出均收到 FrameSubmitted，终止测试 KWin 后两轮 supervisor 各 0.215s 退出，无自动重启。日志 kwin-restart-{0,1}.log。测试固定用户服务发现被显式禁用，只接受测试父树。
- entry-virtual.test.py：双屏冷/热夹具、默认背景、晚 Cover、延迟必要组件、丢失输出帧、hash 错误共 7 项通过；virtual.log 与各场景 log。生产 SessionEntryService 运行于虚拟 fixture，provider ready 在此显式 stub 为 true，不能替代实际 provider 全链路测试。
- entry-protocol.test.cjs：旧/重复/session/hash/fit/output 拒绝，新增 provider 未完成、必要帧未就绪时拒绝揭幕。protocol-tests.txt。
- install.test.py：36 个 fake-systemd/logind 文件事务测试通过，包含相同安装/升级前检查失败时无系统写操作。install-tests.txt。
- shell-sync.test.py：干运行无改动、第二目录替换故障恢复、symlink materialize、旧文件移除、原生/app/根入口保留、能力缺失检测。shell-sync-tests.txt。
- entry.test.py：2 项通过。QML duplicate handlers 检查 417 文件无重复；qmllint-changed 检查 11 文件无真实语法错误。

## 测试隔离事件与恢复

第一次旧 supervisor 回归意外发现当前生产服务 socket，在 eDP-2 上短暂创建 Cover；它只有一个输出，测试等待双输出失败。原因是原夹具与当前用户 runtime 共存，固定服务 fallback 允许生产服务，即便虚拟 KWin 使用私有 D-Bus 也未限制 supervisor 继承的总线。异常 finally 对测试 compositor/supervisor SIGTERM + wait，supervisor finally 对 Cover 进程组 TERM + wait；未重启或替换当前桌面。该失败输出可在代理工具记录追溯；日志后来被修复后的重复运行覆盖，不能将旧日志当作保留证据。修复夹具通过显式仅子树发现，完全不调用固定服务 fallback；所有测试范围对 supervise 的调用已核查，仅此夹具做真实 compositor发现，其余单元调用显式 mock。

## 未测与边界

未安装本批文件、未切换显示管理器/PAM、未重启当前 Shell。未做真实认证、冷热启动录像、物理 VT/DRM/presentation 与黑帧计量。用户 KWin 接管前的空档仍属底层单独工作。Cover 背景 feed/image settled 首帧规则与 12/15/25 秒故障期限保持原设计。慢于超时会撤罩恢复，不永久遮挡。

现有 T08/T11–T14 的文档主项阻断状态保留；本批源码修复与隔离测试不把缺少的实机证据补写成通过。最终需独立审查，主代理负责派发审查并记录结论。
