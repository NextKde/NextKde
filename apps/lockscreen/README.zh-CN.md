# KOS 锁屏（`apps/lockscreen`）

给 KDE Plasma 的 iPadOS 风格锁屏，由 `kscreenlocker` 渲染——**真会话锁**，不是覆盖层。

与 `apps/` 下其他目录不同，这不是可执行程序，而是一个 Plasma Look-and-Feel
包（KPackage）：它只替换 `kscreenlocker_greet` 所画的 QML。认证、闲置锁定、
睡眠挂钩和所有锁屏入口仍然归 kscreenlocker 管。

## 结构

```
metadata.json                 KPackage 元数据（Plasma/LookAndFeel，id org.kos.desktop）
contents/defaults             继承 Breeze Dark，切换主题不影响桌面其余外观；
                              还把 [Desktop] Containment 钉在纯壁纸的
                              org.kde.desktopcontainment 上，供 plasmashell 读取（见下）
contents/lockscreen/
    LockScreen.qml            greeter 入口（kscreenlocker 契约）＋ 密码输入状态机 + 壁纸接管
    LockClock.qml             超大时钟 + 日期（数字是液态玻璃：取背景那一块做遮罩）
tests/headless/               离屏夹具：断言状态机与壁纸接管，渲染 lock.png
    wallpaper-sample.png      夹具用的高清壁纸样本（真机上是用户自己的壁纸）
```

## greeter 给 QML 注入了什么

kscreenlocker_greet 注入 `authenticator`（PAM 会话：`startAuthenticating()` /
`respond()` / `succeeded` / `failed`）、`wallpaper`（Plasma 壁纸 item）、
`config` 和 `kscreenlocker_*` 全局量；读取根对象的 `viewVisible`，连接
`clearPassword()` / `notificationRepeated()` 信号。这里只能用纯 QtQuick 加这些
注入对象——没有 Quickshell，没有 Kos.Ui。

## 开发循环

```sh
# 让 greeter 看得见这个包（用户级，无需 root）。注意是 plasma/shells/：
# greeter 从 Shell 包结构里取锁屏，look-and-feel/ 对它无效——
# 这两个条件是 tests/theme-resolution 逐一验证过的。
mkdir -p ~/.local/share/plasma/shells
ln -s "$PWD" ~/.local/share/plasma/shells/org.kos.desktop
kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage org.kos.desktop

# 离屏断言 + 渲染预览，不需要真的锁屏：
./tests/headless/run.sh

# 在真 greeter 里预览：
/usr/lib/kscreenlocker_greet --testing
```

每次锁屏都是新起的 greeter 进程，改完 QML 下次锁屏即生效，不用重启 shell 或
合成器。在系统设置「全局主题 → KOS Lock Screen」切换（或改
`kdeglobals [KDE] LookAndFeelPackage`）。

## 输入

只有密码输入框，没有数字键盘：账号密码是任意字符串（字母、标点、空格），
只收数字的界面会把一部分用户锁在门外。回车提交，Esc 清空并让 greeter 丢弃
未完成的密文；「显示密码」切换明文；大写锁定开着时会有提示（复用
`org.kde.plasma.private.keyboardindicator`，与上游默认主题同源）。

## 背景壁纸：为什么要自己再画一遍

greeter 交过来的 `wallpaper` 是壁纸包的根 item。`org.kde.image` 内部用 C++ 的
`TransientImage` 出图，而它的纹理按「加载那一刻 item 的几何尺寸」生成——那个尺寸归
greeter 管，我们只能事后接管。在 HiDPI 屏上（本项目的面板是 3840×2160 @ scale 2）这张
纹理可能停在逻辑尺寸上，于是 1920×1080 的图被拉到 3840×2160 的面板上，表现就是
「壁纸变成了一张很低像素的图」。这些像素已经不存在了：抓 item、动 `layer`、想办法让包
重新解码，最终都还是在采样同一张偏小的纹理。

所以主题不用它的像素：接管 item 后深度优先遍历那棵子树，找到包自己解析出来的静态图片
文件（名字解析、`#dark` 之类都在包内处理完了，读结果比读配置可靠），再用普通 `Image`
配 `sourceSize = 尺寸 × devicePixelRatio` 自己解码一遍，叠在包自己的画面之上。找不到
文件（动图 / 视频壁纸）就什么都不做，退回 greeter 给的那一张。

两个配套细节：遍历要重试（包在我们接管之后才建图，幻灯片还会换文件），5 秒一次；
解出来的 URL 必须是绝对的——相对 URL 是按写出它的文件解析的，那个文件是包不是我们，
照抄会去错路径，所以相对 URL 一律不接管。

**诊断开关**：把 `LockScreen.qml` 顶部的 `debug` 改成 `true`，锁屏左上角会画出屏幕
尺寸 / dpr / root 尺寸 / greeter 给的 item 尺寸与 layer / 遍历结果 / 我们解码的尺寸与
Image 状态。这个主题跑在一个谁也 attach 不上的进程里，这是唯一能看它到底拿到了什么
的办法。

**别用大半径 `FastBlur` 补救**：它按绝对半径挑内部分辨率，radius 64 时约 80% 的输出来自
1/16 与 1/32 的缓冲（1080p 上就是 120×67 和 60×34）——那不是"模糊的壁纸"，是"低分辨率
的图"，只会更像糊。真要更强的模糊就用 `MultiEffect`，别加大 radius。

## 后续

- ~~接入 `tools/kosctl` 部署~~ 已完成：`./tools/kosctl install lockscreen`
  会把包装到 `$prefix/share/plasma/shells/` **和**
  `$prefix/share/plasma/look-and-feel/`（greeter 只搜前者，后者是给
  `plasma-apply-lookandfeel` 和系统设置页的），并把 `plasmashellrc [Shell]
  ShellPackage` 指过来。不带参数的 `./tools/kosctl install` 也会装 shells/ 根
  ——作为桌面接管的 shell 包，但不含锁屏。NixOS（`nix/package.nix`）
  仍未接入——否则 NixOS 装不上（`Kos.SurfaceShape` 踩过同样的坑）。
- 解锁/锁定过渡动画（KWin 侧「吸走窗口」原型在 vendored 特效里做，不在这里）。
