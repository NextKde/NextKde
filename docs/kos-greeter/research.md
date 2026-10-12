# 研究报告

## 证据分级与范围

研究日期 2026-10-11，代码基线 `54512887915152c514b9d08f3a45ca14779e1adc`。这里整理既有只读调查结论；本次文档创建没有重新运行真实登录或 modeset。机器状态是该次调查的快照，实施时必须复核。代码定位行号会随后续提交变化。

“已观察”指源码或本机调查得到的事实；“建议”是架构选择；“待验证”不得作为已实现能力。当前没有冷启动端到端录屏证据。

## 项目现状（已观察）

- 旧 SDDM 主题仍在 `apps/sddm/Main.qml`；提交 `76137dc` 暂停安装/卸载入口，不能称源码已删除。`README.md:195` 说明集成暂停。旧界面有时钟、用户、密码和会话选择，但不是 Tahoe 的底部用户布局。
- `shell/desktop/modules/wallpaper/WallpaperService.qml:16` 管理壁纸配置，配置路径为 `~/.local/state/quickshell/kos/wallpaper.ini`。现有调查记录：`mode=image`、`takeoverEnabled=true`、`fitMode=crop`、`transition=top`；图片是 `~/.local/share/kos/gallery/V2.0 Asuka 明日香 高清 动态壁纸.png`。保留的 `themeId=blackhole` 不能覆盖实际 image 模式判断。
- 用户提供的设置截图明确开启“由 KOS 显示壁纸”。可见背景以 KOS 管线为权威；Plasma 可能保留占位图，不能反推当前 KOS 壁纸。文件名含“动态”不代表当前 PNG 通过动态渲染入口播放。
- `shared/qml/wallpapers/ThemeWallpaperScene.qml:9` 是可研究的参数化场景边界；不要把整个桌面 Shell 当登录前依赖。
- `apps/lockscreen/contents/lockscreen/LockScreen.qml:304` 使用锁屏宿主注入的壁纸，尚未直接统一到 KOS 自绘管线。登录与锁屏可以共享视觉契约，但认证生命周期不同。
- `packaging/systemd/kos-shell.service.in:3` 的现有启动依赖包含平台、KWin 和 plasmashell，完整 Shell 不适合作为用户 KWin 后第一块背景。
- `WallpaperService.qml:230` 附近收集壁纸就绪；图片解码、主题 frameReady、过渡结束都不等价于显示器已 scanout。
- `platform/src/daemon/PlatformServer.cpp:1759` 附近解析输出，现有提取未覆盖完整模式、缩放、VRR，不能直接作为完整显示同步契约。
- 本机调查输出：eDP-2，2560×1600，239.998 Hz，scale 1.5，VRR Never，HDR off；推荐模式约 59.999 Hz。KSplash 配置为 Engine=none、Theme=None。不得假设登录前自动使用 240 Hz 或 KSplash 自动接住 KOS。

## 认证与生命周期（官方依据）

Quickshell 0.3 的 [Greetd 接口](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/Greetd/) 提供认证与会话启动能力。ReadyToLaunch 是认证结束并可提交启动请求；launched 是请求确认，不是桌面首帧。退场动画须在 launch 之前完成，提交启动后 Greeter 应尽快退出。

