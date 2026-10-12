# 壁纸构图与首显独立复审

日期：2026-10-11 Asia/Shanghai。执行者 /root；审查者 /root/t07_review，只读、未参与实现。分支 codex/notification-center-stacks。范围：证据wallpaper-startup/SHA256SUMS所列文件。

初审P2：缺背景实例/Loader错误可能无限隐藏认证。执行者加入七秒总期限兜底，追加真实Qs缺背景/Loader错误测试。复审关闭P2；独立重跑五项启动测试全部通过，未复现空资源转图片旧settled提前锁存。实际virtual背景全屏/预算检查、主窗口不重复绘图、首次visible资源settled、UID变更不隐藏均通过。20项script和9场景IPC原始证据匹配。

P3：KScreen请求scale1.5缺实际回读和QtDPR=1.5断言。执行者修改报告及使用说明，明确只是请求值，预算按Qt实际DPR检查；不宣称真实分数缩放协商通过。

被审初始摘要8a3215634d0531b6088f7e619b90918502360b884e6b2ea01e33af7164243d0b已归档wallpaper-startup-reviewed-SHA256SUMS。文档边界/状态差量后摘要c360283c6fdc3095016270f0c19df22f00fcb64189fba68ea1693f453c35fef3。代码、测试及原始日志未变；同一独立代理最终差量确认通过，摘要全部校验成功，P3已关闭，无未关闭P0–P3，可完成本次修复。

未测：本机真实显示管理器切换/真实认证、用户物理屏幕显示一致性、scanout及同帧时序。无系统服务或登录配置变更。审查记录不纳入自身摘要以避免自引用。
