# KWin 最终隔离验证

日期：2026-10-13。**实验实现及隔离验证已完成，待独立复审；真实 DRM/VT/宿主黑屏未验收，未部署。**

- 最终行为补丁真实编译链接通过：`kwin_wayland`、同前缀 wrapper、libkwin；必要增量以 `nice 10 -j2` 执行。接收 PNG 已限 16MiB、nlink=1。产物摘要见 `KWIN-artifacts.json`，构建日志见 `KWIN-build.log`。
- 最终双虚拟输出八场景全部退出 0：normal、三秒 timeout、cancel、十五秒 bootstrap 自撤、nonce/CONFIRM READY、SCM 图 fd、拒绝多个 fd、CONFIRM 安全窗不足 EXPIRED。对应 `KWIN-virtual-*.log`。使用私有 bwrap/DBus，隐藏宿主设备/运行时/socket，无真实认证访问。
- 最终 native publication parser 十四场景全部通过，见 `KWIN-publication-final.log`。覆盖 cover/contain 及 UID/hash/尺寸/fit/期限/字段/权限/撤销/symlink/avatar 负例。两个固定根的 installed-root 正向/撤销优先选择未单独行为测试；Live KWin publication 撤销仍未单独执行。
- 初次失败及当时冻结状态另存 `KWIN-HISTORICAL-REPORT.md` / `KWIN-first-normal-failed.log`。修复跨 executable/libkwin hidden 状态副本，改唯一导出状态；同时 fixture 显式 console logging，避免隐藏 `/run` 后缺失 Qt info 日志导致断言误判。最终 normal gate 的实际正负行为已通过，不以符号检查代替测试。
- 最终 patch 对固定上游原始文件 `git apply --check` 通过；被审文件摘要见 `KWIN-SHA256SUMS`。系统侧 helper→实际 VirtualKWin 集成由协调代理另存 `systemd/` 证据，不冒充真实 PAM/DRM 运行。

没有替换宿主 `/usr`、修改 PAM、重启 greetd/KWin/logind、切换 VT 或连接真实 GREETD_SOCK；没有后台编译进程。NVIDIA CloseFB、跨 GPU、真实输出切换、物理黑帧、source 退出后硬件持帧的撤销/超时恢复仍属于实机验证，未宣称零黑帧或宿主已经修好。

运行、独立前缀/VM 部署边界与回退见实验 README。独立审核由主代理另行派发；本报告不关闭原实机 A16/A18/G5 门槛。
