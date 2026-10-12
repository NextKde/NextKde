# 临时切换与完整回滚

这两个脚本由用户明确要求编写；本次没有实际切换宿主服务。T02/T05 的真实 PAM、显示、会话退出与恢复验收仍未测。默认管理器目前是 plasmalogin.service，脚本会运行时查询，不硬编码此名称。

只读预检（可以在桌面终端执行）：

```sh
cd /home/wwt/Downloads/NextKde
python3 tools/test-greeter.py --check
```

保存所有工作，然后按 Ctrl+Alt+F3，登录文字 TTY，执行：

```sh
cd /home/wwt/Downloads/NextKde
sudo python3 tools/test-greeter.py --start --timeout 600
```

sudo 启用 use_pty 时，会将 stdin 包装为 /dev/pts/N；脚本识别 sudo 提供的 SUDO_TTY 原始文字终端，因此在 tty3 上可直接使用上述命令，无需更改 sudo 配置。图形终端及管道输入仍拒绝。

当前桌面会被结束。测试登录在 VT1，Ctrl+Alt+F3 返回保留的恢复 TTY。支持 `--vt 1..12`，必须与执行脚本的 TTY 不同；支持 `--timeout 60..1800` 秒，或用 `--timeout 0`（等价 `--no-auto-rollback`）关闭自动回滚，让测试一直保持到手动回滚或重启。脚本拒绝图形终端、管道输入、现有 greetd、残留测试快照、占用的测试单元及不能安全 runtime mask 的默认管理器。缺依赖只报错，不安装软件或创建账户。必须已有发行版 greetd/PAM、非 root 的 greeter 账户、Quickshell/KWin/Plasma，以及 Python、systemd、loginctl、busctl、dbus-run-session。

启动前写入 root 私有恢复快照，复制有限 app 文件到 /run 的 root 管理目录；不从普通用户可写源码路径运行登录前代码。独立 systemd 切换进程停用默认管理器并 runtime mask，启动 kos-greeter-test.service。它不更改开机 enable 状态或 display-manager 别名，不编辑 /etc/greetd/config.toml、PAM 或 home 权限，不执行 install apps。独立 D-Bus 会话托管登录 KWin；不导入用户桌面 bus。使用专属临时 greetd 配置，禁止认证前 profile 脚本。

启动前已安排自动回滚计时器，默认 10 分钟，从计时器启动开始计时。即使成功登录测试桌面也会到时结束该测试会话，恢复原登录界面；不要在测试桌面做未保存工作。服务启动失败触发恢复。自动恢复等待切换锁，最多三次尝试；故障持续时保留恢复文件并在日志中报错，需要 TTY 手动重试。关闭自动回滚（`--timeout 0`）时不写计时器和失败守卫单元，测试不会自动结束，只能手动回滚或重启；脚本会在启动前打印警告，`--check` 与 `--status` 显示 disabled。系统完全卡死或硬件故障无法由脚本保证恢复。重启会清除 /run 的临时服务与 runtime mask，开机仍按原持久配置启动，关闭自动回滚时这也是保底恢复手段。

手动完整回滚（从恢复 TTY）：

```sh
sudo python3 /home/wwt/Downloads/NextKde/tools/rollback-greeter.py
```

若源码目录移动或损坏，测试期间还有 root 管理的独立副本：

```sh
sudo python3 /run/kos-greeter-test/private/rollback-greeter.py
```

只读查看测试状态：

```sh
sudo python3 /home/wwt/Downloads/NextKde/tools/rollback-greeter.py --status
```

完整回滚范围：停止临时 greetd；终止测试新增的 greetd/logind 会话，保留测试前会话及其他新增的非 greetd 会话；移除脚本创建的 runtime mask；启动原管理器并核验 active 和原 enable 状态；必要时恢复原本 active 的测试 VT getty；停止计时器、移除临时单元、app、副本、配置和协调锁。重复回滚无害。原 greetd 服务和持久配置未修改，无需重写。遇到外部管理员并发修改或恢复失败时拒绝覆盖并保留快照，修正原因后重试。

“完整”指恢复本次脚本改变的服务状态与文件；不能重新创建已退出的桌面窗口、进程或未保存内容。回滚会回到原登录界面，需要重新登录。不要在测试期间另行编辑相关临时 unit 或切换显示管理器，否则原快照不能代表最新意图。

诊断只查看控制服务日志，不打开认证协议 debug 或采集密码画面：

```sh
sudo journalctl -u kos-greeter-switch.service -u kos-greeter-rollback.service -b --no-pager
```

验收记录见 docs/kos-greeter/evidence/temporary-switch/REPORT.md；模拟故障测试不是实际服务切换或恢复通过证据。

## T07 壁纸测试

脚本现已复制 T07 的宿主、消费 helper、主题校验清单及完整可信共享 QML/图片/shader bundle 到 `/run/kos-greeter-test/app`。共享源码的仓库链接会被解析后复制为普通文件，运行时不再访问源码目录。主题文件哈希不匹配或缺失会在切换前拒绝。

需要临时覆盖 KOS 选图、显示另一个指定文件时，先检查：

```sh
python3 tools/test-greeter.py --check --wallpaper "/绝对路径/壁纸.png"
```

