# T12 执行记录

任务/验收：T12，A12/A13 隔离子项。状态：阻断（实现/隔离交付；独立复审通过）；完整 A12/A13 与 T11 依赖仍阻断。
执行者：Codex 主代理。日期/时区：2026-10-12 Asia/Shanghai。
分支：codex/notification-center-stacks。基线：54512887915152c514b9d08f3a45ca14779e1adc；本次工作区文件摘要见 ../../reviews/T12.sha256。
版本：Quickshell 0.3.2（Arch），KWin 6.7.5。真实 greetd/VT/DRM/GPU驱动不参与本次运行，未测。
环境：本机非生产临时目录；虚拟 KWin 两个1024×768输出，独立 DBus；没有改显示管理器、PAM、系统服务或账户权限。

## 产物与验证

- [契约与主题支持表](../../contracts/wallpaper-fallback.md)：全模式明确静态回退、资源权限、未知 QML、背景专用采集边界及预算。
- `apps/greeter/tests/fallback.test.py`：五个预生成主题、未知主题固定色、空间二维原图、无同意、版本/fit不匹配、撤销、过期、替换和损坏。结果 [fallback.log](fallback.log)。每个公开输出均逐字节比对规范化 PNG，不是 phase 字段比较。
- `apps/greeter/tests/entry-virtual.test.py`：生产 SessionEntryService 与生产 Cover，双屏模拟静态层；冷/热、默认色、Cover晚到、必要组件延迟、输出缺帧及资源撤销。输出 [virtual-summary.log](virtual-summary.log)，详细事件在各 case .log。名称 hash-mismatch 的旧夹具当前注入公开 store 撤销（故意保留名称以兼容原七项断言）。
- 生产层扩展：`KOS_T12_PRODUCTION_LAYER=1` 实际加载生产 SpatialWallpaperWindow、WallpaperImageLayer 和共享 StaticWallpaperImage；动态/空间服务仍用初始 active 桩。七项场景外增加 fit/center，并对仅背景 entryWallpaper Item 离屏图逐输出核对留白 #16283b 与中心像素，九项通过，证据在 [production-layer/summary.log](production-layer/summary.log)，两输出 fit/center 的四张 PNG 均为本轮新生成。这不是完整 Shell 或真实 GPU动态重放。
- 既有 entry identity、kos-wallpaper、IPC拒绝/重复请求和首过渡抑制测试通过；细项写入 checks.log。

背景静态来源是仓库预生成资产与夹具生成纯色图，未捕获任何用户界面。不保存密码、头像或用户窗口截图；测试不连接 GREETD_SOCK，不导入全局环境令牌。A13 的本次新增代码/数据范围人工审阅通过，完整认证隐私矩阵仍未测。

## 时间线与故障恢复

认证、launch、登录 KWin 退出：未测。虚拟日志记录 KOS_ENTRY ResourceMatched/FrameSubmitted/RevealStarted/RevealComplete 与 Cover 提交/撤罩；Date.now 时间戳仅用于隔离同机事件排序，未进行跨真实会话 presentation 对齐。实际 scanout、空白帧数、240Hz/1.5、Tahoe叠图、冷启动录像：未测。

输出不登记或公开资源撤销时，桌面12秒超时放行；Cover自身仍保持独立撤罩期限。测试 finally 对夹具 Quickshell 发 SIGTERM，必要时2秒后 SIGKILL，临时目录自动删除；虚拟 KWin 随 session 退出。准确故障耗时以各日志事件为准，没有测真实 TTY 恢复耗时。系统服务保持原状态，未执行安装/部署。

## 限制与结论

本卡交付安全静态方案及实现，不交付可信 phase 恢复或 GPU快照。实际预生成图不是登录动画最后一帧；本次不声称 GPU 重启可复现。生产静态窗口已进入隔离渲染；正式前景/动态服务的完整 Shell 实机渲染、Greeter-Cover-桌面三阶段同版本（T08终帧）及 T11 完整 A03/A10 未测，不能因双屏夹具通过关闭这些依赖。完整 T12 状态保持阻断，安全静态回退实现及隔离交付已独立复审通过。

## 独立审查

见 [审查记录](../../reviews/T12.md)。审查者未参与实现，最终被审文件摘要见该记录。本次未进行系统部署。

测试夹具修复记录：生产层扩展首轮因 QML 本地类型登记/绝对 import URL 、背景容器无QML引擎及 Python夹具语法错误失败；随后修正，日志变量遮蔽和缺帧注入同步修复。失败发生在隔离临时环境，finally/虚拟会话边界清理进程，无系统配置变更。最终只用后续通过运行作证，未将这些失败写作生产功能通过。
