# 登录加载与上拉揭幕（2026-10-12）

实现来源分支：codex/notification-center-stacks；交付分支：codex/kos-greeter（PR #185）。范围：密码提交后加载提示、早期 Cover 加载提示、桌面就绪后整幅 Cover 上拉，bar/Dock 同步以 620ms OutCubic 入场。减少动画模式使用 1ms 揭幕并保留静态加载指示。没有部署或修改系统服务、PAM、显示管理器；现有安装需要更新 app，桌面侧需要加载更新的 SessionEntryService。

## 验证

- entry-protocol.test.cjs：3 项通过（旧/重复交接拒绝、日常同图选择、预览释放）。
- ipc.test.py：12 个真实 Quickshell + 模拟 greetd 场景通过（无真实凭据）。
- entry-virtual.test.py：双输出虚拟 KWin 7 项通过，包含迟到 Cover、延迟组件、丢失帧、hash 不匹配和超时恢复。
- visual.test.py：6 个实际 Qt 渲染场景通过；人工查看 waiting.png，加载指示显示正常。

未测：真实 DRM/TTY 切换及冷热登录录像。两个独立 KWin 会话之间的无显示空档无法由 QML 动画覆盖；本次不宣称消除黑帧。未改变 T01–T14 原验收状态。

## 独立审查

审查代理：/root/review_transition；只读，未参与实现。结论：未发现 P0/P1/P2，IPC 校验、帧门控和超时保留。P3：账号表单中的圆圈与 Cover 固定位置可能发生跳变，保留待实机视觉细调；不阻断加载与上拉目标。Cover 在接受 reveal 请求时启动，桌面在 accepted 回包后启动，存在微小 IPC 时间差。

## 被审文件摘要

- `apps/greeter/qml/LoadingSpinner.qml`：`7bfd09baa6088b3c66978b0aa9d1dab2040a838c46d5d4030032443b7c105827`
- `apps/greeter/shell.qml`：`029802da8393cbb1f961fbec5056cea65c7f5dd25bc4cafe4279f79cd633e999`
- `apps/greeter/cover.qml`：`5a5ff9c35e148cdb642fe6dfcc4fae1dba4d9c357b6096d55b6f133229926c5a`
- `shell/desktop/modules/common/SessionEntryService.qml`：`92c43931b573876327781ede3859e5da275cd4c76beee62158ab67e0856e4266`
- `tools/test-greeter.py`：`95e187f6a7a3cf5cb4436015854eb71f5b9128acbe478c1a0730e9e39cf8f3a1`
