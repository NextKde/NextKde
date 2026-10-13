# PR185 虚拟机接入与崩溃诊断（2026-10-13）

执行者：`/root`；独立只读实现审查：`/root/review_ci_display`。
基线：`60934dc`，分支：`codex/pr185-ci-display-fix`。用户明确授权在已运行的 kubuntu 虚拟机接入，宿主未执行项目测试、编译或启动 Shell。

## 接入修复与静态审查

Ubuntu 的 Plasma 包装器和 greetd 路径不同于原 Arch 固定路径，现采用两个明确 Plasma argv 与两个明确 greetd 位置；未知命令或附加参数仍拒绝。Ubuntu `/run` 为 noexec，临时入口、认证后入口与 KWin UI helper 通过固定 Python 解释器启动。KWin `--exit-with-session` 的命令作为单个参数传入，按上游 KShell::splitArgs 规则编码，避免只启动空 Python 解释器。

首次适配曾在私有切换脚本中引入不可解析的 helper import，实际触发 OnFailure 自动回滚并恢复原 SDDM；已移除该快照依赖。一次源码传输超过宿主 argv 长度上限，没有更新；随后按文件复制、确认完成并重新接入。启动参数单参数问题经源码核对修正并重新部署。保留这些失败，不将较早尝试解释为接入通过。

独立代理审查新增 helper、两个入口、前端、临时工具、打包必需文件和测试差异，未发现新增实质 P0/P1/P2 代码问题。它未独立读取本轮新增 VM 日志，因此运行结果是执行者记录，不能扩大静态审查结论。

## 实际虚拟机结果

环境：Ubuntu 26.10 开发版，Quickshell 0.3.0，Qt 6.11.2，KWin 6.7.5，virtio_gpu/virgl。源码暂存 `/opt/nextkde-pr185-integration`；采用 PR 临时 `/run/kos-greeter-test` 安装，保留原 SDDM 持久启用，1800秒自动回滚。未修改 PAM、现有账户密码或宿主登录管理器。

- VM回归：路径允许清单4项、Greeter配置15项、安装44项、会话日志12项、实际Quickshell+模拟greetd IPC15场景、handoff37个拒绝case全部通过。安装44项是模拟文件系统/服务测试，不是44次真实服务切换。
- 15:49:49：真实 Greeter `Configuration Loaded`，Virtual-1 窗口映射与帧提交，进入认证提示。
- 15:50:41–42：真实认证完成、退场、launch，PAM打开用户会话，Plasma与Cover启动。Cover成功连接用户KWin并提交帧，15:51:02因未收到正式Shell就绪而超时撤罩。
- VM现有桌面安装没有 `SessionEntryService.qml`，尚未同步完整PR桌面侧。真实揭幕闭环不能标通过。
- 本次开始前图形环境已有崩溃；另观察到旧KWin卡在virtio_gpu内核队列、控制台写入阻塞，已通过虚拟机重启恢复。不能将全部既有故障归因于新Greeter。

## 用户反馈的持续崩溃

1. 15:48:33旧用户KWin退出：core PID1465，`EffectWindow::unrefVisible` → `DockWindowAnimationEffect::finishAnimation` → 动画插件析构 → `unloadAllEffects`。这是Dock动画卸载路径，不是Greeter认证失败。
2. 15:50:53与15:51:48桌面Quickshell：core PID4140/7237，`QQuickItem::window()`，相同quickshell偏移`0x375349`/`0x33026c`。VM最小弹窗用例control正常退出；有效`anchor.item`改null用例产生core PID21024，关键调用偏移与桌面一致。Quickshell v0.3.0源码`PopupAnchor::setItem`调用`onItemWindowChanged`，后者直接解引用`mItem->window()`，缺少null保护。已确认这一触发机制，尚未定位完整桌面的具体触发组件或修复应用/上游。
3. KDE `drkonqi-coredump-launcher`自身持续SEGV，socket累计接受数千次请求，放大故障。已仅在VM UID1000用户管理器运行时mask该socket与template service，停止对应报告器，系统core采集保留。这是停止循环，不是修复上述根因，重启会清除运行时mask。

原始core与完整应用日志仍保留在虚拟机；不向仓库复制包含进程内存的core。相关诊断摘要位于VM `/tmp/pr185-core-{1465,4140,7237}.txt`，最小复现目录 `/tmp/pr185-anchor-ba7q9g75`。

结论：临时Greeter已接入且真实认证/启动子项有证据；桌面稳定性、完整揭幕与恢复验收仍有P1阻断，不能宣称PR可合入。手动恢复：文字TTY执行 `sudo python3 /run/kos-greeter-test/private/rollback-greeter.py`；本轮最终计时器原定16:19:48回滚，之后操作须检查实时状态。

同一独立代理随后复审本记录并核对上游PopupAnchor源码，确认文档无P0/P1/P2误导。该复审没有独立读取VM core或复现日志，不扩大运行证据的独立核验范围。

## 被审实现 SHA256

```text
b6dffd9403f5cb3da2a2d4b0ff5acf5ec6a668c9469fd2e93bd4fd61ad8e56cf apps/greeter/bin/kos-greeter-session
5f8288c447183772575738e352e06c07d6d54d67f3c0ab17434018c514a8971a apps/greeter/bin/kos-user-session
af81ab1d26f390fc4b6c4eff2f5572de2fa6c8d1f1a2164b83b4fadc0e110b8f apps/greeter/companion/plasma_session.py
dc4ec4c248c83e8002fde4e3b7a15827a5818c69017b2edabc63a053765604fd apps/greeter/shell.qml
06765446f85d01bbabb12b3fef5d5a3ae26cc990b7bc208d3506e5d365e89b37 apps/greeter/tests/plasma-session.test.py
9a5109828e03a8e51b1de1ac98e014237b6a6c97310fe809a52819900c8187f0 apps/greeter/tests/install.test.py
cd5b449e2d349e8e1f6ec395f2f3040718ceb3cedb84e49c440c9751b5e87fbb apps/greeter/tests/ipc.test.py
e341574a2fd65994403cc4d05c0ec1fd4b5ffe350a7f8dc27e4cf17cad6004e2 tools/test-greeter.py
7007497c87e5f51e5b57fd1928fdf202eaaecddaf91d66e41f26e90c327d4541 tools/greeter-install.py
```
