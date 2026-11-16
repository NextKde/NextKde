# T6 首屏揭示动画：实现与验证记录

2026-11-12，分支 `astral/startup-reveal-astra`。实现已提交；真实 VM 验收尚未完成，不能标记 T6 全部通过。

## 实现

- `shell/desktop/modules/common/StartupReveal.qml` 独立维护 `idle → fading → bar → dock → icons → done`，公开 `progress`，默认 800ms。
- 壁纸淡入、顶栏从下方 12px 滑入、Dock 从所在屏幕边缘弹起、图标错峰落位。顶栏/Dock 继续叠加原有自动隐藏控制器；启动动画不改变其输入 mask。桌面图标只动视觉子项。
- `DesktopEnvironment.qml` 构建完成后显式初始化。配置、输出与壁纸就绪后，原生 monitor 等待当前 exposed QQuickWindow 提交首帧，再启动按实际经过时间推进的计时器。就绪阶段有 1200ms fail-open，避免资源缺失导致桌面永久隐藏。
- Qt 应用事件过滤器同步完成 reveal 后返回 false，让原输入继续分发。KWin InputEventSpy 补充其他窗口上的全局键鼠/触摸观察，只发一次不带按键内容的信号，观察上限 3000ms。
- 设置页增加“减少动效”和 600/700/800/900ms 时长；异步 SettingsBridge 更新 AppearanceConfigService 并持久化。减少动效直接 done。
- shell.qml 未添加编排，无 greeter、Plymouth、SDDM 依赖。

首帧等待修正经过编译和离屏测试，尚未获得完整 shell/VM 复测结果。它不能作为已解决真实 VM 跳阶段的证据。

## 任务卡位置复核与假设

- `shell/shell.qml:11` 是 StateDir 说明，真实入口为 ShellRoot/DesktopEnvironment，初始化在 DesktopEnvironment。
- DockWindowPreview 的 reveal 属于 hover preview，未复用。
- “bar 下没有 reveal”与当前代码不符：BarAutoHideController/BarWindow 已有自动隐藏 revealProgress，本次单独叠加 StartupReveal。
- “顶栏从下滑入”解释为从最终位置下方 12px 回到顶边；侧边 Dock 从其对应边缘进入。
- 当前项目默认启动台快捷键是 `Meta+Space`，并非裸 Super。裸 Super 跳过、启动台打开与 reveal 重叠是不同验收项；没有更改用户快捷键。
- 离屏只能验证 Qt 输入传递；KWin layer-shell mask、全局 Super 与真实渲染必须在 VM 验证。VM 使用任务指定的 `kos-vm-dev`（172.20.23.3）。

## 文件范围

- 编排及视觉：StartupReveal.qml、common/qmldir、DesktopEnvironment.qml、BarWindow.qml、DockWindow.qml、FreeSlotDesktopDemo.qml、SpatialWallpaperWindow.qml。
- 输入：surface-shape 的 startupinputmonitor.h/.cpp、surfaceshapeplugin.cpp、CMakeLists.txt，以及 contextmenuinputeffect.h/.cpp。
- 设置：AppearanceConfigService.qml、ThemeSettingsPage.qml、SettingsBridge.h、SettingsBridgeAppearance.cpp、ZhCatalog.mjs。
- 验证：顶层 CMakeLists.txt；tests/shell-startup 下 reveal.mjs、run.mjs、isolated-platform.py、process_lines.py、record-vm.py、interact-vm.py。

## 已通过的本地验证

```text
$ cmake --build .build/startup-native -j4
[5/5] Linking CXX shared module qml/Kos/SurfaceShape/libkos_surface_shape.so

$ cmake --build .build/startup --target kos_surface_shape kos-settings -j4
[5/6] Linking CXX shared module qml/Kos/SurfaceShape/libkos_surface_shape.so

$ cmake --build .build/startup-input -j4
ninja: no work to do.

$ QT_FORCE_STDERR_LOGGING=1 ctest --test-dir .build/startup \
    -R 'kos-shell.startup-reveal|kos-settings.qml-smoke' --output-on-failure
1/2 Test  #30: kos-shell.startup-reveal ......... Passed  2.38 sec
2/2 Test #145: kos-settings.qml-smoke ........... Passed  0.53 sec
100% tests passed out of 2
Total Test time (real) = 2.92 sec
```

状态机测试真实输出：

```text
PASS : qmltestrunner::StartupReveal::test_click_at_zero_delivered()
PASS : qmltestrunner::StartupReveal::test_keyboard_and_motion()
PASS : qmltestrunner::StartupReveal::test_launcher_cancels_before_open()
PASS : qmltestrunner::StartupReveal::test_missing_wallpaper_fails_open()
PASS : qmltestrunner::StartupReveal::test_order_and_duration()
PASS : qmltestrunner::StartupReveal::test_reduce_motion()
PASS : qmltestrunner::StartupReveal::test_stagger_and_no_replay()
Totals: 9 passed, 0 failed, 0 skipped, 0 blacklisted, 2281ms
```

