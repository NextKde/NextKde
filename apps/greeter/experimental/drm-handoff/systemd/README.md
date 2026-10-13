# 显式实验协调链路（未部署）

源码目标固定为 systemd v262、greetd 0.10.3，与父目录 KWin v6.7.5 补丁配合。默认入口不启用；本机二进制、服务及 VT 均未更换。真实 NVIDIA DRM/VT 连续性未测，不能将隔离验证等同于实机黑屏验收。

协议：greetd 的私有 seqpacket FD 只传入实验 Greeter/KWin；PAM worker 返回真实 UID 后固定 root 授权器发送 ARM + nonce + 只读 PNG SCM_RIGHTS，获得 PRESENTED，再准备 logind 并发送 CONFIRM。只有当前 READY 才继续会话；过期/错误确认会取消 logind。KWin 三秒期限不延长。greetd 仅允许固定 kos-user-session 且不接受参数/环境覆盖；普通启动默认不进入此分支。

logind 保留最多十秒；超时、后继死亡、取消解除。原子 `/run/systemd/greeter-handoff` 只记录 VT，不记录认证信息，也不恢复授权。logind 启动加载并检查所有已保存控制器后：有存活同 VT 控制器则保护它，否则恢复文字 VT。失败保留 marker 供下次启动重试。新控制器先成功保存，再清理 marker。测试使用 memfd 替代真实 VT，含实际 SIGKILL 子进程后 marker 恢复、恢复失败重试及不重置存活控制器。

## 复现构建

上游归档（将其解压到独立目录，禁止在宿主系统源码树直接覆盖）：

- [systemd v262](https://codeload.github.com/systemd/systemd/tar.gz/refs/tags/v262)，SHA256 `6aa77506c0644aa67f940a48e3d3a7368601f787e4f249139516d353f107bcab`。
- [greetd 0.10.3](https://codeload.github.com/kennylevinsen/greetd/tar.gz/refs/tags/0.10.3)，SHA256 `ee5cb70e0add4ca9c9fe57e47581ab0002d44c07743fb5492469f3b570db640b`。

各自源码目录 `patch -p1 < 本目录对应.patch`。systemd 需要 Meson/Jinja2/gperf 及上游编译依赖；本次仅用私有缓存工具，不安装软件包：

```sh
meson setup systemd-build systemd-v262 --prefix=/opt/kos-handoff/systemd -Dauto_features=disabled -Dlogind=true -Dtests=true -Dman=disabled -Dhtml=disabled -Dtranslations=false -Dinstall-tests=false
nice -n 10 ninja -C systemd-build -j2 systemd-logind test-greeter-handoff
cd greetd-0.10.3
nice -n 10 cargo test --locked -p greetd
nice -n 10 cargo build --release --locked -p greetd
```

没有安装脚本。Meson 配置只适合隔离原型构建，不是完整发行版 systemd 构建。

## VM 入口接线

所有 `/opt/kos-handoff` 路径及父目录必须 root 所有、不可组/其他人写、无符号链接：greetd 位于 `/opt/kos-handoff/bin/greetd`；授权器和实验入口位于 `/opt/kos-handoff/libexec/`，可执行权限 0755。KWin 固定 `/opt/kos-handoff/kwin/bin/{kwin_wayland,kwin_wayland_wrapper}`，应用仍为 root 管理 `/usr/local/lib/kos-greeter/app`。仅在一次性 VM 使用 `greetd-vm-only.toml`，并在启动实验 greetd 的环境显式设置 `KOS_GREETD_HANDOFF=1`。实验 Greeter 入口保留 FD 穿过 dbus-run-session；KWin 收到后删除变量并设 CLOEXEC，UI 不获得此权限。

认证后的 `kos-user-session` 仍采用已审固定 Plasma 入口。VM 用户的 `plasma-kwin_wayland.service` 必须显式使用示例 `plasma-kwin_wayland.service.vm-override` 重置 ExecStart 至独立 wrapper；仅设 KWIN_BINARY 对当前 systemd 单元无效。这两个文件只是配置示例，没有应用到宿主。VM 如需启动实验 logind，应单独替换 VM 单元并保留原二进制恢复路径；禁止将未实机验收的包安装到当前桌面。

## 隔离证据

`run-isolated-tests.sh` 使用 bwrap 新 rootfs/user/PID namespace，无宿主 PAM、显示 socket 或系统 bus；需缓存 fixture companion 为当前应用 resources.py/wallpaper.py 的只读副本，并可通过 KOS_HANDOFF_BUILD_ROOT 指定缓存目录。授权器使用真实 Reader、seqpacket/SCM_RIGHTS、假的 bus 调用，验证发布根选择/撤销、nonce、超时和 prepare/confirm 失败回滚。入口测试通过真实 dbus-run-session 到独立 fake KWin/UI，验证 FD 到达且不会泄露到 UI。

systemd 测试命令（普通用户执行，绝不能宿主 root 执行）：

```sh
bwrap --unshare-all --die-with-parent --new-session --ro-bind / / --proc /proc --dev /dev --tmpfs /run --tmpfs /tmp --uid 0 --gid 0 --unsetenv DISPLAY --unsetenv WAYLAND_DISPLAY --unsetenv DBUS_SESSION_BUS_ADDRESS --unsetenv GREETD_SOCK /绝对构建路径/systemd-build/test-greeter-handoff
./run-isolated-tests.sh
```

最终 greetd 12 项测试通过；logind 8 组状态/故障测试通过；授权器与入口隔离测试通过。附对应日志和源码摘要。它们验证组件和控制边界，不声称真实 PAM、三层同时运行或物理显示连续性已经验收。独立复审结果由任务证据目录记录。

`run-kwin-integration.sh` 用最终真实 VirtualBackend KWin、真实 dbus-run-session 和真实授权器 arm/prepare_and_confirm 函数，验证双输出 PRESENTED → READY → 正常退出保留，以及延迟 Prepare → EXPIRED → Cancel 回滚。bus 为明确的隔离假对象，不接真实 logind；root helper 的 main 进程身份验证不由此测试覆盖。实测日志见 real-kwin-coordinator.log。故障测试与组件单测结合给出协调边界证据，不伪称三层真实守护进程同时通过登录。

复审 P1 修复：取消阶段 vt_restore（含重新打开 VT 重试）失败时保留原子 marker，即使 Session 被 GC 也保留；任何新 ARM 不得覆盖待恢复 marker。成功恢复或现存可信控制器接管后才删除。新增失败取消→GC→新 ARM 拒绝→恢复测试通过。
