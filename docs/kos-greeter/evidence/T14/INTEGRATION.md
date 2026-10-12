# T14 集成、安装与恢复评审方案

日期：2026-10-12 Asia/Shanghai。仅方案与隔离测试；不执行本机安装或系统切换。完整验收未通过，不建议进入 G5。

## 安装清单与依赖

真实独立 bundle 清单见 `bundle-files.json`，由 `tools/greeter-install.py --build … --no-wallpaper-sync` 生成：app 的 QML、Python、bin、config 与可信 shared 渲染资源。无天气/音乐、研究参考图或完整 Shell 打包。安装路径为 `/usr/local/lib/kos-greeter/app`；系统配置包括 `/etc/greetd/config.toml`、greetd 恢复 drop-in、`kos-greeter-recover.service`、系统用户级 `kos-shell.service` 路径 drop-in 与 `/usr/local/sbin/kos-greeter-rollback`。具体受管文件以 `tools/greeter-install.py` 的 `FILES` 为准。

依赖：发行版 greetd/PAM、非 root greeter 账户、Quickshell、KWin Wayland、KScreen、Plasma Wayland、systemd/logind、D-Bus、Python/Pillow；本轮版本见 `environment.txt`。这些是当前验证版本，未验证跨发行版最低版本。Shell 须具备 T11 门控；安装不升级整个桌面。缺依赖拒绝，不自动安装依赖，不生成 PAM。

## 操作入口与授权边界

以下为后续获授权的操作方案，不是本轮已执行记录。详见 `../../../../apps/greeter/INSTALL.zh-CN.md` 与 `TEMPORARY-TEST.zh-CN.md`。

| 目的 | 入口 | 效果/限制 |
| --- | --- | --- |
| 普通用户构建 | `python3 tools/greeter-install.py --build <临时目录>/bundle --no-wallpaper-sync` | 不安装、不切换；本轮已执行 |
| 只读预检 | `./tools/install-greeter.sh --check` | 通过 sudo 读取系统预检；本轮未执行 |
| 单次试运行 | `python3 tools/test-greeter.py --help` 所列临时流程 | 从不同于登录 VT 的文字 TTY 执行；结束当前图形会话；须另行授权 |
| 文件安装 | `./tools/install-greeter.sh --files-only` | 写 app/配置，保持 boot enablement；仍是系统写操作，须另行授权 |
| 持久启用 | `./tools/install-greeter.sh` | 默认下一次开机 greetd；先备份原管理器；须另行授权 |
| 立即启用 | `./tools/install-greeter.sh --activate-now` | 仅文字恢复 TTY；结束当前桌面；须另行授权 |
| 临时恢复 | `sudo python3 tools/rollback-greeter.py` | 使用临时测试快照；不能混用于持久安装 |
| 持久恢复/卸载 | `./tools/rollback-installed-greeter.sh` | 恢复原服务/配置后删除 app/公开副本；活动 greetd 时须文字 TTY |
| 脱离源码恢复 | `sudo /usr/local/sbin/kos-greeter-rollback --rollback` | root 安装副本；或 `sudo python3 /var/lib/kos-greeter-install/rollback.py --rollback` |
| 公共图刷新/撤回 | `./tools/install-greeter.sh --refresh-wallpaper [--no-wallpaper-sync]` | 当前账户重新取得同意或撤回；不重新启用管理器 |

安装默认启用源于先前明确脚本需求，不能把普通 install 当纯资源安装；隔离资源安装应使用 `--files-only`。`kosctl install/uninstall greeter` 尚无入口，不提供虚构命令；专属脚本为当前产品入口。普通 `install apps` 未接入 Greeter，源码检查未见附带 Greeter 启用；完整合集实机安装仍未测。

## 恢复演练与升级

临时 root 文件树 + fake systemd/logind 的 `install.log` 覆盖备份在修改前完成、精确恢复 alias/wants 链接、配置字节/权限、原服务 active、getty 状态和新增 greetd 会话清理。失败自动恢复；恢复失败保留快照/app，修正原因后重试。真实 TTY 可操作性、发行版别名行为和原管理器重新登录未测。宿主本轮原有 greetd active/enabled，不能误称本轮恢复了 plasmalogin；只读前后状态见 services 文件。

同 bundle 重装保留首份快照；不同 bundle 明确拒绝原位升级。当前升级方案为保存工作 → 文字 TTY 回滚并核验原管理器可登录 → 安装新 bundle → 失败时用新安装快照回滚。升级不是原子切换；停机时长、跨版本兼容和断电恢复未测。受管配置被管理员修改时拒绝覆盖，保留快照，人工核验差异后处理。

恢复耗时：`results.json` 是各套件耗时，不能作为真实登录恢复耗时；虚拟 KWin 终止耗时见 `supervisor.log`。原管理器物理恢复耗时未测。

## 隐私、公开资源与许可

本轮测试只用合成图、虚拟输出及 mock IPC；不连接宿主 GREETD_SOCK，不记录真实密码，不截用户桌面。handoff 只含有限展示字段，0600、session 隔离、单次消费；无全局 systemd/dbus 环境导入。IPC 日志仅记录请求类型，测试响应为合成值，不能证明真实 PAM 日志无泄漏。

发布需要每账户明确同意及认证前可见范围说明；图片去元数据，root 安装副本与 home 分离。已测发布中断/GC/撤回、读取端默认回退、Cover 与门控撤销；完整真实账户删除事件联动与所有消费端旧缓存清理未测。当前 24 小时过期与显式刷新不能保证账户删除当刻自动撤回；上线前须补账户删除的显式清理操作与证据。

Apple/512 Pixels 参考图仅研究使用，未获产品再分发许可；不在 bundle 内，不分发 Apple 系统字体。仓库 theme/shared 资源的信任哈希不等于版权许可；完整资产、字体与第三方依赖分发许可核验仍未测，发行前须完成清单。当前不能写“所有资源许可通过”。

## 剩余风险与阻断

| 优先级 | 缺口 | 解除条件 |
| --- | --- | --- |
| P1 集成阻断 | 未验证物理恢复 TTY、真实 Greeter/UI 故障返回原管理器；OnFailure 只覆盖 daemon 失败 | 授权后逐项实机故障注入，核验可登录及残留 |
| P2 验收阻断 | T11/T12 完整生产三阶段、冷/热启动与 A03/A10/A12 未测 | 同版本背景及正式 Shell 录像/呈现证据 |
| P2 验收阻断 | A18 真实账户删除联动及所有消费端失效未测 | 删除/撤销/中断场景的端到端证据 |
| P2 验收阻断 | A19 真实独立安装、缺依赖、升级/卸载及合集操作未测 | 干净环境安装/恢复日志与实际服务状态 |
| P2 验收阻断 | 资产/字体完整分发许可未核验 | 发行资源来源和许可清单 |
| 指标未测 | A16 没有外部高帧率跨会话录像 | 依 T13 PROTOCOL 采集并统计；不承诺零黑帧 |
| 视觉限制 | Tahoe 同状态实机基准/动画参数缺失 | 首版标明自有视觉；不宣称 1:1 |
| 产品限制 | 同 UID 共享 Shell 不支持并发图形会话 | 维持 wrapper 明确拒绝第二会话；不以文件隔离宣称并发支持 |

阻断来自既有契约与证据缺口，不将其误称为本轮新发现的已修复实现缺陷。授权实机工作前应复核当前服务和快照状态，不能直接套用历史 plasmalogin 记录。
