# Independent applications / 独立应用边界

**安装边界：原生版与 Flatpak 版允许共存。** Settings 的“安装／打开／卸载”只看当前
Flatpak 库存；原生程序、桌面入口、源码安装记录均不得阻止查询、计划或安装。
旧原生清理是独立可选操作，绝不是安装 Flatpak 的前置条件。
卸载入口：点击应用图标或名称展开详情 →“卸载”→确认；仅删除选中的用户级 Flatpak，
保留个人资料、配置和原生应用。系统级或多份 Flatpak 须由对应管理器明确处理。

2026-11-05：旧 Calendar／Calculator／Weather 与新版是不同应用，允许 breaking change。
新版仅使用 `org.nextks.calendar`、`org.nextks.calculator`、`org.nextks.weather` 的
独立配置、资料、状态和服务身份，不接管旧安装、不继承或复制旧 profile。
源码安装的命令仍为 kos-calendar／kos-calculator／kos-weather；源码安装器的同名入口保护
仅约束原生文件写入，不适用于 Flatpak 安装。
ListenFree、KMusic 的应用身份不变；五款应用均只通过 Flatpak 管理。
原生 KMusic 不再被视为已安装的 Flatpak，也不再由 Settings 直接启动。
清理脚本额外支持旧原生 ListenFree 程序。

Settings 和 kos-apps 只管理当前身份，不提供 remove-retired、迁移或兼容说明按钮。
正常更新／卸载保留当前身份资料；同 ID 重装可以复用这些资料，不等于读取旧版资料。
旧 ID 或旧源码目录存在本身不是新版库存或升级路径。

旧版程序和个人资料仅由 core 仓库 `tools/maintenance/purge-legacy-apps.py` 人工显式清理。
默认预览；--apply 必须在终端逐应用确认，确认前列出该应用的目录与文件。
选择 all 也必须每个应用分别确认；回车跳过该应用，Ctrl+C 结束后续处理。
不再支持 --yes 或非交互删除；会同时删除列明的旧个人资料。
例外：`--app listenfree` 只清理确权原生程序和入口，保留 Flatpak、配置、音乐库和下载。
`all` 包含它，须另行输入 `DELETE listenfree PROGRAMS` 确认。
历史 `~/.local/opt/listenfree` 包须符合文件白名单及原启动入口；未知内容会阻止清理。
脚本只处理确权旧原生安装和固定旧专有目录，不卸载任何 Flatpak，
不删除任何 ~/.var/app 资料。未发布过的开发 ID 不构成用户迁移流程。
发行版／Nix／历史 core 的未确权文件只报告保留，由原管理器处理；不删整个 core、
共享 runtime、共享 KosApplications.conf 或 core Weather 状态。不杀进程、不自动停止服务。
新版目录受保护；未知所有权、替换链接、写者或安装歧义会拒绝。
部分失败可能已经完成部分删除，不承诺原子回滚或全机清理。

Calendar 现有 ICS 导入／导出是可选内容交换，不是完整 profile 迁移或本轮交付门禁，
不打包 metadata、图片或后台权限，不自动交接提醒。旧迁移 journals／备份不被搜索、
恢复或清除。宿主 widget 只消费新身份的当前摘要契约。

English: the old and new apps are distinct products. Native storage and Qt
preferences are isolated under the new identities; Calendar uses
org.nextks.calendar.Pim, and Weather only uses its bundled backend. No automatic
adoption, profile migration or old-data readback requirement remains. Ordinary
current-ID updates/uninstalls preserve current data. Explicit legacy purge is a
separate, irreversible human action, never an installation side effect. Unproven
system/core ownership and shared data are retained and reported, not guessed.
Compilation does not establish runtime acceptance or authorize publication.

Full current paths, cleanup commands/limits and manual acceptance:
https://github.com/NextKde/NextKde/blob/main/docs/app-store/ProfileMigration.md