再从恢复文字 TTY 执行：

```sh
sudo python3 tools/test-greeter.py --start --timeout 600 --wallpaper "/绝对路径/壁纸.png"
```

`--wallpaper` 明确选择将此图在本次测试的认证前向所有用户展示；用户选择列表和其他账户认证时都能看到它。仅接受有界静态 PNG/JPEG，拒绝损坏图、链接及超预算内容；sudo 读取时使用调用者 UID/主组（不继承附加组），不会利用 root 权限读取调用者不可读的源文件。Pillow 用于规范化重编码去除元数据，副本以 root 管理的 0644 文件保存在临时 app/config 内。只替换临时复制的认证界面资源状态，仓库认证/壁纸代码与持久公开资源目录不变。

未传 `--wallpaper` 时现在默认使用调用账户已授权的 KOS 当前选图，具体自动链路见下节；未经授权的账户仍使用默认背景。回滚删除临时图片和整个 app 副本，不留下持久发布。此参数用于临时预览，不声称完成 T14 的账户公开发布部署或实机验收。

脚本更新的隔离复制、实际 offscreen Quickshell 加载与模拟回滚验证见 `docs/kos-greeter/evidence/temporary-switch/T07-update/REPORT.md`。没有在本次更新中启动真实切换。

## 自动使用 KOS 当前壁纸

本次用户明确要求自己的 KOS 选图同步到登录背景，已为 UID1000 在 `~/.local/state/quickshell/kos/greeter-display.json` 保存 0600 的明确展示选择与认证前公开说明。不会据桌面选图自动为其他账户授权：每个账户须有其自己所有、私有权限、UID匹配的明确选择文件，未授权则不发布。

以后正常命令无需传图片路径：

```sh
python3 tools/test-greeter.py --check
# 从恢复文字 TTY：
sudo python3 tools/test-greeter.py --start --timeout 600
```

脚本先以 sudo 调用者身份读取 `XDG_STATE_HOME/quickshell/kos/wallpaper.ini`（默认该账户 `~/.local/state`）中的 Wallpaper.mode/image/fitMode/takeoverEnabled；当前 image 非空时它就是 WallpaperService 权威来源，轮播 chooseImage 也会更新此值。保留 crop/fit/stretch/center，不读取 Plasma 占位。主题模式、KOS接管关闭、空路径或源图错误会在切换前明确拒绝，不能声称等于当前画面；动态/空间快照仍属后续范围。

源文件读取和重编码在调用账户的子进程中，root 只接收有限规范化PNG字节；T03 Store 原子发布到临时 app/public-display 的账户目录，root所有、普通账户只读；config/wallpaper.json 仅指定授权的初始UID，不含原图路径。Greeter 初始用户列表即消费此副本；选同一账户继续显示，选另一账户仅消费该账户副本，缺副本回退纯色。登录前不读取 home，不执行用户QML，不依赖用户平台socket。原图随后不可读仍可重绘公开副本。每次准备新的测试都会重新读取最新KOS设置并替换本次资源；不是登录前实时读取home或生产发布服务的安装。

`--no-wallpaper-sync` 仅跳过这一次自动发布；已有旧测试先运行原回滚命令再启动新脚本，脚本不会覆盖活动快照。

撤销本账户的同步选择及活动测试副本：

```sh
sudo python3 tools/test-greeter.py --revoke-wallpaper
```

撤销按调用UID隔离，先清 manifest/旧版本，随后以调用者权限禁用选择文件；消费者下一次校验丢弃旧图（通常一秒，读故障最多三秒）。无当前发布也能禁用本账户选择，不清理其他账户副本。显式 `--wallpaper` 预览属于单次管理员公开图片选择，停止该预览使用完整回滚。正常回滚删除整个临时公开目录，不改变你的KOS桌面选图。

自动接入证据与独立复审：`docs/kos-greeter/evidence/temporary-switch/kos-wallpaper/REPORT.md`。

## 壁纸构图与首显修正（2026-10-11）

正常显示由按输出四边锚定的 WallpaperWindows 独立背景层绘制，认证窗口透明，不叠加另一个按窗口比例裁剪的副本。认证窗口初始逻辑尺寸取活动屏幕；图片保持 KOS 的 crop/fit/stretch/center，不把 crop 偷改为 fit。crop 仍会按桌面相同规则裁掉屏幕比例之外的部分。

启动时立即读取已发布副本，不等首个一秒轮询。首显等待读取完成及图片解码/明确回退，亦等待活动屏背景层资源就绪；之后切换账户或撤销图片不会再次隐藏认证窗口。读取三秒、图片解码三秒有各自回退；背景层创建失败或无就绪回报时，七秒总期限使用认证窗口的内置背景/已解码图兜底，保持登录可用。此门槛是资源就绪，不承诺物理屏幕同帧呈现。

验证包括真实 Quickshell 延迟图片、坏图、缺背景及 Loader 错误，另在独立虚拟 KWin 16:10、向 KScreen 请求 1.5 倍缩放时验证全输出背景与桌面解码预算一致（预算按 Qt 实际报告 DPR 检查，未断言 Qt 有效 DPR 为 1.5）、认证窗口首次显示时资源已就绪。不切换本机显示管理器；物理画面需下一次用户实际运行确认。
