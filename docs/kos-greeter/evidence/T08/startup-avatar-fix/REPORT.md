# T08 壁纸首显与 KDE 头像回归修复

日期2026-10-11（Asia/Shanghai）；执行者/root；分支codex/notification-center-stacks。状态：独立审查通过。范围仅Greeter源与测试，不部署系统服务、不修改系统权限。

用户反馈：壁纸晚于登录界面出现几秒；头像没有跟KDE。修复依据本机只读检查与实际Qt测试，不把该反馈当完整A15或scanout证据。

## 原因与修复

单账户自动选择会变更WallpaperSource.uid。旧实现reset把默认背景标为ready=true，已有read又阻止立即重读；startupComplete可以提前锁存，先显示默认背景，之后才显示图片。新实现UID切换ready=false；generation丢弃旧UID结果；readerBusy直到旧进程退出才释放，取消旧读取后立即启动当前UID读取。身份列表解析且自动选择完成后才accountsReady=true，首显必须当前身份与背景均就绪。之后切换账户不再次隐藏可用认证窗口；原有3秒读取、3秒解码、7秒首显降级保持。

本机AccountsService返回IconFile=/var/lib/AccountsService/icons/wwt，图片PNG256×256、root所有0644；固定/var/lib/AccountsService及icons目录为root:root0775，旧策略拒绝groupwrite导致默认头像。现仅这两个固定目录允许gid0的groupwrite；其他目录不放宽，仍拒绝符号链接、非root所有、otherwrite。头像文件仍要求root所有、无group/otherwrite、O_NOFOLLOW、有界PNG/JPEG重编码，不读home。未chmod任何目录或文件。实际snapshot已确认UID1000头像解码为有效data URL（只记录布尔结果，未保存用户头像图像）。

## 验证

- accounts.test.py 三项测试通过，包含固定root组775目录正常解码、不可信组775拒绝、777/symlink拒绝及损坏/超像素回退。
- wallpaper-startup.test.py 六项实际Qt测试：延迟图、损坏图、缺背景、Loader错误、延迟单账户返回+自动选择+旧read仍在途，以及独立虚拟KWin16:10/缩放请求回归。首显断言accountsReady、selectedUid及当前资源version，而不是仅检查默认背景resourceSettled。失败保持安全回退。
- wallpaper-freeze.test.py 两项实际QML冻结/解冻回归通过。
- ipc.test.py 十二项实际Quickshell+mock greetd回归通过，保证直接回车登录与认证生命周期未回退。

实际命令输出见accounts.txt、startup.txt、freeze.txt、ipc.txt。当前版本见SHA256SUMS；上级初轮证据和interaction-update为历史快照，不将旧hash或旧测试套用为当前版本。完整A15、真实跨会话呈现仍未测，T08整体阻断不变。

修复后应回滚上一轮临时测试，再从文字TTY重新运行原测试脚本，以复制新的源文件；活动/run快照不热更新。此任务没有主动结束用户桌面或切换管理器。

独立审查记录：../../../reviews/T08-startup-avatar.md。
