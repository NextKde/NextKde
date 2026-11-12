# KOS 锁屏

MacLock 风格的 KDE Plasma 原生锁屏。`kscreenlocker_greet` 负责会话锁定和 PAM 认证；本包只绘制界面，不启动 Quickshell 锁屏，也不接管快捷键或睡眠策略。SDDM 登录屏不受此次改动影响。

## 外观和运行边界

- 顶部日期与时钟，下方中央为紧凑媒体卡、头像、用户名和密码胶囊。
- 图片按屏幕物理分辨率解码；GPU 使用 `MultiEffect` 轻度模糊及采样壁纸的玻璃卡片。玻璃不采样密码或锁屏后的桌面窗口。
- 软件渲染保留清晰壁纸、普通文字和半透明卡片。特效、头像、媒体、通知通过独立 Loader 加载，失败不能阻断密码输入。
- MPRIS 播放控制与已有歌词元数据；歌词默认收起。只使用本地/内嵌封面，不联网搜索歌词或视频。
- 通知默认关闭，启用后仅显示应用名、图标和时间，不显示正文、不提供应用操作。窄屏优先保证时钟和密码区不重叠。
- 回车和箭头在 PAM 密码提示就绪后只提交一次；异步等待期间保留输入，Esc 或 greeter 清空会取消待提交请求。未就绪请求 10 秒后过期，不会稍后重放密码。
- 任意字符密码、Caps Lock 提示、失败等待和唤醒重试均保留；遵守实际 PAM 密码延迟。非交互认证仅因用户活动重试，不在后台循环开启摄像头。

## 设置与部署

KOS 设置 → **锁屏**（`kos-settings --page=lockscreen`）：

- KOS（MacLock 风格）/系统默认锁屏。
- 独立锁屏图片、现有图库、本地文件和不锁定会话的静态预览。
- 媒体控制、隐私通知开关，以及需要明确点击的“立即锁屏”。

锁屏壁纸写入 `kscreenlockerrc [Greeter][Wallpaper][org.kde.image][General]`，不调用桌面壁纸 IPC。外观项由 `contents/lockscreen/config.xml` 声明，KScreenLocker 加载到 `[Greeter][LnF][General]`。只修改这些外观键，保留 `[Daemon]` 自动锁定设置及未知项。

**不要通过全局主题或修改 ShellPackage 来切换锁屏外观。** KDE 从 `plasma/shells/org.kos.desktop/contents/lockscreen/LockScreen.qml` 加载皮肤，根级 `X-Plasma-APIVersion` 必须为 `2`；撤下锁屏目录会回退系统主题，但桌面包仍保留。

Settings 与 `kosctl` 共用 `LockScreenSettings` 生命周期：稳定资源位于 `$prefix/share/kos/lockscreen`，同文件系统 staging、写入锁、自有标记和原子交换防止半复制入口。GUI 不改变 `ShellPackage`，不覆盖未知皮肤或沿符号链接写入。核心升级保留启用状态。

从仓库根目录执行显式安装：

```bash
./tools/kosctl install lockscreen
```

恢复系统锁屏：

```bash
./tools/kosctl uninstall lockscreen
```

独立 CLI 安装保留原有 ShellPackage 备份/恢复语义；如果尚无当前版本 Settings 后端，先构建。每次锁屏启动新的 greeter，已部署 QML 下次锁屏生效。Nix 实机部署未验证。

## 通知桥

现有桌面通知服务通过 `lockscreen.notifications-publish` 向平台进程发布内存摘要。平台只读导出：

- 服务 `org.kos.LockScreen`
- 对象 `/org/kos/LockScreen`
- 接口 `org.kos.LockScreen1`，属性 `NotificationsJson`

不抢占 `org.freedesktop.Notifications`。最多四条；正文始终为空，阻止来源、关闭历史或勿扰时隐藏。发布者断开或 30 秒租约过期后清空，不读取磁盘通知历史。详见 `shared/contracts/platform.v1.md`。

## 验证与安全预览

以下从仓库根目录运行，不锁定真实会话：

```bash
bash apps/lockscreen/tests/headless/run.sh
```

```bash
dbus-run-session -- env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input apps/lockscreen/tests/preview/tst_layout.qml
```

交互预览使用假的认证器、媒体和通知，约两秒后保存图片并退出：

```bash
dbus-run-session -- env QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl qml6 apps/lockscreen/tests/preview/Preview.qml -- --wallpaper /绝对路径/壁纸.png --output /tmp/kos-lockscreen-preview.png
```

`tests/preview/tst_layout.qml` 覆盖宽屏、小屏、竖屏、窄屏、隐藏媒体和通知、非法通知数据、日期时钟，以及 greeter 加载后再次 reparent 时的自动壁纸重接管。认证、媒体选择和主题解析原有测试继续保留。

通知端到端测试会在临时目录原样复制生产 `LockNotifications.qml` 及其玻璃依赖，用私有 D-Bus 和真实平台桥验证模型与实际卡片标签，包括已有/晚启动服务、四条替换、清空、发布者断开和服务消失/重启：

```bash
cmake -S tests/lockscreen-notifications -B .build/lockscreen-notifications-tests
```

```bash
cmake --build .build/lockscreen-notifications-tests -j 4
```

```bash
ctest --test-dir .build/lockscreen-notifications-tests --output-on-failure
```

真实密码认证、多显示器热插拔、睡眠唤醒仍需在可恢复的测试会话中验收。

## 着色器与许可

`LockGlass.qml` 和 `liquidglass.frag` 改编自 MacShell/MacLock（Rickky，MIT），许可随 `LICENSE.MacShell` 分发。未复制第三方字体、截图壁纸或专辑素材。旧 `LockClock.qml` 与 SDDM 的对应文件保留不变，新锁屏使用 `MacLockClock.qml`。

修改 shader 后重编随包发布的 QSB（不要在 greeter 内编译）：

```bash
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o apps/lockscreen/contents/lockscreen/liquidglass.frag.qsb apps/lockscreen/contents/lockscreen/liquidglass.frag
```