此测试替换外部服务和 Quickshell 生命周期宿主，保留生产状态机与真实原生输入 monitor。progress=0 的离屏 MouseArea 点击通过，不等于真实 Dock 首击通过。

设置 smoke 仍输出现有 LiquidGlassSwitch/LiquidSlider/ColorRampSlider 覆盖 enabled 属性的警告。Python 四个脚本语法检查通过；三行同时写入的日志读取检查得到 `3/3 lines received before process exit`。`node --check tests/shell-startup/run.mjs` 与 `git diff --check` 通过。

## 完整 shell 与 VM 结果

首帧等待修正前，本地隔离 headless 测试实际失败：

```text
shell.qml loaded and stayed alive on headless weston
StartupReveal: idle → fading → dock → icons → done
```

因此 run.mjs 已从“加载后仍存活”增强为要求完整阶段顺序，并使用隔离状态与拒绝会话写入的代理。首帧修正后的完整复测被自动审批拦截，没有通过结果。Weston 不提供 KWin layer-shell/glass/窗口管理协议，相关警告不代表 VM 路径结论。

VM 早期三轮日志记录完整顺序，观察时长 895/872/870ms。后续补录则为 914/881/1013ms，其中第三轮仅 `idle,fading,done`。旧脚本将 TextIO.readline 与 selectors 混用，会延迟读取已缓冲日志，所以这些时长只能作为旧观察记录。当前脚本改用独立读取线程、记录读取时间、检查裁切视频实际长度及 600–900ms 窗口；尚未重跑。

真实输入失败记录：

```json
{"mode":"click","before":{"phase":"fading","progress":0.08375},"after":{"phase":"done","progress":1},"launcher":{"open":false}}
```

这证明输入结束了 reveal，但启动台未打开。坐标 (429,764) 与 1280×800 截图中的启动台图标一致，仍缺正常显示后的点击对照，原因未定位。精确 progress=0 的真实 ydotool 点击尚未完成。

interact-vm.py 已增加 rest-click 对照、zero-click、动画中点击、Super、IPC 启动台重叠、减少动效独立测试；每项失败后继续其他项，最终恢复隔离配置原文。IPC 重叠测试不冒充实际快捷键验证。

## 录屏证据

工作树下 `tmp/startup-reveal/` 保留旧版录屏（未纳入 git）：

| 文件 | ffprobe 实测 | 说明 |
| --- | --- | --- |
| arrival-2.webm | 1280×800，3.250s | 早期完整顺序录像，有原会话窗口遮挡 |
| arrival-3.webm | 1280×800，3.384s | 同上 |
| arrival-clean.webm | 1280×800，3.200s | 补录第二轮，仍残留 KWin 调试控制台，并非完全干净 |
| arrival-1.webm | 1280×800，2.884s | 不满足 3–5 秒要求，不作为交付片段 |

这些片段来自首帧等待修正前，不能证明当前 HEAD 的视觉稳定性。逐帧图 contact.png/clean-contact.png 同目录可查。

## 未完成项与阻塞

1. 真实 Dock 首击打开失败尚未定位；精确 progress=0 点击未完成。
2. 当前 HEAD 的三次稳定 VM 录制、Super 实际快捷键打开、减少动效重启和设置真实 UI 操作尚未完成。
3. 首帧等待修正后的完整 headless 测试尚未执行。
4. 最新原生修改尚未同步并在 VM 构建/加载，VM 仍使用早期 2000ms 观察版本。

自动审批先后拒绝：

- VM 对照测试：`[Remote Shell Writes]`，认为远程启动应用、注入输入与写截图需要明确授权。原任务已要求这些验证，但当前审批仍拦截，因此没有改用其他通道绕过。
- 本地 Weston 复测：`[Code from External]`，执行此前下载的 Weston 二进制需要批准。

此前修改共享壁纸也曾被拒绝；之后改用独立 StateDir、壁纸配置与只读透传代理，没有重复该写入。

VM 测试痕迹仍需处理：kos-startup-proxy 在最后一次检查时 active；临时 KWin 脚本 kos-startup-capture 已加载；原有应用曾最小化。context-menu-input effect 曾替换为测试版，备份位于 VM `~/kos-startup-reveal-astra/.build/input/original-kos_context_menu_input.so`。没有声称已恢复环境；恢复 effect 也需正常 KDE 注销后加载，不能原地 reload。测试脚本自行终止其创建的 shell/录制进程，不应停止原有 Spectacle 进程。

下一步：解除上述执行阻塞后，先跑正常 Dock 点击对照，定位真实首击问题，再部署当前原生插件、重跑三轮录屏和全部交互，最后清理测试代理/脚本并明确 effect 恢复状态。
