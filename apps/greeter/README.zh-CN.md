# KOS Greeter 最小生命周期原型

独立 Quickshell app，不导入桌面 Shell、用户主题或用户壁纸。当前仅用于 T02；不是可部署的登录管理器，安装/卸载入口由后续任务交付。

依赖：Python 3、greetd、Quickshell 0.3 Greetd API、KWin Wayland、Qt Quick Controls、已安装的 Plasma Wayland 会话。测试另外需要 Node.js。固定会话允许清单是 `/usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland`，启动前与 `/usr/share/wayland-sessions/plasma.desktop` 精确比对；不会执行任意 Exec 或用户命令。

运行预检：`apps/greeter/bin/kos-greeter-session --check`。离线预览：先移除 GREETD_SOCK，再运行 `apps/greeter/bin/kos-greeter-ui`，此时认证禁用。源码树无需构建；运行入口和资源都在本 app 内，正式打包尚未实现。

状态：Idle → Authenticating ↔ AwaitingPrompt → ReadyToLaunch → Exiting → LaunchRequested → Terminated。取消先进入 Cancelling，等待后端 Inactive 才开放新的认证。消息依照 echoResponse 决定是否隐藏输入；非 responseRequired 提示不发送响应。响应发送、失败、取消、退场和退出时清空表单，不记录用户名、PAM 提示或响应。应用层清空不保证 Qt/JS 内存密码零化。220ms 占位退场后 launch，确认后退出；不等桌面就绪。认证/取消 60s 超时、launch 10s 超时后退出，交给隔离环境管理员恢复，当前不承诺自动重启次数控制。

测试：

```sh
node apps/greeter/tests/lifecycle.test.cjs
python3 apps/greeter/tests/ipc.test.py
```

IPC 测试使用真实 Quickshell 与假 greetd socket，只模拟协议成功、失败重试、取消、断连和 launch 拒绝；不使用真实账户/密码，不验证 PAM。断连测试将生产 60s 超时缩短到 500ms。虚拟 KWin 退出测试入口为 tests/exit-fixture；它也不验证登录。

## 隔离 VM 实验步骤（尚未执行）

只在可丢弃 VM 中复制本 app 到 root 管理的只读目录，例如 `/opt/kos-greeter`，保留可执行权限。VM 安装上述依赖并建立专用 greeter 账户，通过发行版正常 greetd/PAM 配置；不得用宿主的真实账户或更改宿主 PAM。先记录版本、VM 快照、原 display-manager 指向、配置备份、可用的串口或第二个 TTY，演练停止 greetd、恢复原管理器并计时。未证明恢复入口前不启动实验。

VM greetd 配置样例（不是宿主安装指令）：

```toml
[terminal]
vt = 2
[default_session]
command = "/opt/kos-greeter/bin/kos-greeter-session --isolated-seat"
user = "greeter"
```

不配置 initial_session 自动登录。记录实际 seat、VT、argv、父子 PID 和单调时钟。VM 管理员手动开启实验服务；本 app 没有启用系统服务的命令。成功后用户会话必须是允许清单内 Plasma，登录 KWin 应随前端退出。使用 VM 屏幕录像，但密码输入阶段遮挡/暂停，不保存密码可见画面或原始 IPC；不得打开协议 debug 日志。

依次验证错误认证后重试、secret/非 secret/纯信息提示、提示取消、断连、前端崩溃、Plasma 立即失败。记录每次恢复到登录或 TTY 的命令、耗时、最终进程树。用户会话立即失败应在 VM 的受控包装入口注入，并重新独立审查测试允许清单，不能把任意命令入口加入产品。另在仅测试版本的人为有限退出延迟下观察 greetd 是否等待，解除延迟后确认启动，不在产品添加生产延迟开关。

任一故障产生启动循环，停止 VM 的 greetd、恢复原 display-manager/config/PAM 快照并重启原管理器；具体原服务名取 VM 实测。恢复失败则回滚 VM 快照。清理 app 目录只涉及资源；必须先恢复管理器，不能靠删除 app 恢复登录。T02 完成需另有真实录像、进程树、A01/A02/A14-P/G1 及独立审查证据。

## T05 身份与认证

