# 正式安装与回滚

这两个入口与 `/run` 临时测试分开。本页命令由用户明确要求编写；本轮只进行了源码打包和隔离故障测试，没有实际切换宿主显示管理器。

## 安装

在仓库根目录以自己的普通账户执行，脚本仅在安装阶段调用 sudo：

```sh
./tools/install-greeter.sh --check
./tools/install-greeter.sh
```

默认安装独立 Greeter，备份原配置与 systemd 别名/启用链接，禁用原显示管理器的开机启动并启用发行版 `greetd.service`；当前桌面仍运行，**重启后生效**。本机原管理器为 `plasmalogin.service`，脚本运行时查询，不硬编码成 SDDM，也不卸载 Plasma。认证成功后仍启动既有 Plasma Wayland 会话。

Greeter 是 QML/Python 应用，没有自身 C++ 目标；构建检查 Python 语法、校验可信共享主题哈希并生成有限文件的独立 bundle，再安装到 `/usr/local/lib/kos-greeter/app`。不编译/安装天气、音乐等无关应用，也不自动安装系统依赖。依赖需预先具备：发行版 greetd、greetd PAM、非 root greeter 账户、Quickshell、KWin Wayland、KScreen、Plasma Wayland、systemd/logind、D-Bus、Python/Pillow。不会改写 PAM 或自动加 KWallet hook。

若仍在临时测试中，安装预检会拒绝。先保存工作，从 Ctrl+Alt+F3 的文字 TTY 执行：

```sh
sudo python3 /home/wwt/Downloads/NextKde/tools/rollback-greeter.py
```

恢复原管理器、重新登录后再正式安装，不能叠加临时 runtime mask 与持久配置。

需要立即切换时，保存工作并从**文字 TTY3**执行以下命令；它会结束当前桌面：

```sh
./tools/install-greeter.sh --activate-now
```

默认 Greeter 位于 VT1，文字恢复 TTY 必须不同。图形终端或管道执行立即切换会拒绝。`--files-only` 安装 app/greetd 配置而不改变服务 enablement；这是安装与开机选择分离的可选模式，与 `--activate-now` 互斥。

安装写入系统用户级 `kos-shell.service` 路径 drop-in，让已有 T11 Shell 找到独立安装的 Cover；仅 daemon-reload 当前调用者的用户管理器，不重启 Shell、不导入全局认证/DBus环境。该 drop-in 不包含令牌。Shell 自身需已有 T11 模块，脚本不顺带升级整个桌面；未接入门控的 Shell 仍依靠独立 Cover 超时撤罩。当前共享 Shell 仍不支持同 UID 的并发桌面。

## 更新已安装版本

直接再次运行：

```sh
./tools/install-greeter.sh
```

已有有效安装快照时自动更新，无需先卸载。通过 Linux 原子目录交换替换完整 app，删除旧版源码中已移除的文件；升级失败恢复旧 app，下一次执行自动处理未完成事务。原位升级要求 app 与恢复快照处于同一文件系统，不满足则在替换前拒绝。断电恢复仍未实机验证。

升级保持原开机选择：曾用 `--files-only` 安装的版本不会因默认更新被启用。更新不接受 `--activate-now`；已有持久启用时也不能用 `--files-only` 改成禁用。当前账户公开图按构建时的明确同意刷新，无同意或 `--no-wallpaper-sync` 撤回当前账户副本，其他账户副本保留。同包被跳过时，壁纸续期/撤回仍使用 `--refresh-wallpaper`。

配置/服务链接被管理员修改、快照不完整或回滚未完成时拒绝自动覆盖。自动更新的是 app 源码/资源，沿用既有服务配置与恢复入口；不升级完整 Shell、系统依赖或 PAM，也不更改旧安装的配置契约。

## 回滚

Greeter 正在运行或存在其新登录会话时，从文字 TTY3执行：

```sh
./tools/rollback-installed-greeter.sh
```

源码目录移动或删除后，仍有两个 root 管理的独立恢复入口：

```sh
sudo /usr/local/sbin/kos-greeter-rollback --rollback
sudo python3 /var/lib/kos-greeter-install/rollback.py --rollback
```

`--status` 可从普通终端查看安装快照，不修改服务：

```sh
./tools/rollback-installed-greeter.sh --status
```

