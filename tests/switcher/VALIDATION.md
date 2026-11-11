# T1 验证记录（未完成验收）

日期：2026-11-12。工作分支：`astral/switcher-astra`。

## 实现与边界

- KWin 原生 TabBox 继续处理 Alt+Tab、反向、循环、MRU 和释放激活。可选接管只切换 `[TabBox] LayoutName`，不重绑 `Walk Through Windows`。
- TabBox QML 适配器通过已有 `org.kos.Platform.Publish` 转发显示状态与 UUID。Shell 使用现有 WindowService 元数据、静态缩略图，以及 StageCard 所用的 ScreencastingRequest/PipeWire 路径。
- 设置默认关闭；保存原布局（包括配置项原先不存在），关闭时恢复。用户后来在 KDE 选择其他布局时尊重该选择。切换失败会尝试回滚，保留恢复记录。
- 未修改 `kwin/` 下的 C++。SettingsBridge 的异步方法和 Python 配置辅助脚本属于本次集成；没有新建平台通信通道。
- 同应用分栏按任务允许延期，已留 TODO。

任务引用复核：ShortcutsService 的 `net.local.kos-window-switcher` 实际为 Quick Search、默认 `Meta+Shift+Space`，保持不变；实际像素捕获在 `platform/src/kwin/KWinBridge.cpp`，window-bridge.js 提供 UUID/窗口元数据。StageCard 是专用大组件，因此复用其流接口与共享玻璃组件，没有直接嵌套整个 StageCard。

## 本地已完成

```sh
cmake -S . -B .build/switcher -G Ninja \
  -DKOS_BUILD_KWIN_PLUGINS=OFF -DKOS_BUILD_SPATIAL=OFF -DBUILD_TESTING=ON
cmake --build .build/switcher \
  --target kos-settings kos-kwin-shortcut-conflict-test -j 4
ctest --test-dir .build/switcher \
  -R '(switcher-|kwin-shortcut-conflict)' --output-on-failure
```

配置、编译均 exit 0；CTest 实际输出：

```text
kos-shell.switcher-state .............. Passed 1.40 sec
kos-shell.switcher-layout ............. Passed 0.30 sec
kos-shell.switcher-content ............ Passed 1.71 sec
kos-platform.kwin-shortcut-conflict ... Passed 0.02 sec
100% tests passed out of 4
Total Test time (real) = 3.42 sec
```

```sh
QMLLINT=/usr/lib/qt6/bin/qmllint node tools/ci/qmllint-changed.mjs --base 6df77a57
/usr/lib/qt6/bin/qmllint --ignore-settings --only-explicit-categories \
  tests/switcher/content.qml tests/switcher/shell.qml
```

实际输出为 `qmllint 6.12.0`、`QML syntax: 8 files, OK`；新 fixture 单独检查 exit 0。这是仓库规定的语法 lint，不能解释为所有严格类型诊断通过。`git diff --check` 无输出。

单独运行状态测试得到 `5 passed, 0 failed`；Python 布局测试 `Ran 3 tests ... OK`。状态测试使用依赖替身，真实组件测试另用 Quickshell 离屏加载真实卡片和玻璃，得到 `SWITCHER_CONTENT_PASS`。后者不连接平台服务、不改 KWin 配置、不请求真实窗口捕获；离屏后端及缺失服务会有预期警告，不能称为运行日志完全无警告。

## VM 观察与失败证据

必须在实际 KWin 会话验证键盘 grab、Alt 释放、缩略图捕获和合成器玻璃；离屏测试不覆盖这些行为。使用 kos-vm skill，在 `172.20.23.2` 的独立源码目录 `/home/amao/kos-switcher-astra` 运行 fixture；未替换 KWin 插件。

环境为 KWin 6.6.6 / Qt 6.10.2 / Wayland / Virtual-1 1280×800；开启 Kate、Dolphin、Konsole。收到原生 switcher 事件和现有 bridge 的 thumbnail 返回。实际截图仍未显示浮层：`open=true`、窗口 `visible=true` 和正确尺寸不足以证明画面显示。

- `screenshots/switcher/native-before.png`：一次原生切换器截图，仅为静态基线。
- `screenshots/switcher/overlay-not-visible.png`：失败截图，画面没有玻璃切换器，不能用作成功验收。
- 重复 fixture 实例污染了会话；原生列表出现两个 quickshell 窗口，原因未确认。
- 先前将不可见归因于 X11 的判断没有证据支持；后来查询的实例均显示 Wayland。

自动审批阻塞了三类动作：给 org.kos.Shell 授予 `zkde_screencast_unstable_v1`；停止旧 fixture PID；继续向 VM 注入输入及恢复原生布局。没有绕过这些拒绝。源码中的实验 AppId/桌面权限声明已撤回，现有应用身份保持原样。

最后一次只读检查：VM `LayoutName=kos-glass`，fixture 设置 enabled=true，未按键时 open=false。仍列出的 fixture PID 为 `1810678`、`1812819`、`1814493`，生产 shell PID `1805356`。这些 PID 仅是当时记录，后续操作前必须重新核对。

恢复资料位于 VM：

```text
/home/amao/.local/state/quickshell/by-shell/ec892db7b5626997d2551db57966db71/switcher/native-layout.json
```

授权恢复写操作后，应先在确认的 fixture 上调用 `switcher-test enable false`，等 changing=false 且 error 为空、确认原布局已恢复，再停止测试实例。当前恢复工作没有完成。

## 未完成项

1. 查清 PanelWindow 在 VM 不可见的原因，取得真正展开与选中项截图。
2. 实时 PipeWire 流权限及实际画面验证；当前只有已有 bridge 静态缩略图返回证据。
3. 连续 Tab 不闪烁、不重排、反向/循环、快速点按及释放激活的完整真机回归。
4. 关闭开关后与改动前逐帧一致的实际采集与比较。没有做，也没有以配置恢复单测替代。
5. Settings UI 在 VM 经实际 SettingsBridge 开关的端到端验证；目前只编译通过。
6. 清理重复测试实例、恢复 VM 原生布局，受审批阻塞。
7. Shell 崩溃后的原生布局自动回退尚未实现；事件 lease 只关闭浮层。当前会话快照也没有完整处理 chord 期间窗口关闭/元数据晚到，需要在稳定真机环境继续验证。

这份记录明确表示 T1 未达到交付验收条件，不应据此合并为已验证功能。
