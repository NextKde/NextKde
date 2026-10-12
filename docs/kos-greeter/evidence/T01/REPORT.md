# T01 事实与环境核验报告

状态：完成。执行者：Codex 主代理。日期：2026-10-11，Asia/Shanghai。
分支：codex/notification-center-stacks。源码基线：54512887915152c514b9d08f3a45ca14779e1adc，与研究基线相同。
开始时 docs/kos-greeter/ 整包为未跟踪文件。本次只新增本证据目录、审查记录和更新任务状态；不安装、不切换服务、不实现 UI。

## 事实、版本与差异

以下证据路径均相对本目录；源码精确片段及行号见 source-excerpts.txt，摘要见 source-sha256.txt。版本是审计快照，不是依赖已写入包管理锁文件。

| 项目 | 已观察事实 | 证据与差异/限制 |
| --- | --- | --- |
| 源码 | HEAD 与研究基线相同 | source.txt；源码没有新增 Greeter |
| 旧 SDDM | 76137dc85ea8d44074a036d1550e608450c08750 去掉安装/卸载分派，源码 apps/sddm/Main.qml 保留 | baseline.txt；README.md:197，tools/kosctl:1317；提交只称集成问题，具体故障根因未知 |
| Quickshell | 0.3.2-1，运行时 0.3.2；Arch 构建不提供 revision | versions.txt、qs-version.txt；官方参考接口版本 0.3.0，补丁版真实认证行为留 T02 |
| KWin | 6.7.5-3，运行时 6.7.5；存在 --exit-with-session | versions.txt、kwin-version.txt、kwin-help.txt；未启动额外 KWin，真实退出/DRM 释放未测 |
| Qt | qt6-base 6.12.0-2，qt6-declarative 6.12.0-1 | versions.txt |
| greetd | pacman 无包，PATH 与 /usr/bin/greetd 均无程序 | versions.txt、extra.txt；运行版本无法锁定，T02 隔离环境需先选定和记录版本 |
| 当前显示管理器 | display-manager.service 实际为活动的 plasmalogin.service；所属包 plasma-login-manager 6.7.5-1 | display-manager.txt、extra.txt；不是 SDDM；pacman 查询 plasmalogin 无包是包名不符，不表示服务缺失 |
| 系统与 GPU | Arch；内核 7.2.9-zen1-1-zen；NVIDIA RTX 4070 Mobile/nvidia 与 AMD Radeon 610M/amdgpu | kernel.txt、gpu.txt；mesa 1:26.2.4-1、nvidia-utils 615.78.08-1（versions.txt、driver-versions.txt）；实际 scanout GPU 未测 |
| 壁纸 | mode=image、takeoverEnabled=true、fitMode=crop、transition=top、slideshowEnabled=false；themeId=blackhole 为保留值 | wallpaper.txt；WallpaperService.qml:17–57；实际 key 是 fitMode，契约中的 fit 尚未实现；私有路径脱敏，未发布资源也没有认证前公开授权 |
| 壁纸 ready | 按输出收集资源与 transition 完成状态 | WallpaperService.qml:230–268；不是 scanout 证据；当前 service 导入 desktop/platform，不能直接用在登录前 |
| 共享主题 | ThemeWallpaperScene 仅直接 import QtQuick，host 注入 phase/天气/指针等；Loader 选择内置主题或 packResolver 返回路径 | ThemeWallpaperScene.qml:1–65；共享不等于登录前可信，Greeter 禁传用户 packResolver，仅允许审查过的内置资源；动态 phase 不代表 GPU 状态 |
| Shell 依赖 | Requires platform，Wants data，After KWin/plasmashell/graphical-session；qs --no-duplicate -c kos | kos-shell.service.in:3–37、shell-unit.txt；完整 Shell 不能成为早期独立 Cover |
| 平台输出 | parseDisplayOutputs 仅保留 connected+enabled 输出的 name、priority、connected、enabled | PlatformServer.cpp:1759–1787；模式、Hz、scale、rotation、HDR、VRR、位置及硬件标识均未透传，拟议 outputs 契约需要扩展或独立读取 |
| 显示 | eDP-2，currentModeId=2，2560×1600，239.9980010986328 Hz，scale=1.5；位置 0,0；逻辑 screen 1707×1067 | outputs.txt；preferredModes=[1]，59.999000549316406 Hz；extra.txt 的 -o 明示 VRR Never/HDR disabled |
| 旋转 | KScreen rotation=1 | outputs.txt、extra.txt；不能直接拷贝到草案 rotation=0，T06 必须定义枚举到角度的转换；EDID 映射和登录前模式未测 |
| KSplash | Engine=none、Theme=None | ksplash.txt；不假定它提供交接遮盖 |
| 账户 | AccountsService 26.27.3-1；缓存返回一个 UID 1000；UserName 与 IconFile 有值、RealName 空、SystemAccount=false、Locked=false | accounts.txt、account-fields.txt；字段值脱敏；展示名应回退 UserName；缓存不是全部登录账户，保留其他用户；Greeter 身份头像可读性未测 |
| 当前会话 | UID 1000 的一个 seat0/tty1 user 会话，另一个 manager 会话 | sessions.txt；不是两个图形会话 |
| Plasma 入口 | /usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland | plasma-entry.txt；只读定位，未执行登录/注销 |

