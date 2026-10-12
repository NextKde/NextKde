# 前接管画面保留：三环诊断与最小原型

日期：2026-10-12。这是可审核的研究/离线诊断产物，未编译或安装自定义 KWin，未修改 PAM、logind/greetd、真实 VT/模式或会话。CPU 优化能缩短空档，但不能在不存在可绘制 compositor 的阶段显示 QML spinner。

## 本机边界与证据

主代理只读证据：KWin 6.7.5、systemd 262；NVIDIA RTX4070（PCI01:00.0）通过 card2 驱动活动 eDP-2，AMD eDP-1 断开；nvidia-utils 与 nvidia-open-dkms 均为 615.78.08。fbcon 日志将 nvidia-drmdrmfb 设为 primary。必须在该双 GPU/NVIDIA 组合验证，不能把其他驱动成功当本机实证。

真实登录事件：旧 WallpaperDestroyed16.158、旧 KWin 退出诊断16.263；内核 DRM 事件17.702–17.772；新 KWin19.904 开始 DRM、另一组 DRM 事件21.651，Cover SocketConnected21.692。这只能关联阶段，既没有原子属性快照，也没有屏幕呈现证据，不能由日志宣称“哪个 commit 导致黑屏”。

## 1. 旧 KWin 输出清理/CloseFB

