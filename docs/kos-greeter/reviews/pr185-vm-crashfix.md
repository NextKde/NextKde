# PR 185 虚拟机崩溃修复记录（2026-10-13）

范围：只修复本次虚拟机暴露的 Quickshell 弹窗崩溃和 KWin Dock 动画销毁崩溃。所有 QML、C++ 编译、测试及桌面运行验证均在 `kubuntu` 虚拟机执行；宿主只作源码编辑和虚拟机编排。

## 失败证据与原因

- 虚拟机 `coredumpctl info 4140/7237/25156/2497/3428` 的共同关键栈为 `QQuickItem::window()` → Quickshell 偏移 `0x375349`、`0x33026c` → `QQmlBinding::update()`。18:09:35 的 Quickshell 日志止于应用启动器关闭，18:09:58 的日志止于 Dock 缩略图和全局指针事件。日志没有暴露具体的 QML 属性绑定行。
- Quickshell 0.3.0 的 `PopupAnchor::setItem` 在非空 Item 变成 null 时仍调用 `mItem->window()`。虚拟机最小用例复现了相同的 native 栈。PR 旧基线有 11 个可变 `anchor.item`；合入当前 `main` 后还有 `DockAppNameTooltip` 和 `NotificationHistoryPanel` 两个，原先部署遗漏了后两者。现在 13 处都改为只向锚点写入有效 Item 的 `PopupAnchorBinding`。原先尝试的 QML `Binding` 实现在信号更新顺序下仍写入 null，虚拟机回归失败后已废弃。
- 15:48:33 的 KWin core 1465 指向 `EffectWindow::unrefVisible()` → `DockWindowAnimationEffect::finishAnimation()` → 插件析构。修复了可见引用与删除窗口拥有引用的释放顺序，并在同步回调前移除动画/claim 表项、重新检查窗口存活。合并后的源码保留 `main` 原有的 KWin 正在退出时放弃引用回调保护。
- `drkonqi-coredump-launcher` 本身在处理崩溃时反复 SIGSEGV，形成报告风暴。它是次生故障。测试期间仅对虚拟机当前用户做了 `--runtime` socket/service mask；core 捕获仍保留。重启后该 runtime mask 自动失效。
- 18:37:47 的额外 core 102410 是旧崩溃报告子进程：`COREDUMP_ENVIRON` 中有 `__QUICKSHELL_CRASH_DUMP_PID=3428`，`PPid=2521`，不是新桌面进程崩溃。

## 虚拟机验证

- 修补版弹窗生命周期用例：有效 Item → null（保留旧锚点）→ 新 Item → 销毁；Quickshell 退出码 0 且打印 `PASS popup anchor null, replacement and destruction`。
- 真实 KWin 虚拟输出用例确认 `closeAnimationCount > 0`、`animatingWindows > 0` 后卸载 Dock 插件和退出合成器，均返回 0。审查指出早期退出分支可能等待客户端至动画结束；修正为退出分支立即结束 driver 后，在 18:44 重启的虚拟机空闲状态重新运行，`unload` 和 `exit` 两例都再次通过，测试结束无新 core。用户桌面占用 virgl 时的一次重跑曾因 DRM layer 创建失败而中断，这是环境资源问题，不计为通过。虚拟机实际安装的插件哈希见下文，测试按 KWin 插件名从系统目录加载。
- 合入 `main` 后在虚拟机重新编译原生 Dock 插件成功；ASAN/UBSAN 引用生命周期用例通过，CTest 2/2，弹窗生命周期用例再次通过。
- 18:41:32 重启虚拟机用户态 `kos-shell.service` 后，正式主进程 PID 103247，`NRestarts=0`；Dock 多图标悬停后未产生新 Quickshell/KWin core。18:44 正常重启后 SDDM 启动，18:45:18 用户成功登录；KWin 进程已映射最终插件。18:45:52 虚拟机实际画面显示壁纸、Dock 和已打开的通知历史弹窗，未把截图提交进 PR。用户随后确认已执行启动器开关、Dock 悬停及通知历史操作；18:46:37 虚拟机检查仍显示 `kos-shell.service` 为 `active`、主进程 1825、`NRestarts=0`、本次开机 Quickshell/KWin core 均为 0。

## 部署与回退

虚拟机已最小修改安装目录中的 13 个弹窗、公共 helper/qmldir 和 Dock 插件；原件、哈希及文件属性保存在 `/var/backups/nextkde-crashfix-9apmoh2w`。最终插件 SHA-256 为 `31c305cdb62af11695814a8b2bf3673444cb36cf0d3bfdc000481ca6fe2b59cf`。还原时先退出桌面使 KWin 不再映射插件，再以虚拟机 root 运行 `python3 /var/backups/nextkde-crashfix-9apmoh2w/rollback.py`；脚本验证已安装文件哈希后原子还原。SDDM 已恢复为已启用状态。

独立审查：`/root/review_ci_display` 对合并 `main` 后的最终代码确认无 P0/P1/P2，旧退出测试的 P2 假阳性已关闭；其审查时修订版真实 KWin 用例尚未完成，现在以上述虚拟机结果补齐。长期稳定性和更多实体显示器仍待单独验证。

被审核心源码 SHA-256：`dockwindowanimationeffect.cpp` 为 `554f609127bc336e3b58356af5e21bf3cdbec72748bc5204561da629cfe7bdaa`，`animationwindowreferences.h` 为 `08df6e81f36f3c7e4eba387a583d7b72e8e581b92e09826c17cd59efc4491df5`，`live_lifecycle_test.py` 为 `208997e86356afa9fa2ed9a2ce690e3b8c79dd94693b381209a955351f37b02e`，`PopupAnchorBinding.qml` 为 `155f9b233786793555c68558cba7deebb0e48de70208b88587f534c7087033bc`，`DockAppNameTooltip.qml` 为 `bf324b8ad368f1c2e20ce2d6983b709c5ac9d6f0aa31b1292e7b2f8ed34e682e`，`NotificationHistoryPanel.qml` 为 `3a7ac636cc01dcc9a2d37bd26a970d046825cb849a7763d11032e0a7f17046fc`。