AccountsService 只读列表使用 system bus 与 busctl，UID 关联、UserName 认证、RealName 展示；其他用户保留手工登录。仅安全的管理员头像副本可读取，home/缺图/损坏回退默认头像。Python 3 与 busctl 为列表依赖，Pillow 为可选头像依赖；缺失仍保留手工登录。支持多轮 secret/visible/info/error、取消返回列表和键盘焦点恢复。运行 `python3 apps/greeter/tests/accounts.test.py` 和原 IPC/model 测试。T05 已由用户验收完成，见 docs/kos-greeter/evidence/T05/REPORT.md。

用户明确要求的临时测试/回滚脚本已提供：`tools/test-greeter.py` 和 `tools/rollback-greeter.py`。它们使用独立 runtime 服务与定时回滚，不更改持久登录配置。本次没有实际切换。用法和完整回滚边界见 [临时测试说明](TEMPORARY-TEST.zh-CN.md)；该显式实验入口补充原隔离 VM 方案，用户已验收关闭 T01–T06，物理测量边界见各任务验收记录。

## T07 独立壁纸宿主

`apps/greeter/bin/kos-greeter-wallpaper` 可在隔离/嵌套 Wayland 会话独立运行，每个活动输出有独立背景窗口。管理员可通过 `KOS_GREETER_WALLPAPER_UID` 指定已授权公开副本的 UID；消费目录固定 `/var/lib/kos/greeter/display`，要求 root 所有，未部署/未选择时使用固定背景，不读取 home 或平台 socket。认证 app 复用此组件，次屏也有背景。此命令不安装或切换登录管理器。

运行 `python3 apps/greeter/tests/wallpaper.test.py` 和 `python3 apps/greeter/tests/wallpaper-render.test.py`。后者自动创建虚拟 KWin，覆盖 1/1.5 缩放、四种 fit、独立离线夹具像素对比、故障回退及输出释放。资源消费依赖 Python 3/Pillow，缺失保持默认背景。主题加载须通过 app 固定文件哈希清单，升级需重新审查清单；源码 `wallpapers` 链接指向 shared，打包须保留可信资源到 app 根内。事件含义与限制见 [宿主契约](../../docs/kos-greeter/contracts/wallpaper-host.md)，证据见 [T07 报告](../../docs/kos-greeter/evidence/T07/REPORT.md)。专属安装/卸载仍由 T14 汇总，尚未执行系统部署。

T09: `bin/kos-user-session` is the fixed authenticated Plasma wrapper. See [session handoff contract](../../docs/kos-greeter/contracts/session-handoff.md) and [isolated evidence](../../docs/kos-greeter/evidence/T09/REPORT.md). Run `python3 apps/greeter/tests/handoff.test.py` from the repository root. No persistent installation or manager switch is performed.

### 早期桌面 Cover（T10）

`kos-user-session` 现在与固定 Plasma 启动链并行运行独立 Cover supervisor，等待用户 KWin socket 实际可连接，再显示每输出静态 overlay；不等待 platform/data 或完整 Shell。Cover 15 秒自撤罩，supervisor 25 秒总期限兜底，无自动重启。T11 已接入按会话/输出/hash匹配的 `cover describe` / `cover reveal` 正式帧与bar/Dock门控；完整 A03/A10、真实冷热启动录像仍阻断，见 [T11证据](../../docs/kos-greeter/evidence/T11/REPORT.md)。`... ipc call cover abort` 保留人工恢复，旧 ready 仅作 T10 恢复兼容。参见 [契约](../../docs/kos-greeter/contracts/early-cover.md) 与 [隔离测试](../../docs/kos-greeter/evidence/T10/REPORT.md)。此次没有安装/启用系统服务，未证明真实三阶段呈现或零黑帧。

### 正式安装与回滚脚本

用户于2026-10-12明确要求编写持久安装/启用与回滚脚本。现提供 `tools/install-greeter.sh` 和 `tools/rollback-installed-greeter.sh`，默认改为下次开机使用greetd，立即切换须从文字TTY显式指定。详见 [安装说明](INSTALL.zh-CN.md)。本轮只编写/隔离测试，未实际部署；原临时回滚仍用 `tools/rollback-greeter.py`，两者不能混用。
