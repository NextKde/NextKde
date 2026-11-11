# 输入法弹窗动画

候选框和中英提示使用 `InputMethodPresentation.qml` 保存最后一份完整内容和
光标锚点，直到退出动画完成。同一事件循环内的 Kimpanel 更新合并提交；显示期间
更新内容不重播入场动画。退出途中再次切换时，共用的 `PopupMotion` 从当前进度反向继续。

候选框入场 210 ms、退场 160 ms，轻微收缩 4%；中英提示入场 190 ms、退场
140 ms，轻微收缩 10%。文字、阴影和合成器材质共用显隐进度。候选框尺寸变化以
160 ms 平滑衔接，选中底板平滑跟随，文字保持左上内边距定位。光标跟踪立即更新，退场开始即关闭输入区域。
跨屏时旧面板在原光标位置淡出。

空的全屏层窗口保持映射并使用空输入区域，只显隐卡片，避免窗口映射特效移动整个
表面。每次打开先查询新的合成器光标位置，再显示内容，最长等待 180 ms；关闭后或
超时后的旧响应作废。未初始化的 spot 坐标使用鼠标/窗口回退，不再误判为绝对 `(0, 0)`。

以下命令**仅在专用 VM 或托管 CI 执行**：

```sh
node tests/inputmethod/run.mjs /usr/lib/qt6/bin/qmltestrunner
node shell/desktop/modules/inputmethod/test_inputmethod_placement.mjs
node shell/desktop/modules/inputmethod/test_inputmethod_status_dismissal.mjs
python3 tools/tests/test_fcitx_panel_install.py
```

测试运行生产 QML 呈现及动画组件，覆盖退出快照、动画反向、状态合并、跨屏和空内容。
统一接管验收必须保留 Kate/Qt 的 `QT_IM_MODULE=fcitx` 和 GTK 3/4 的
`GTK_IM_MODULE=fcitx`，覆盖 Wayland 和支持时的 XWayland。开启一次后输入
`nihao`，分别用键盘和鼠标选词，确认中文上屏且没有第二个客户端候选窗。
保持应用打开，关闭接管并确认原有候选界面与输入恢复；前端退出后，扩展的
`Active` 应为 false、`ContextCount` 应为零。桥接测试还覆盖扩展缺失/版本不兼容
时的回退、备份失败与崩溃恢复。不得通过改写应用输入模块变量使测试通过。
没有连接 Fcitx5 的应用不属于此项验收范围。

它不验证 KWin 玻璃渲染。真实 VM 还需验收输入与上屏、快速中英切换、横向及纵向
候选布局、屏幕边缘定位，并使用安装后的 Shell。

同一测试入口还覆盖呈现偏好的读取和保存、拒绝输入引擎配置项、保存失败反馈、自动
布局、点击索引保持、注释显隐、字号、对比度、长列表边界和减少动画。虚拟机验收应
在正在组词时调整这些偏好，确认 Fcitx 配置文件未改变，并可正常选词上屏。

启动台验收还需要从继承 `QT_IM_MODULE=fcitx QT_IM_MODULES=fcitx` 的环境启动真实
Shell，确认入口指令仍选择原生 Wayland 输入上下文。启用接管后，在启动台搜索框
输入 `nihao`，玻璃候选框应出现在搜索光标旁，空格应上屏“你好”；关闭接管后再
检查 Fcitx 原生界面回退。源码/开发模式和安装模式均需覆盖；输入上下文变更不能
仅靠热重载验收。候选框截图应避免唤起区域选择浮层，以免抢走启动台的键盘焦点。

专用 `input method motion` 工作流在候选分支运行这些检查；CTest 也将其纳入
logic 和 headless 测试组。关于应用程序兼容性分类与排障方法（例如 Wayland 文本输入协议要求及独立打包运行时的适配规避方案），请参阅[输入法集成与应用兼容性指南](../../docs/InputMethodIntegration.zh-CN.md)。

[English](README.md)
