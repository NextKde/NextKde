# Independent applications / 独立应用边界

2026-11-05：旧 Calendar／Calculator／Weather 与新版是不同应用，允许 breaking change。
新版仅使用 `org.nextks.calendar`、`org.nextks.calculator`、`org.nextks.weather` 的
独立配置、资料、状态和服务身份，不接管旧安装、不继承或复制旧 profile。
命令仍为 kos-calendar／kos-calculator／kos-weather，真实同名入口冲突仍须人工处理。
ListenFree、KMusic 不变。

Settings 和 kos-apps 只管理当前身份，不提供 remove-retired、迁移或兼容说明按钮。
正常更新／卸载保留当前身份资料；同 ID 重装可以复用这些资料，不等于读取旧版资料。
旧 ID 或旧源码目录存在本身不是新版库存或升级路径。

旧版程序和个人资料仅由 core 仓库 `tools/maintenance/purge-legacy-apps.py` 人工显式清理。
默认预览；--apply 要求破坏性确认（非交互须 --yes），会同时删除列明的旧个人资料。
脚本只处理确权旧 source 安装、唯一旧 user Flatpak ref 和固定旧专有目录。
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
