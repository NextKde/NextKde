# 最终独立复审记录

日期：2026-10-13。实施者：/root、/root/implement_frame_handoff、/root/complete_coordinator。独立只读复审：/root/review_frozen_handoff。

结论：隔离实验实现通过，本次代码范围未发现仍开放的 P0/P1/P2。源码与隔离证据可交付；不能宣称宿主黑屏已解决，也不批准部署。

## 问题处置

- P1 已关闭：原子VT恢复标记、启动恢复，取消时恢复失败保留marker跨GC且拒绝新ARM覆盖；最终8组故障测试含SIGKILL、失败重试、不重置存活控制器。
- P2 在实验范围关闭：固定VM入口、真实dbus-run-session的私有FD传递/隔离、greetd12测试、真实VirtualKWin与授权器正常交接/过期回滚；CONFIRM仅当前nonce、全部输出呈现且至少剩余一秒才READY。
- P3 已关闭：PNG限制16MiB及nlink=1一致；最终8虚拟场景、14parser场景通过。

## 最终版本

KWin patch SHA256：bded1a76f0f0bd4b27913a5fa49e35eac1d9cfae674148e1d6cbe5bf9ecf60a0。

KWIN-SHA256SUMS SHA256：49e3868b02649d80ab29d1498d9985cd3a67dfff2cb16818f598dd15ecfceb9c。

systemd-v262.patch SHA256：95e1d995bfb4b100589fff8a3cbeff0b0eff908451987105a7f80457b7831056。

systemd/FROZEN-SHA256.json SHA256：2b83cb4befd1b0a2f105a3b2a3de63a69eda1d70e5744b040359568348f57f70。

审核核验全部匹配。旧失败报告保留在 KWIN-HISTORICAL-REPORT.md，不能把旧失败当当前测试结果。

## 未验收边界

真实PAM、三个真实守护进程共同登录、NVIDIA DRM/VT、物理黑帧、旧compositor退出后的硬件恢复仍未验证。installed根选择和Live KWin撤销未单独进行真实KWin行为测试；授权器根选择测试已通过。没有部署宿主或重启其登录服务，不需要回滚。录屏不是开发/隔离测试前提。本记录不关闭原实机验收任务。
