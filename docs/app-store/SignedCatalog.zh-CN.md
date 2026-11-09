# 可更新的应用目录

[English](SignedCatalog.md)

应用名单与安装后端分开。官方投稿仓库为 [NextKde/appCatalog](https://github.com/NextKde/appCatalog)。
应用包和目录都必须通过 GitHub 的正式稳定 Release 发布；不接受 raw URL、脚本安装命令、其他托管平台或任意下载地址。

## 投稿、运行库与多语言

开发者在自己的 GitHub Release 发布安装包和带 SHA-256 的发行清单，再向 appCatalog 提交条目。维护者审核并发布签名目录后，客户端刷新即可发现；普通应用新版不需要修改目录。详见[投稿说明](https://github.com/NextKde/appCatalog/blob/main/README.zh-CN.md)、[发行协议](https://github.com/NextKde/appCatalog/blob/main/RELEASE-CONTRACT.zh-CN.md)、[Qt runtime 指南](https://github.com/NextKde/appCatalog/blob/main/docs/QtRuntime.zh-CN.md)与[多语言约定](https://github.com/NextKde/appCatalog/blob/main/docs/Localization.zh-CN.md)。

Qt 应用推荐同分支同架构的 `org.kde.Platform` / `org.kde.Sdk`，现有 kos-apps 使用 6.11。应用包来自 GitHub；共享运行库由独立批准的 Flathub runtime 源提供，不要求应用上架 Flathub，也不使用宿主 Qt 代替。

Settings 和种子目录支持英文、简体中文、巴西葡语，目录缺失翻译时回退英文；后台通知跟随系统语言。应用自身界面翻译需要打进应用，不能由目录翻译替代。

## 代码职责

- `platform/app-catalog`：格式无关的来源配置、目录验签、原子缓存、序号防回退、有效期、应用身份及安装来源记录。
- `IndependentAppRegistry`：Flatpak 适配层，从目录读应用；Settings 展示同一目录。
- `FlatpakRelease`：从目录指定的 GitHub owner/repository 获取 latest stable `vX.Y.Z`，解析 schema 2 发行清单。
- `FlatpakApps`：唯一当前安装后端，检查包 SHA-256、元数据、ref/commit、依赖计划、版本和安装归属。未来格式通过目录 `format` 分发到新的编译后端；不从目录执行命令。
- `kos-app-update-agent`：用户会话后台元数据检查、结果持久化、通知去重；不自动下载包或安装。
- `ServicesSettingsPage`：应用来源管理、手动检查全部更新、自动检查/通知开关、更新标记。

首个目录没有发布前，程序使用随核心发行的 bootstrap 目录。它的信任来自核心分发，不能被网络错误替换为任意未签名列表。已有远程目录缓存损坏时不得回退 bootstrap 重置历史。目录有效期失效后保留展示，但不再授权安装/更新。

初始目录和公钥是发布时的种子，不是运行中的应用白名单；之后新增/下架应用只修改并发布 appCatalog。初始五款保留既有开发者公钥；新投稿可以不配置 `publisher`。

## 信任边界

目录必须通过已配置完整主指纹的 OpenPGP 签名。官方 bootstrap 当前沿用核心已有发布公钥；仓库仅包含公钥，不包含私钥。第三方目录需要用户输入完整指纹、公钥文件并明确同意信任。单靠下载到的公钥不自动建立信任。

应用包的 SHA-256 来自批准的 GitHub 仓库发布的发行清单。开发者签名可选；目录指定 `publisher` 时，必须验证清单和包内 commit 签名，失败不能降级。未配置时信任 GitHub 仓库账户安全及 HTTPS；若攻击者控制仓库并同时更换包和摘要，不能靠 SHA-256 防住。

安装结果记录实际 commit、架构、来源、origin、包摘要和原目录条目。无开发者签名的已有安装只有匹配本客户端记录才允许更新，不接管未知安装。旧的签名安装仍核对发布者 commit 签名。运行库继续执行独立的固定来源/公钥策略。

计划绑定目录条目摘要；确认及部署前重新核对授权、包摘要、实际元数据与安装快照。事务执行有跨进程锁。下架或删除来源不卸载应用；保留记录只用于展示和原安装管理，不用于重新授权安装/更新。跨来源相同 appId 冲突不得静默覆盖。

目录密钥自动轮换尚未实现；更换第三方根密钥使用新的来源 ID 并重新明确建立信任。同一根密钥可以重新添加已移除来源，不丢弃保留的回退保护历史。

## 自动更新行为

用户会话自启动 updater，Settings 启动时也尝试唤起同一个单实例。登录后延迟约 2–4 分钟；正常每 6 小时检查，失败后约 1 小时重试，另加随机偏移。只检查目录中有效、已安装、可管理的应用。手动入口可立即触发一轮。

检查结果在 `XDG_STATE_HOME/kos-settings/app-catalog` 下保存，Settings 只复用与当前目录条目及安装快照匹配的结果。通知按 appId + 版本 + commit 去重，桌面通知服务确认接收后才记为已通知。点击通知打开“应用与服务”。通知不代表已安装更新。

当前自动检查没有计费网络识别；关闭自动检查后仍可手动检查。普通离线/限流错误保留到状态中，不弹周期性错误通知。各应用发现请求串行执行，尚未引入跨应用 GitHub ETag 缓存。

来源配置在 `XDG_CONFIG_HOME/kos-settings/app-sources.json`。添加第三方源使用 GitHub `owner/repository`，公钥必须是导出的二进制 `.gpg` 文件。来源仓库 Release 附件固定为 `catalog.json`、`catalog.json.sig`。

## 发布与验收

首次正式目录发布需要维护者配置 `catalog-release` environment 和与客户端公钥对应的签名 secret。发布序号必须递增，默认 30 天有效期到期前需重新签发，操作见[维护者说明](https://github.com/NextKde/appCatalog/blob/main/MAINTAINING.md)。仓库存在或条目已合并不等于客户端已经验收，也不等于应用已发布可安装包。

只在开发虚拟机或 CI 构建和测试，不在本机启动 Shell、图形验证或运行测试。目录用例位于 `apps/settings/tests/store/catalog.cpp`，同目录包含 Flatpak 发行校验测试。发布前应覆盖错误/缺失签名、回退和过期、SHA-256 不匹配、开发者签名失败、第三方源增删及冲突、无签名包安装记录、并发事务，以及关闭 Settings 后的自动检查和通知去重。真实包部署与桌面通知还需虚拟机验收。
