# T09 用户会话交接实现契约

入口：`apps/greeter/bin/kos-user-session`；仅接受无参数启动或 `--check`。前端 Greetd.launch 使用该绝对入口，入口再次核对已安装 Plasma desktop Exec 与固定 argv，不拼接 shell，不接受命令或文件路径参数。临时测试的文件清单包含入口与 companion/handoff.py；持久 app 安装入口仍属 T14，未安装/启用系统服务。

当前描述由认证后的 wrapper 按自身 eUID 从 T03 活跃发布 manifest 生成，不采信 Greeter 传来的 UID 或 home 路径。生产固定资源根为 `/var/lib/kos/greeter/display`，根及资源由 root 拥有；仅在已存在的 root-owned 临时测试 app 路径下读取其 public-display。缺失、撤销、损坏资源使用默认描述。T08 终帧 hash 的显式传输尚未接入；T10/T11 必须处理版本在 launch 前后变化的默认回退，不能声称三阶段已经一致。

## 支持的有限版本

这是 v1 的可运行静态子集，历史 handoff.example.json 是未来字段草案，不能直接作为程序输入。入口不读取该示例。

- 顶层严格为 schemaVersion/sessionId/issuedAt/expiresAt/user/resource/wallpaper/outputs/transition；未知及重复字段拒绝。JSON 上限 16 KiB，UTF-8，深递归回退。
- schemaVersion 整数1；sessionId 为 wrapper 新生成的32位小写十六进制 nonce，消费必须与当前引用一致；user 仅含当前 eUID。
- issuedAt/expiresAt 是 Unix 整秒，必须 issuedAt ≤ 当前时间 < expiresAt ≤ issuedAt+120。时间仅用于过期，不用于认证。
- resource 仅含 version/sha256；version 匹配 `v-[0-9a-f]{32}`，hash 为64位小写十六进制。资源路径由 T03 根/UID/版本推导，描述禁止 path。每次消费核对当前授权 manifest、活跃版本、内容 hash 和 fit；撤销与版本替换不复用缓存。默认为 version=default、空hash和crop。
- wallpaper 仅 image、四种 T03 fit、phase=null；theme/spatial 延后 T12。图片沿用 T03 的16 MiB/1600万像素/单边8192解码预算。
- outputs 最多16，connector/hardwareId 为1–128位 ASCII标识；connector 不重复；width/height 为1–16384整数；Hz有限1–1000、scale有限0.5–4；rotation 为0/90/180/270；position 为两个±32768整数；crop 为有界归一化矩形；vrr=never/automatic/always；hdr为布尔。字段不能携带代码。wrapper 当前生成空数组，表示由机器安全策略重新匹配，**不表示已应用输出配置**。
- transition 抑制初次壁纸切换固定true；两个建议时长为0–1000整数毫秒。T11 实际消费尚未实现。

## 文件、环境与生命周期

真实 XDG_RUNTIME_DIR 必须为绝对、非链接、当前 UID 拥有的0700目录。新建 `kos-handoff-<sessionId>/`，0700；通过目录 fd 操作，临时文件0600、fsync、原子 replace 至 handoff.json、目录fsync。记录文件 inode 和内容摘要；wrapper 校验拒绝替换、修改、硬链接、symlink、权限放宽及超长数据。

只向固定 Plasma 子进程局部传递 KOS_HANDOFF_PATH/KOS_HANDOFF_SESSION/KOS_HANDOFF_SHA256；不写全局用户管理器或 DBus 环境。陈旧的同名环境变量先移除。T10 使用 `read_reference(XDG_RUNTIME_DIR, sessionId, sha256)`：忽略任意 path，按固定目录名定位，校验文件和当前发布授权，成功后单次删除文件；无效时返回None并使用内置背景，不能阻塞可用桌面。T10 现在由 wrapper 并行启动 Cover supervisor，并局部传递这些引用；supervisor 等待实际 KWin socket 再启动 Cover，独立进程消费一次引用。详见 early-cover.md；systemd 服务没有自动继承这些局部变量。

wrapper 持有同 UID 的持久 flock inode `kos-desktop-session.lock`，拒绝第二个 wrapper；检查活跃 kos-shell.service 和其他 logind 图形会话。检查失败拒绝启动。此锁不拦截绕过 wrapper 的外部手动启动，不提供完整多桌面支持；T14 继续验证当前共享用户服务的限制。

正常退出、目标命令失败及 TERM/INT/HUP 转发后按拥有者清理当前文件和目录；信号转发给固定子进程组，5秒后强制结束。不会 glob 删除其他会话。锁文件保留而锁释放，避免不同 inode 分裂锁。SIGKILL/断电无法执行 finally，可能留空/未消费目录；描述120秒过期后拒绝消费，注销销毁 runtime 时由系统移除，不能声称 SIGKILL 后即时清理。其他会话仍活跃时不得删除其目录；同 UID 恶意进程不属于文件权限隔离边界。

## 验收范围

A11/A13 的 T09 描述、文件和本地进程子项可独立验收；真实 PAM/双KWin/三阶段画面/scanout/持久安装没有在本卡运行，也不因此重新打开已经关闭的 T02/T06。

## 2026-10-12 wrapper关键路径降时

生产wrapper的build/write/consume显式采用metadata-only live引用检查：仍校验有限schema、UID/session/摘要、root发布目录/manifest有效期/版本/fit/hash字段、目标文件元数据，但不将它当图片已就绪。被引用资源的真实字节/hash/canonical/尺寸在Cover read_reference和消费路径仍完整验证，失败回退；其余调用默认完整检查。这样不在启动Plasma前重复PNG解码/重编码。
