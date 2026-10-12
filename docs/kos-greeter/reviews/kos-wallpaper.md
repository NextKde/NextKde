# KOS 当前壁纸自动接入临时脚本独立审查

日期：2026-10-11，Asia/Shanghai。执行者 `/root`；独立只读审查者 `/root/t07_review`，未参与实现。

范围：本增量 SHA256SUMS 中的脚本、选图与消费 helper、WallpaperSource、测试、文档和证据。分支 codex/notification-center-stacks。

初审两项 P2：授权文件缺 owner/mode 检查；无发布/另一 UID 发布阻断本账户禁用选择。执行者修复为同一 FD 校验 owner、安全权限、nlink=1；撤销不存在或其他 UID 的发布返回 False，仍禁用本账户偏好。增加故障覆盖。另修复 start 的 TTY/root 检查顺序，在读取私有图之前拒绝不合法 start。

最终复审通过，无未关闭 P0/P1/P2/P3。冻结摘要 `95ec5843c261a340330b12d68af7411a496b951b33088b4886b848bc47ced497` 全部校验通过，归档为 kos-wallpaper-reviewed-SHA256SUMS。独立重跑 20 项脚本测试与选图测试通过。选图、T03 发布、真实 helper、staged QML 解码、UID 隔离及撤销证据匹配。

未测：真实系统切换、root 部署、真实 PAM 与物理呈现；实机只读预检因原显示管理器 inactive 拒绝，属环境限制。

报告状态及实机预检结果差量后摘要 `0594d7fb26b209cc290b6eb473f77d5eb5c51a5f8808194049f61fde7e1c9818`；代码、测试和原始日志未变化。同一独立代理已确认状态差量通过，最终摘要全部校验通过，实现、测试及原始证据未变，可完成，无未关闭 P0–P3。审查记录不纳入自身摘要以避免自引用。