## greetd 事件语义与来源核验

2026-10-11 成功读取 [Quickshell Greetd 官方接口](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/Greetd/) 与 [官方 GreetdState](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/GreetdState/)。ReadyToLaunch 表示认证成功，可发启动请求；launched 只表示 greetd 确认请求。默认 launch 会退出 Quickshell，quit=false 时由调用者退出。动画须在 launch 之前结束；认证提示只有 responseRequired 时调用 respond，失败和可恢复消息应分别处理。这里核实的是文档语义，未对本机 0.3.2 进行 PAM/IPC 实测。

上游 [greetd 项目手册](https://man.sr.ht/~kennylevinsen/greetd/) 访问被 robots.txt 拒绝。可达的 [作者手册 Debian 镜像](https://manpages.debian.org/unstable/greetd/greetd.1.en.html)（来源包 0.10.3-7，页面源日期 2026-08-17）说明：Greeter 请求启动并终止后才启动新会话。其包版本不是本机已安装版本或 T02 选定版本。记录此限制，不将镜像可达等同上游实测。

因此 Greeter/登录 KWin 不得等待尚未启动的用户桌面。KWin 的退出选项仅由本机帮助确认存在，生命周期、seat/VT、权限和黑帧均需要 T02/T06/T13 的隔离或硬件证据。

## 同 UID 多会话盘点与策略

已观察的启动组合：本机一个 Plasma Wayland user 会话 + 用户级 kos-shell.service 活动。源码提供 kosctl start（统一重启用户服务）和 dev（共享正常 platform/data 的源码调试）；这些入口存在不表示两个完整图形桌面并发已通过。qs-help.txt 确认同配置已有实例时 --no-duplicate 直接退出；tools/kosctl:992–997 主动杀掉手动 kos 实例再由 systemd 接管。

当前共享用户 unit 和配置没有 session 实例键。T01 产品边界决定：首版目标限定每 UID 一个完整 KOS 桌面；不得对同 UID 第二个图形会话承诺完整 KOS。拟议 wrapper 发现已有该 UID 图形会话时拒绝 KOS 交接并清理此次描述，回退普通 Plasma（不能重启/杀掉已有会话服务）；若不能可靠隔离共享服务，保持登录并说明不支持。此拒绝/回退尚未实现，须 T09/T14 验证。不同 UID 隔离、dev+正式实例、嵌套会话和第二个完整桌面均未执行并发测试。runtime 文件按 session 隔离只能隔离描述，不能解决服务单例。

## A19 结构设计（拟议，未实现）

选定源码/资源边界为 apps/greeter/，QML/Quickshell 独立进程，不改旧 apps/sddm，不复用完整 Shell。计划文件：shell.qml（入口）、qml/（认证状态和展示）、assets/（内置回退背景/默认头像）、bin/kos-greeter-session（启动/退出独立 KWin 的固定参数 wrapper）、CMakeLists.txt、README.md/README.zh-CN.md、tests/。桌面发布端和交接 wrapper 置于该 app 的 companion/，各自独立进程与权限，不要求登录 app 访问用户平台 socket。

运行入口拟议为安装的 kos-greeter-session，内部使用 kwin_wayland --exit-with-session 和固定 qs -p 路径；实际 argv/退出顺序由 T02 验证，不在本次生成可部署配置。Greeter 不是普通 .desktop 启动应用。可信 shared/qml/wallpapers 可按显式资源清单复用；禁止导入 shell/desktop、其他 app、用户主题包和完整用户服务。shared 的递归 QML/shader 依赖及许可需 T07 逐项检查，不盲目复制全部 shared。

构建计划：根 CMake 新增默认 OFF 的 KOS_BUILD_GREETER 及专属 greeter-dev/greeter-release preset，关闭平台、KWin 插件、空间推理与所有无关 app，BUILD_TESTING=OFF 的生产打包不拉入现有其他 app 测试目标；Greeter 自身测试单独开启。QML 数据资源安装采用显式清单，必要 native 模块再独立构建。现有 CMake 没有这些目标/preset；最终依赖清单以原型导入验证为准。运行必需候选为 greetd/PAM、KWin、Quickshell Greetd/Wayland、Qt Quick、system D-Bus/AccountsService；编排 seat/logind 与权限留 T02。CMake/Ninja 为打包工具，天气/Go/ListenFree SDK 不应成为依赖。

专属命令保持 ./tools/kosctl install greeter、./tools/install-greeter.sh、./tools/kosctl uninstall greeter 的设计值，当前均未实现。仅安装 app 与必要配套、预检依赖、保留安装清单；安装与持久启用分离，默认不切换显示管理器/PAM，不从 install apps 自动启用。T14 实现并验证重复安装、升级失败回滚、活动服务卸载检查、配置备份与当前 plasma-login-manager 恢复。资源发布另需每账户显式授权，桌面选图不自动授权。

## 缺失依赖和后续门槛

- greetd 未安装，运行版本未知；T02 必须在隔离环境固定版本和 PAM/seat/VT，验证恢复后才能评审系统切换。本机不补装。
- 无 Greeter app、wrapper、发布服务、Cover、专属构建/安装入口；属于后续卡实现，不是 T01 失败。
- AccountsService 字段只读查询通过，Greeter 头像读取/账户变更/其他用户未测；资源公开授权和清理由 T03 验证。
- 当前输出已核验；登录前模式、EDID 稳定身份、合盖/热插拔、双 GPU 交接、零黑帧未测。
- greetd 上游手册受限、0.3.2 本地认证语义未测，不能用文档替代 T02。

## 验收、时间线与恢复

T01 命令/源码事实采集通过；版本已记录，缺失与差异明确；A19 仅结构设计交付。A01–A16、A18 及 A19 安装/卸载/升级实测全部未测；A17 见独立审查记录。T01 关闭不表示 G1 或后续任务原型门槛已满足。

所有认证成功、退场、launch、KWin 退出、Cover 映射、scanout、揭幕时间线：未测。无视频、无 Tahoe 像素比较、无空白帧统计。背景原图 hash 未采集：本卡仅配置核验，未授权发布，不创建背景快照。

预置恢复边界：本任务没有服务切换，未验证 TTY 恢复操作。只读查询失败（greetd/sddm 包不存在、plasmalogin 包名不符、上游 robots 拒绝）均保留原失败结果，继续只读核验，不修系统。重复触发可重跑对应证据首行命令或访问上述来源；无需恢复命令，恢复耗时不适用。最终 display-manager=plasmalogin active、kos-shell active；未注入崩溃、未改 PAM/权限/配置。无凭据采集；账户与 home 路径已脱敏，原始未脱敏内容未落盘。

独立审查范围：本目录全部证据、T01 卡与索引状态；审查摘要/代理/问题与结论记录在 ../../reviews/T01.md。产物摘要见 SHA256SUMS。

[独立审查与关闭记录](../../reviews/T01.md)