回滚停止已装 greetd，清理本次新增的 greetd/logind 会话（保留安装前同一 boot 的会话及其他非 greetd 会话），恢复原 greetd 配置、原 drop-in/恢复入口、systemd 开机链接和必要的 getty 状态，重新启动原管理器并核验 active，再删除已装 app、公开壁纸副本及私有快照。重复回滚无害；不能恢复已经退出的窗口或未保存数据。

快照位于 `/var/lib/kos-greeter-install`，0700；配置备份为0600，保存之前不修改服务或配置。相同 bundle 重复安装跳过；检测到不同 bundle 会自动原位更新为当前本地源码，不自动拉取远程源码。升级保留首次安装的原管理器备份、服务启用状态和会话清理基线，不重启 greetd/当前桌面，新版在下一次登录使用。回滚检测到管理员后来修改了管理配置/别名时拒绝覆盖；服务恢复失败保留快照和 app，修正原因后可重试。不要在安装/回滚中手动编辑相关 unit/config。

greetd **daemon 服务失败**时 `kos-greeter-recover.service` 调用同一恢复代码；`Restart=no` 避免 daemon 无限重启。该机制不检测“daemon仍运行但图形界面无法操作”，也不保证硬件故障或断电恢复；这些仍需真实登录验证。

## 壁纸公开副本

默认构建仅读取调用账户已有的明确同步同意及 KOS 当前静态选图；无同意不发布。该图在认证前向其他使用者可见，登录前只读取 root 管理副本，不打开 home。图片经过有限大小校验与去元数据，副本放在独立 app/public-display，回滚一起删除。`--no-wallpaper-sync` 可在安装时跳过公开图。

副本沿用 T03 的**24 小时有效期**，不会永久显示过期/撤销版本，过期使用内置背景。目前没有自动刷新服务，改变选图或在到期前使用：

```sh
./tools/install-greeter.sh --refresh-wallpaper
```

它重新读取当前账户的同意与选图，不重新启用管理器；同意已撤销时清理该账户旧 manifest/版本。也可直接撤回已装公开副本：

```sh
./tools/install-greeter.sh --refresh-wallpaper --no-wallpaper-sync
```

这条命令撤回当前已装副本，不改变你桌面的原图或本地偏好。其他账户副本保留；刷新后如在登录中版本变化，旧版本消费者按既有契约降级，不冒充逐帧连续。

## 验证边界

打包、语法、文件系统事务及模拟 systemd/logind 故障测试已执行，初次安装独立审查记录见 `../../docs/kos-greeter/reviews/persistent-install.md`；自动更新的35项隔离验证与独立审查见 [更新证据](../../docs/kos-greeter/evidence/automatic-upgrade/REPORT.md)和[更新审查](../../docs/kos-greeter/reviews/automatic-upgrade.md)。未实际安装、重启、测试物理 TTY/PAM 或开机登录；不把模拟测试当作完整 T14/A19 系统集成验收。

## 密码框玻璃与 KWallet 自动解锁修复（2026-10-12）

密码框采样其所在窗口的同源静态壁纸，保留高斯模糊、圆角和高光；移除双重蓝色染色并减弱焦点边框。软件渲染或效果模块不可用时仍使用可读的回退底色。隔离渲染已验证实际 WallpaperHost、data URL 和真实 shell 中的采样，实机观感仍须更新后确认。

本机日志显示 `pam_kwallet5(greetd:session): not a graphical session, skipping`。greetd 的 PAM 会话早于 Plasma 图形会话，已有 `auto_start` 并不足够。独立修复脚本为 optional auth/session 钩子补充 `force_run`（KDE 模块在 auth 阶段解析参数），保留原配置并生成 root 专属备份，不保存或接收密码。安装器仍不自动改写 PAM。

在本仓库普通终端执行：

```sh
./tools/install-greeter.sh
sudo python3 tools/fix-greetd-kwallet.py
```

更新不会重启当前桌面。退出后重新用账户密码登录，检查密码框是否透出当前壁纸，并打开 Chrome 验证钱包是否自动解锁。钱包密码须与账户登录密码一致；本轮未访问钱包内容，也未执行真实认证测试。

PAM 备份路径由脚本输出，位于 `/var/backups/kos-greeter/greetd-pam-*`。需要撤回时用 `sudo cp -p` 将该次备份恢复至 `/etc/pam.d/greetd`；Greeter app 回滚不自动撤销这次独立 PAM 修复。