已核对固定 upstream v6.7.5：[drm_gpu.cpp](https://raw.githubusercontent.com/KDE/kwin/v6.7.5/src/backends/drm/drm_gpu.cpp)、[drm_buffer.cpp](https://raw.githubusercontent.com/KDE/kwin/v6.7.5/src/backends/drm/drm_buffer.cpp)、[main_wayland.cpp](https://raw.githubusercontent.com/KDE/kwin/v6.7.5/src/main_wayland.cpp)。原始源码 URL/SHA256 见 kwin-source-reference.json。

DrmGpu 析构会 removeOutputs；removeOutput 设置 m_forceModeset，并在最后 pipeline 移除时调用 maybeModeset；该路径安排 0ms timer，doModeset 在空 pipelines 且 force=true 时向 unused objects 发 CommitModeset 禁用请求。**这是可能清除 scanout 的路径，不等于每次析构都必然执行该 timer/commit**。需要确认实际次序、返回结果及 ACTIVE/CRTC/FB_ID；正常拔线时这些清理有必要，不能全局跳过。

DrmFramebufferData 析构已经使用 drmModeCloseFB，失败才回退 RmFB。[DRM UAPI](https://dri.freedesktop.org/docs/drm/gpu/drm-uapi.html#drm-ioctl-mode-closefb)描述的持帧作用不会阻止后续禁用输出/换 FB，也不能保证 NVIDIA 在内核/GBM 生命周期结束后保持相同画面。再加一次 CloseFB 无效。

最小行为原型设计：在 ApplicationWayland 增加仅实验 Greeter 模式的 **显式已授权正常交接状态**；由私有控制通道绑定实际 Greeter UI 子进程，认证成功、背景终帧已提交、随后该子进程 normal exit=0 三条件共同置位。不得仅依据环境变量/所有 code=0 退出/所有析构判定。DrmGpu 仅该状态的析构路径可停止 pending cleanup timer、抑制最后 unused-object disable commit、保留正常 CloseFB；热拔线、GPU移除、异常退出、注销、崩溃及恢复路径保持现状。需要同时确认 output->removePipeline/commit-thread 清理没有其他禁用提交、wait/readability 生命周期完整、CloseFB 成功；这个设计尚非可部署 patch。

## 2. logind 控制权释放与 fbcon

KWin LogindSession 在析构 ReleaseControl、设备关闭时 ReleaseDevice。[session_logind.cpp](https://raw.githubusercontent.com/KDE/kwin/v6.7.5/src/core/session_logind.cpp)。本机对应的 [systemd v262 logind-session.c](https://raw.githubusercontent.com/systemd/systemd/v262/src/login/logind-session.c) 在 session_drop_controller 调用 session_restore_vt；后者调用 [terminal-util.c 的 vt_restore](https://raw.githubusercontent.com/systemd/systemd/v262/src/basic/terminal-util.c)，包含 KDSETMODE(KD_TEXT) 和 VT_AUTO。新控制器准备 VT 则设置 KD_GRAPHICS。这是明确存在的文本控制台接管路径；当前清屏让文本缓存为空，所以即使没有“代码”，fbcon 仍可能显示黑色。

因此，仅 KWin stop-cleanup 不能保证持帧。先观察旧控制器消失、VT恢复、fbcon更新与新控制器TakeControl之间是否发生实际覆盖。若确认 KD_TEXT/fbcon 覆盖是主因，下一最小原型需要 **greetd/logind 的同 seat、同 VT、有界交接协调**：只在认证已成功且新用户会话已准备创建时保留 graphics 交接状态，到新控制器接手解除；超时/取消/用户会话立即失败必须恢复KD_TEXT和原显示管理器/TTY。系统目前没有已验证可直接启用的“保留该帧”app选项，不能用全局禁止KD_TEXT、禁用fbcon、持有DRM master不释放、chmod设备或延迟Greeter launch替代。该环若需修改logind/greetd，属于额外系统级范围，须在VM先实现/演练，不能默默包含在普通Greeter安装。

## 3. 新 KWin 第一帧

即便旧帧留住，新 KWin 正常 compositor 的第一次空场景/背景 commit 仍可能覆盖它。SocketConnected只是协议响应，不是背景第一帧。应记录新 KWin first page-flip 与 Cover第一 buffer commit、配置/模式提交的次序。

候选最小原型：用户 KWin 用显式有限 handoff 模式启动，保持继承的可用 CRTC/plane 模式，在收到当前会话可信 Cover 的首批全输出 buffer 前不提交空场景；输出发现/Wayland dispatch仍运行，让Cover可以configure/提交。首批buffer就绪后以一次合法atomic commit替换旧帧；超时、输出变更或不兼容模式恢复正常启动。实施位置涉及 compositor启动/presentation 与 DrmGpu/DrmPipeline 首次commit，不应仅在 Python socket等待中延时。识别namespace不构成权限凭据，需绑定当前会话/控制通道；多屏、NVIDIA/AMD跨GPU及必要modeset失败须有回退。另一候选是新 KWin 自己的可信静态 bootstrap 背景，但同样需要在首个scene呈现前准备，不能先清空再绘图。

## 当前可审核诊断与下一步次序

无需替换二进制的已有观察：限定 `QT_LOGGING_RULES=kwin_wayland_drm.debug=true`（[类别定义](https://raw.githubusercontent.com/KDE/kwin/v6.7.5/src/backends/drm/drm_logging.cpp)）可记录GPU发现、输出移除、DRM openRestricted EBusy重试等。只给实验 KWin，不给整个认证/UI打开debug。它不能可靠给出每个atomic请求属性/cleanup返回结果、KD_TEXT实际fbcon画面或新KWin第一帧内容；本轮没有启动该诊断会话。

离线 `kwin-v6.7.5-trace-only.patch` 对四个原始文件增加固定、env opt-in 的单调时钟事件：SessionChildExited/ApplicationDestroy、GpuDestroy/OutputRemoval、ModesetBegin/LastOutputDisableCommitReturned、CloseFB失败回退、ReleaseDevice/ReleaseControl、FirstPageFlipAnyOutput。默认不开启，不改变cleanup/DRM/VT行为、不记录像素/凭据；FirstPageFlip只记录进程内第一个任意输出回调，不代表每屏内容。已 `git apply --check` 通过，**未编译，不能声称可运行/ABI验收**。事件“Returned”也不证明commit成功，应结合专门属性/返回码观测或VM ioctl trace。patch 源码是GPL-2.0-or-later所需修改片段，原文件版权保留。

执行顺序：先部署本批app CPU降时（审查后独立更新，不改KWin）；下一次授权的真实登录同时采集新固定阶段事件、限定DRM debug及外部高帧率录像，区分frame提交与屏幕黑帧；只有现有日志仍无法区分三环时，再在VM编译/运行trace-only版本和相同版本systemd的受控VT观测。根据确认的覆盖点，分别实现上述行为原型，逐环验证，不一次改三层猜原因。

实验部署/恢复前置：一次性VM快照、原KWin包/显示管理器配置副本、可用不同恢复TTY；自定义KWin先装VM的独立前缀（例如/opt/kos-kwin-handoff-test），Greeter实验入口显式指定它，不替换/usr/bin/kwin_wayland或普通桌面service；恢复为去掉实验入口/标志、恢复VM原包/快照，确认原登录可用。生产二进制/系统协调任何部署都需要用户明确许可和一次会话中断，当前尚未执行。

Greeter HOME=/ 的shader/sycoca缓存报错另有启动成本，可用Greeter专属、UID拥有0700的runtime缓存/config目录优化登录前初始化；本轮不将它冒充登录后空档原因，也未修改实际HOME/缓存。