[greetd 手册](https://manpages.debian.org/unstable/greetd/greetd.1.en.html)描述登录会话与用户会话的交替。不能让 Greeter 等待桌面就绪才退出，否则会阻塞用户会话启动。版本行为需在 T01 固定并实测。

[KWin 源码](https://github.com/KDE/kwin/blob/master/src/main_wayland.cpp)提供 `--exit-with-session` 生命周期入口；这不是跨合成器帧保留协议。普通 QML 无法承诺 DRM 释放和新 KWin 接管之间无黑帧，参见 [DRM 用户接口](https://www.kernel.org/doc/html/latest/gpu/drm-uapi.html)。

[Qt frameSwapped](https://doc.qt.io/qt-6/qquickwindow.html#frameSwapped)表示帧已排队呈现，不能直接证明 scanout；严格计时应使用 [Wayland presentation-time](https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/main/stable/presentation-time/presentation-time.xml) 或外部高帧率录像。

## 推荐结构与交接流程（建议）

1. greetd 管认证和会话切换；独立 KWin 托管 Quickshell 登录 UI。
2. 桌面侧发布有限展示 manifest 与资源副本，登录前读取系统范围、只读的展示快照。
3. 认证成功后清空密码并禁输入，180–280 ms 淡出头像、表单和时钟，恢复纯背景；该时长是建议，不是 Tahoe 实测。
4. 最后一帧不保留模糊、暗罩或不同裁切。确认帧已提交，再调用 launch，并退出 Greeter/登录 KWin。
5. 新用户 KWin socket 可用后，独立轻量 Cover 尽早绘制同一背景；它与 Plasma/KOS 并行，不等待 platform/data。
6. 正式壁纸窗口、输出与必要顶部栏/Dock 就绪后统一揭幕。登录这一次抑制 `top` 日常壁纸切换；天气等非必要数据无需阻塞。
7. Cover 无法覆盖新 KWin 接管以前的空白；跨实例黑帧必须另列性能研发与证据。

静态图应同原图、同填充、同 crop、同 scale 重绘。时间驱动主题可携带 phase；粒子/流体 GPU 状态不能仅靠 phase 复现，宜用壁纸专用静态帧过渡。空间壁纸使用预生成素材和中性视角，禁止登录时推理。不得截取含密码或用户窗口的整屏帧。

## 身份与显示（建议）

使用 system bus AccountsService 的 UserName 认证、RealName 展示、IconFile 头像和 UID 关联。[AccountsService 接口](https://cgit.freedesktop.org/accountsservice/tree/data/org.freedesktop.Accounts.xml) 的缓存列表不涵盖所有可登录账户，保留“其他用户”。头像 home 不可读时使用已处理副本或默认头像，不能放宽家目录权限。greetd/PAM 处理密码与认证提示。

显示参数先采用机器级默认。选择头像不得立即触发 modeset；显示器变更、合盖、多屏与未知 EDID 要有安全回退。保存精确 Hz 或模式标识，不能把 239.998 简化后盲配 240。登录与桌面尽量一致，但仍需实测链路是否重新训练。

交接描述经会话 wrapper 校验后写入该用户该会话 `XDG_RUNTIME_DIR`，0600，按 session 隔离；它只携带展示状态，不携密码，不全局 import systemd/dbus token，不直连用户 0600 platform socket。

## 待验证与阻断项

- 固定 greetd/Quickshell/KWin 版本后验证权限、VT/seat、进程退出和真实 Plasma 会话交接。
- 完整冷启动登录、密码展开、失败、多用户切换的 Tahoe 参考尚未收集齐；现有图不能支持完整 1:1 宣称。
- 图片发布权限、AccountsService 本机字段、头像读取与缓存更新需要核验。
- 新 KWin 最早窗口时机、Cover 层级、系统快捷键可用性、崩溃撤罩和启动超时需要原型。
- 外屏断开、合盖、GPU 驱动与 240 Hz 切换造成的空白时长需要视频证据。

## 实施门槛

先完成只读事实审计，再在隔离环境验证最小登录和退出；确认恢复路径后才允许评审系统集成方案。本任务包没有授权直接替换本机显示管理器。

## 补充：项目 app 定位

用户明确要求作为本项目独立 app，并有自己的安装命令。已核对 apps/README.zh-CN.md 的 shared 复用、独立进程和禁止导入 shell/desktop 约定，以及现有 kosctl install apps 入口。Greeter 的系统会话部署与普通用户级 app 有不同运行边界，详见 [App 安装方案](app-packaging.md)。
