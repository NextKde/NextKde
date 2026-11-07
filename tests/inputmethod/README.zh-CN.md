# 输入法弹窗动画

候选框和中英提示使用 `InputMethodPresentation.qml` 保存最后一份完整内容和
光标锚点，直到退出动画完成。同一事件循环内的 Kimpanel 更新合并提交；显示期间
更新内容不重播入场动画。退出途中再次切换时，共用的 `PopupMotion` 从当前进度反向继续。

候选框入场 150 ms、退场 120 ms，轻微收缩 2.5%；中英提示入场 180 ms、退场
140 ms，轻微收缩 8%。文字、阴影和合成器材质共用显隐进度。候选框尺寸变化以
100 ms 过渡，文字保持左上内边距定位。光标跟踪立即更新，退场开始即关闭输入区域。
跨屏时旧面板在原光标位置淡出。

空的全屏层窗口保持映射并使用空输入区域，只显隐卡片，避免窗口映射特效移动整个
表面。每次打开先查询新的合成器光标位置，再显示内容，最长等待 180 ms；关闭后或
超时后的旧响应作废。未初始化的 spot 坐标使用鼠标/窗口回退，不再误判为绝对 `(0, 0)`。

以下命令**仅在专用 VM 或托管 CI 执行**：

```sh
node tests/inputmethod/run.mjs /usr/lib/qt6/bin/qmltestrunner
node shell/desktop/modules/inputmethod/test_inputmethod_placement.mjs
node shell/desktop/modules/inputmethod/test_inputmethod_status_dismissal.mjs
```

测试运行生产 QML 呈现及动画组件，覆盖退出快照、动画反向、状态合并、跨屏和空内容。
它不验证 KWin 玻璃渲染。真实 VM 还需验收输入与上屏、快速中英切换、横向及纵向
候选布局、屏幕边缘定位，并使用安装后的 Shell。

专用 `input method motion` 工作流在候选分支运行这些检查；CTest 也将其纳入
logic 和 headless 测试组。

[English](README.md)
