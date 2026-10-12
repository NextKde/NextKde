# 证据边界与核查记录

研究日期：2026-10-11，Asia/Shanghai。源码基线：`54512887915152c514b9d08f3a45ca14779e1adc`。

本文件区分项目现状、上游接口事实和未来设计建议。整个任务包是待实现方案，文档生成不表示登录器已经实现、安装或通过硬件验收。

## 已确认的项目事实

| 事实 | 项目证据 | 不应推导出的结论 |
| --- | --- | --- |
| KOS 自己绘制桌面壁纸并保存用户设置 | `shell/desktop/modules/wallpaper/WallpaperService.qml` | Plasma 壁纸配置能代表当前 KOS 壁纸 |
| 当前使用图片模式、裁切、KOS 接管，保存了从上滑入效果 | 本机 `~/.local/state/quickshell/kos/wallpaper.ini` 与用户设置截图 | 文件名含“动态”即正在播放视频 |
| 图片就绪与切换完成按输出收集 | `WallpaperService.qml:230` 与 `:252` | `Image.Ready` 等于屏幕已呈现 |
| 完整 KOS Shell 等待 KWin、平台服务和 plasmashell | `packaging/systemd/kos-shell.service.in` | 完整 Shell 可以自动覆盖新 KWin 第一帧之前的间隙 |
| 当前显示输出约 240 Hz，硬件推荐模式约 60 Hz | 本机 `kscreen-doctor -j` 只读结果 | 推荐模式等于用户选择模式 |
| 旧 SDDM 源码保留，安装入口暂停 | `README.md:195`，提交 `76137dc` | 当初移除的具体根因已经全部证明 |

以上是研究时快照。执行任务前需要重读源码与实际配置，行号、配置和硬件状态可能变化。

## 上游机制

- greetd 在登录会话终止后启动用户会话。见 [greetd 作者手册的发行版镜像](https://manpages.debian.org/unstable/greetd/greetd.1.en.html)。因此不能让登录合成器等待尚未启动的桌面第一帧才退出。
- Quickshell 的退出动画必须在 `Greetd.launch()` 前完成；`launched` 是启动请求被确认。见 [Quickshell 0.3 接口](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/Greetd/)。它不是 Plasma 首帧回调。
- Qt `frameSwapped` 表示帧已排队呈现，不是显示器已经扫描输出。见 [Qt 官方说明](https://doc.qt.io/qt-6/qquickwindow.html#frameSwapped)。
- `ListCachedUsers` 不是全部用户列表，必须保留手输其他用户入口。见 [AccountsService 官方接口](https://cgit.freedesktop.org/accountsservice/tree/data/org.freedesktop.Accounts.xml)。
- 独立 KWin 前后使用相同显示模式有利于减少切换，但不保证设备交接没有黑帧。见 [Linux DRM 官方接口](https://www.kernel.org/doc/html/latest/gpu/drm-uapi.html)。

## 视觉证据边界

- [Apple 官方 Tahoe 图](https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/) 是锁屏宣传图，包含设备外框，不能当作冷启动全部状态或直接测量整图像素。
- [512 Pixels 截图库](https://512pixels.net/projects/aqua-screenshot-library/macos-26-tahoe/) 标注 Login Window 的图可参考多用户构图；其文件名为 Fast User Lockscreen，不证明所有冷启动配置都相同。
- 没有实际观看并核验完整 Tahoe 认证成功至桌面录像。文档中的动画时间、位移、曲线都是建议参数，不能声称原版测量值。
- SVG、HTML 状态图和分镜均为 KOS 实现示意；当前壁纸接管截图是用户提供的现状证据。

## 待实测条件

真实 DRM 交接、多屏、合盖热插拔、240 Hz 与 1.5 缩放、登录前头像可读性、不同 GPU 后端、PAM 多轮提示、失败后恢复、遮盖层超时退出均需独立测试。

不得将嵌套窗口演示、客户端渲染回调、静态截图或文档检查替代上述真实会话验收。测试未执行就记录为“未执行”；可选能力缺失应记录为跳过及原因。
