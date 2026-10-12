# 启动蓝底回归修复

2026-10-12，分支 `codex/notification-center-stacks`。用户报告每次启动短暂蓝底。

原因：WallpaperWindows 与 Cover 在源读取/图片解码前立即映射窗口，WallpaperHost 此时只能绘制固定蓝色回退底。认证 UI 的启动门槛未覆盖独立背景窗口。

修复：背景源决定并且宿主图片解码就绪后才进行首次映射；图片在隐藏窗口中按固定screen解码尺寸/DPR预加载，首次映射通过Qt.callLater避免绑定重入；新增测试拒绝Binding loop日志。WallpaperWindows sourceReady显式接入wallpaperSource.ready，认证入口还要求账户选择完成。首次映射后锁存，不随周期资源重读反复隐藏窗口。Cover feed未返回时不显示预设默认底；feed退出/非法或2秒卡住仍决定固定回退，解码失败/3秒期限和Cover15秒撤罩保持。

测试：

- `startup-background.test.py` 在真实虚拟KWin双输出1024×768运行生产组件。延迟1.2秒提供图片，0.7秒前没有提交帧；两个输出的首个提交回调触发的异步宿主抓图均为目标像素(179,101,42)，非蓝。Cover读取卡住时2秒决定回退，两个输出首帧是固定回退像素(22,40,59)。图片和日志在本目录。卡住feed的回退耗时断言1.8到4秒。
- `wallpaper-startup.test.py` 六项通过，含延迟读取、损坏图片、缺背景/loader错误期限及1536×960、scale1.5虚拟KWin认证/背景门槛。
- `entry-virtual.test.py` 七项通过，含默认、迟到Cover、组件延迟、丢失就绪及hash失配恢复。
- `cover.test.py` 原Cover九条PASS记录及双屏资源截图回归通过。
- `entry-protocol.test.cjs` 旧/重复协议事件及同图选择回归通过。

抓图由壁纸宿主的首个 frameSubmitted 回调触发，但 grabToImage 异步完成；只核验资源门槛和提交后的背景像素，不证明 compositor 首个缓冲区像素，非物理屏幕录像或scanout，不宣称跨KWin零黑帧。测试finally清理隔离进程组，未部署、切换登录管理器或重启用户桌面。用户“正常打开”记录为本轮反馈，不补写缺失的完整A03/A10冷热录像。

独立只读审查代理 `/root/review_startup_background`；审查结论见 `../../../reviews/T11-startup-background.md`，被审文件摘要见 `SHA256SUMS`。
