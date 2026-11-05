# Compatibility and manual transition / 兼容与手动过渡

Status (2026-11-04): the unpublished cross-identity profile copier and Calendar
first-launch finalizer have been withdrawn. Settings manages programs, not personal
profile migration. No real profile migration/uninstall was performed during this
change. Runtime/manual acceptance remains pending; new-ID signed releases and
reviewed runtime provisioning are still blockers. Historical development build
results are not evidence that the replacement is production-ready.

## Compatibility boundary

| Scenario | Contract |
| --- | --- |
| Native upgrade | Keep existing application/organization names and configuration/data paths; desktop ID changes do not rename profiles |
| Same-ID Flatpak update | Update the program and keep private data; reinstallation may reuse previously retained data |
| Native to Flatpak / old to new Flatpak ID | Separate identity, not an in-place update; no automatic discovery, copy or merge of old profiles |
| Normal uninstall | Remove only owned program files/refs, keeping personal data and shared runtimes |
| Future incompatible data formats | Document affected versions and manual actions; add necessary conversion in the app when needed, not a universal installer migration framework |

Calendar, Calculator and Weather use `org.nextks.calendar`,
`org.nextks.calculator` and `org.nextks.weather`. Their retired Flatpak identities
are `org.nextkde.Calendar`, `org.nextkde.Calculator` and `org.nextkde.Weather`.
Native/retired conflicts still block new deployment. There is no automatic
cross-channel replacement, EOL rebase or cross-step rollback. Keep a working old
installation until a released replacement, required runtime and an acceptable
data transition are ready. Removing the old program first can leave an availability
gap if replacement installation fails. ListenFree and KMusic identities are unchanged.

## 手动接续资料

跨身份首版不自动导入 Calculator 历史、Weather 城市/单位和外观偏好；新版需要重新设置，
旧资料保留。原生同路径升级不是必然空白；同 ID Flatpak 重装也可能继续使用已保留资料。
不扫描用户目录，不复制整棵 profile，不导入 portal 权限、凭据或宿主服务文件。

Calendar 复用现有 **Export iCalendar… / Import iCalendar…** 菜单交换 `.ics`。
这不是完整备份或完整 profile 迁移：

- 导出仅序列化日历内容，不打包独立 `metadata.json` 中的分类、列表和分组。
- 不搬运图片；旧绝对图片 URL 在新沙箱中可能无法访问。
- 默认导入跳过已有 UID，不提供通用合并；重复、关联、提醒等具体表现仍须人工核对。
- 沙箱 portal 选文件后，PIM 服务能否完整读取尚待人工验收，不能称路径已验证可用。

需要完整组织结构、图片或宿主 widget 联动时，先保留旧安装，不建议直接复制整个 profile，
也不能只复制 `calendar.ics` 就声称完整迁移。源码已提供有限 ICS 交换，不代表沙箱完整迁移已交付。

**提醒交接是独立事项。** 导入不代表新版已获后台权限或已经接管提醒。人工确认新身份的
Background portal 权限和提醒运行情况，再确认旧服务归属及退出方式；两套服务可能重复提醒，
卸旧程序又可能停止旧提醒。Settings 不自动停止/杀死旧服务，尤其不动宿主共享服务。
桌面现有只读摘要联动：唯一明确安装的 Calendar/Weather 提供固定路径、带身份与版本的摘要；桌面只读取摘要，不迁移 profile 或接管提醒。旧包不支持契约、缺失/过期摘要、歧义安装均明确显示状态。源码与 native 编译不代表沙箱联动已人工验收。见 [组件契约与人工验收](WidgetIntegration.md)。

English: Calendar's existing ICS exchange does not package metadata or images,
is not full-profile migration, and does not transfer background permissions or
hand over reminders. Sandbox file access and actual reminders require manual
acceptance. Keep the old installation when full fidelity or host widgets are needed.

## Program removal and source-version cleanup

These are explicit user commands, not operations executed during development:

```sh
kos-apps status --app calendar
# Only after reviewing the old install and preparing an acceptable replacement:
kos-apps remove-retired --app calendar
# Separate signed installation; failure does not reinstall the old program:
kos-apps install --app calendar
```

Mutations require terminal confirmation or explicit `--yes`. `remove-retired`
accepts only an unambiguous, exact old user ref, checks running apps/helpers and
audits a single uninstall at both Flatpak ready stages. It preserves data/shared
runtimes and rereads inventory. System/multiple refs stay with their external
manager. There is no `migration-plan`, `migrate`, source selection or automatic
profile finalization. Uninstall confirmation does not promise reminder handover.

原生/发行版/Nix/历史 core 的程序由原安装方式处理。不要猜路径删除 `/usr` 下文件、
整个 core 或共享 PIM 服务。源码移动不等于历史安装文件已经卸载，本轮不提供通用历史清理器。

Source cleanup remains offline, ownership-bound and explicit:

```sh
tools/install-apps.sh --backend=source --app calculator cleanup-plan
tools/install-apps.sh --backend=source --app calculator prune --yes
# Standalone repository:
python3 packaging/installer.py --app calculator cleanup-plan
python3 packaging/installer.py --app calculator prune --yes
```

Keep current and the most recent other owned revision. Unknown directories,
personal data, backups, logs and shared runtimes are not pruned. A durable reduced
inventory precedes deletion; an interrupted prune retains its recovery journal.
No automatic cleanup runs after an update. Settings provides the same explicit
preview/confirmation. This program transaction recovery is not a profile migrator.

## Unfinished development migration / 未完成开发迁移

The withdrawn local implementation was never released and was not run on real
profiles during development. It may nevertheless have been used manually in a
developer environment; do not assume there are no artifacts and delete them.

若人工环境存在 `$XDG_DATA_HOME/nextkde-apps/migrations/<app>/` 中的 `active.json`、
事务备份目录/编号 `.data`、`complete.json`，或目标中的 `.migration-*`、
`migration-pending.json`、`migration-calendar.ics`、`migration-finalize.json`、
`migration-result.json`，请保留来源、journal、备份及目标后续修改，关闭相关写者后交人工核对。
旧 journal 的 files 数组按顺序对应编号备份，含路径/大小/散列；这些是私有恢复资料，不是可直接导入包。
当前不再自动续传、最终化、合并或清理它们。

Calendar 在打开可写 PimStore 前发现 `migration-pending.json` 或
`migration-finalize.json`（含符号链接）即拒绝启动，避免将半份资料当正常 profile。
这只是遗留状态阻挡，不是迁移完整性校验。不要仅删除标记绕过保护，不盲目用备份覆盖新编辑。
无法确认完整性时，保留全部副本并继续使用确认完好的旧安装。诊断输出需
`QT_FORCE_STDERR_LOGGING=1`；不要为收集输出自动启动应用。

See [manual acceptance](ProfileMigrationAcceptance.md). No runtime result is
accepted merely because code compiles or documentation exists.
