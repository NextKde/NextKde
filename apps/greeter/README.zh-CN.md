# KOS Greeter

基于 greetd、KWin Wayland 和 Quickshell 的独立登录界面，由 greetd/PAM 认证后启动受支持的 Plasma Wayland 会话。安装器不修改 PAM，登录前不执行用户提供的任意主题代码。

- [安装、更新与恢复](INSTALL.zh-CN.md)
- [临时测试及回滚](TEMPORARY-TEST.zh-CN.md)
- [显示配置](../../docs/kos-greeter/contracts/machine-outputs.md)
- [会话交接](../../docs/kos-greeter/contracts/session-handoff.md)
- [可选合成器交接实验](experimental/drm-handoff/README.md)

依赖 Python 3/Pillow、greetd、KWin Wayland、支持 Greetd API 的 Quickshell、Qt Quick Controls 和 Plasma Wayland。运行 `apps/greeter/bin/kos-greeter-session --check` 可只读检查依赖。

登录壁纸使用明确同意后发布的公开副本，永久安装版保留到主动替换或撤销。更换桌面壁纸不会自动发布登录副本：使用 `./tools/install-greeter.sh --refresh-wallpaper` 更新，追加 `--no-wallpaper-sync` 撤销。临时测试副本仍默认限时过期。

加载界面显示与登录界面一致的日期和时间；每输出壁纸与桌面就绪后揭幕。跨合成器黑屏、物理 DRM/VT 连续性和真实 PAM 登录仍需实机验收，隔离测试不代表这些项目通过。

测试入口见 [English README](README.md)。日志、截图和视频默认生成到本地忽略目录 `.build/greeter-tests/`，不提交到仓库；显示策略测试所需的 JSON 夹具保留在 `tests/fixtures/outputs/`。
