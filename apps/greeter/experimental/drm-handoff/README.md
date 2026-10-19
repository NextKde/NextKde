# 有界 DRM 背景交接实验

此目录交付可构建的 KWin 6.7.5 行为补丁和隔离执行夹具。最终八个虚拟行为场景和十四个 native publication 场景已通过；真实 DRM/VT 连续性未测。默认生产入口与安装脚本没有开启实验；源码构建和测试不安装、不重启宿主 KWin/greetd/logind、不切 VT。systemd/greetd 权限和 VT 协调实现另见 `systemd/`。

## KWin 两端

- 旧端持有一个私有匿名 `AF_UNIX/SOCK_SEQPACKET` 端点。真实 DRM 只接受 root peer；端点设 CLOEXEC，环境变量在启动会话前清除，UI 子进程得不到该权限。
- 已认证 root 协调器发送 `ARM:cover:<uid>:<32位小写hex nonce>` 或 `ARM:contain:<uid>:<nonce>`，恰附一个 SCM_RIGHTS 只读 PNG fd。KWin 校验 root 所有权、不可组/其他写、文件/字节/像素上界，再按该 UID 读取当前公开 manifest，核验 SHA256、尺寸和构图。
- 无授权公开图时发送 `ARM:default:<nonce>`，不附 fd。KWin 绘制与现有 Greeter/Cover 相同的内置 `#16283b`。
- 武装后 KWin 自身绘制纯背景，不截图登录窗口，排除窗口、DND、鼠标及 direct scanout。每个当前输出的 `OutputFrame::PresentationFeedback` 到齐后才返回 `PRESENTED:<nonce>`。旧反馈和旧超时用 generation 隔离。
- root 协调器在 logind Prepare 后发送 `CONFIRM:<nonce>`；仅相同 nonce、所有输出已呈现且仍至少剩余一秒时返回 `READY:<nonce>`，否则 `EXPIRED:<nonce>` 并取消对应武装。确认不续期。
- 三秒武装超时返回 `TIMEOUT:<nonce>`，恢复正常窗口。`CANCEL`、控制通道断开、非正常会话退出、输出变化均取消；旧端必须在收到 PRESENTED 后、期限内正常退出 0，才局部抑制 `DrmGpu` 析构中的最后 unused-object disable。日常热拔线不改。现有 CloseFB 保留，未加重复 CloseFB。
- **进程正常退出不是认证证据。** 是否可以 ARM 由 systemd/greetd 的 root 已认证协调器决定；单独运行 KWin 不提供 PAM 认证。
- 新端实验 `kwin_wayland_wrapper` 固定启动同目录实验 `kwin_wayland`，自行选择 `geteuid()` 的公开图，不使用任意环境路径、不全局导入 fd。每次重启重新打开和校验源。首个场景前准备背景；无图或不支持的构图使用内置默认色。背景在正常窗口下方，十五秒自动撤除，不永久遮盖桌面。

## 公开图契约与撤销

只选择两个硬编码根。若 `/usr/local/lib/kos-greeter/app/public-display` 存在，就仅使用该根；根或账户不可信、manifest 缺失/撤销都默认回退，**不再尝试 var 根**。只有该目录不存在时才使用 `/var/lib/kos/greeter/display`。选中路径逐组件 `openat/O_NOFOLLOW`，root 所有、不可组/其他写。

manifest 上限 4096 字节；版本 `v-<32hex>`、schema/UID/日期/资源字段严格校验；PNG 上限 16 MiB、8192 单边、16M 像素；文件 nlink=1；原字节 SHA256 和 IHDR 尺寸匹配。启动至少剩余三十秒有效期。`crop`→cover、`fit`→contain；`stretch/center` 本实验默认回退，未宣称相同构图。KWin 每 500ms 检查当前 manifest/version/hash/文件元数据；撤销或版本变化转默认色并取消旧保帧。没有独立持久快照缓存。

## 构建

上游来源固定为 [KWin v6.7.5](https://invent.kde.org/plasma/kwin/-/archive/v6.7.5/kwin-v6.7.5.tar.gz)，原始文件摘要见 `kwin-source-sha256.json`。在独立源码目录解包后：

```sh
./apps/greeter/experimental/drm-handoff/build.sh /absolute/clean/kwin-v6.7.5 /absolute/private/build /absolute/private/protocol-prefix
```

要求 Qt/KDE/KWin 开发依赖，以及 WaylandProtocols≥1.48、PlasmaWaylandProtocols≥1.21。构建脚本只应用固定补丁并构建 `kwin_wayland`、`kwin_wayland_wrapper` 和无凭据 Qt fixture，不执行安装。已经打过补丁的源码会拒绝重新应用，增量使用 `cmake --build`。

## 隔离执行

```sh
./apps/greeter/experimental/drm-handoff/run-fixture.sh /absolute/build/bin/kwin_wayland /absolute/build/fixture-session /usr/share/wallpapers/Next/contents/images/1440x2960.png normal
```

可选场景：`normal timeout cancel bootstrap nonce scm rejected confirm-expired`。夹具强制双虚拟输出，私有 DBus、PID/网络/IPC/挂载命名空间；隐藏宿主 `/run`、`/tmp`、`/dev`，清除宿主显示与认证 socket 环境；只显示无凭据模拟窗口。`GREETD_SOCK` 不接触。bwrap 的 user namespace 将宿主 root 文件映射成 65534；仅实际 `VirtualBackend` 允许这个测试映射，外层先检查宿主 root 所有权，真实 DRM 始终要求 root=0。旧无 nonce 命令仅虚拟后端兼容夹具。

Native publication 测试用 synthetic root 命名空间，检查实际 C++ parser，无需 sudo：按 `build.sh` 同样 QtCore flags 编译 `publication-probe.cpp`（include 指向已打补丁源的 `src`），然后 `python3 test-publication.py /absolute/publication-probe`。

## 部署与恢复边界

完整系统实验必须同时使用这里的匹配 KWin、`systemd/` 的 logind/greetd 协调和可信公开根。只装 KWin 会被 greetd worker 的 KD_TEXT/清屏以及 logind 的 VT 恢复覆盖，不能作为完整修复。使用独立前缀与 VM 显式 compositor service override，禁止普通 Greeter 更新顺带替换 `/usr/bin`。

回退为撤除 VM 的实验启动/service override 与协调器配置，恢复原二进制/快照。宿主本轮没有部署，因此宿主不需要执行恢复命令。未经独立审核和明确系统实验授权，不提供“一键启用”。

录屏不是编译或隔离验证的前提。虚拟 presentation 和日志通过仅证明代码路径；NVIDIA 615、实际显示/多 GPU/VT/CloseFB 的连续性及物理黑帧仍需实机验证，不能宣称零黑帧或已解决宿主黑屏。静态持帧期间不保证 spinner 连续运动。
