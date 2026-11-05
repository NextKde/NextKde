# Independent apps: compatibility and switching / 独立应用兼容与切换

## 中文

Calendar、Calculator、Weather 现使用 `org.nextks.calendar`、`org.nextks.calculator`、`org.nextks.weather`。原生版和不同 Flatpak ID 是不同安装身份，不是普通的原地升级。

- 同路径的原生升级保留已有资料位置；同 Flatpak ID 更新保留私有资料。重新安装相同 ID 也可能使用以前保留的资料，并非必然空白。
- 跨身份安装不自动读取、复制或合并旧资料。Settings 只管理程序，正常卸载不删除个人资料。
- Calculator 历史、Weather 城市/单位、外观偏好在新身份下需要重新设置。旧资料不自动删除。
- 在正式新包、依赖和资料接续方式准备好之前，保留旧安装。当前没有完整跨身份迁移工具；需要完整资料保真的用户先不要切换。

### Calendar

可使用应用现有的 Export iCalendar… / Import iCalendar… 文件菜单交换 `.ics`。这是有限的日历交换，不是完整备份或完整迁移：

- 不打包独立 `metadata.json` 的列表、分类和分组。
- 不搬运图片；旧绝对路径在新沙箱里可能不可访问。
- 默认导入按 UID 跳过已有事项，不提供通用合并。
- 沙箱文件选择与后台服务读取的完整路径尚待人工验收，不承诺可用性。

导入不代表提醒接管成功。新版需要单独的后台权限及人工确认提醒；旧服务继续运行可能重复提醒，卸旧程序也可能使旧提醒停止。不要自动停止共享服务。桌面只读联动要求应用提供新版身份摘要；未安装、缺摘要、过期或多安装冲突会分别提示，不自动读取另一身份的资料。当前沙箱联动仍待人工验收。

不要直接复制整套 profile 或只复制 `calendar.ics` 并认为迁移完整。需要完整组织结构、图片或宿主 widget 联动时，应继续保留旧安装。

### 旧程序与旧版本

- Settings 的“移除旧程序”仅处理唯一、明确的旧 user Flatpak ref，不装新版、不迁移资料、不删共享 runtime；系统级或歧义安装交原管理器。
- 原生/发行版/Nix/历史 core 安装按原安装方式处理；不要猜路径删除 `/usr` 文件、整个 core 或共享服务。
- 源码安装的显式旧版本清理只清安装器确权版本，保留 current 与一个回退版本，不自动触发。
- 没有一键替换和跨步骤自动回滚。冲突解决后安装仍可能失败，出现暂时无可用程序的空档。

### 未完成的开发迁移

旧开发版曾提供未发布的 profile 复制功能，目前已撤除。如果环境里有 `migration-pending.json`、`migration-finalize.json`、备份、journal 或 staging，请保留来源及全部产物，关闭相关应用后交人工核对恢复。Calendar 应拒绝打开带未完成标记的资料。不要单纯删标记绕过保护，也不要覆盖已有的新资料。

## English

The new IDs are `org.nextks.calendar`, `org.nextks.calculator` and `org.nextks.weather`. Native installs and distinct Flatpak IDs are separate identities, not an ordinary in-place update.

- Native upgrades retain existing storage paths; same-ID Flatpak updates keep private data. Reinstallation may reuse data previously kept for that ID.
- Cross-identity installation does not import, copy or merge old profiles. Settings manages programs; normal uninstall keeps personal data. Reconfigure Calculator history expectations, Weather locations/units and appearance in the new identity.
- Keep the old installation until a released replacement, dependencies and an acceptable data transition are ready. No complete profile migration is provided.
- Calendar's existing Export iCalendar… / Import iCalendar… exchanges ICS only. It does not package lists/categories/groups from metadata.json or image files. Old absolute image URLs may be inaccessible in the sandbox. Existing UIDs are skipped by default, not merged. Sandbox file selection and service access still require manual acceptance.
- Import does not hand over reminders. Confirm the new Background portal permission and actual reminders manually; concurrent old services may duplicate notifications, and removing the old program may stop old reminders. Host widgets consume identity-bound read-only summaries from compatible applications, not whole profiles. Missing, stale, unsupported or ambiguous sources are explicit; sandbox integration still requires manual acceptance. Keep the old installation if complete metadata, images or widget integration are required.
- Explicit retired-ref removal only removes an unambiguous old user Flatpak program, not its data or shared runtimes, and does not install a replacement. System/ambiguous refs and native/distro/Nix/historical core files stay with their original manager. Do not guess paths to delete shared components.
- Source-version cleanup is explicit and ownership-bound; current and one rollback version are retained. There is no automatic cross-step rollback; replacement installation may fail after old-program removal.
- Preserve unfinished development migration markers (`migration-pending.json`, `migration-finalize.json`), journals, backups and staging for manual recovery. Do not delete markers merely to bypass Calendar's guard or overwrite later edits.

No renamed signed release is available yet; runtime trust review and runtime/manual acceptance remain pending. Do not remove a working installation based on a promise that the replacement is already production-ready.
