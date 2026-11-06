# Separate application identities and explicit legacy cleanup / 新旧应用边界与旧版清理

Current contract, 2026-11-05: old and new Calendar, Calculator and Weather are
**different applications**. Breaking change is intentional. There is no old-profile
adoption, cross-identity copy/merge, old ownership upgrade or old bus alias.
ListenFree and KMusic are unchanged. Historical compatibility results are not
acceptance of this boundary. No legacy purge has been executed during development.

## Current identities and paths

| Application | Retired Flatpak ID | Current ID |
| --- | --- | --- |
| Calendar | `org.nextkde.Calendar` | `org.nextks.calendar` |
| Calculator | `org.nextkde.Calculator` | `org.nextks.calculator` |
| Weather | `org.nextkde.Weather` | `org.nextks.weather` |

Commands remain `kos-calendar`, `kos-calculator`, `kos-weather`. Current desktop
files use the current ID. A real occupied command/desktop entry is a conflict,
not permission to overwrite it. Merely retaining an old Flatpak ID or old short-key
source directory does not make it part of the new application's inventory.

Native default locations (XDG defaults apply when variables are unset):

| Content | Current location |
| --- | --- |
| Source program | `$XDG_DATA_HOME/nextkde-apps/org.nextks.<app>/` |
| Source installer state | `$XDG_STATE_HOME/nextkde-apps/org.nextks.<app>/` |
| Qt preferences / Calculator history | `$XDG_CONFIG_HOME/NextKde/org.nextks.<app>.conf` |
| Calendar business data and summary | `$XDG_DATA_HOME/org.nextks.calendar/pim/` |
| Calendar service name, native and sandbox | `org.nextks.calendar.Pim` |
| Weather state and summary | `$XDG_STATE_HOME/org.nextks.weather/standalone-backend/` |
| Weather runtime socket | `$XDG_RUNTIME_DIR/org.nextks.weather-<uid>/weather.sock` |

Calendar's existing D-Bus *interface* name is unchanged; it does not register the
retired service name. Explicit native `KOS_PIM_STORAGE_DIR` remains available but
custom profiles are outside widget integration. Weather only uses its own bundled
backend, ignoring `KOS_DATA_SOCKET` in both native and sandbox builds.

Flatpak profiles are under the exact new ID's `~/.var/app/` directory. Calendar
uses sandbox GenericDataLocation/kos/pim; Weather uses
GenericDataLocation/state/quickshell/kos-weather/standalone-backend and runtime
`$XDG_RUNTIME_DIR/app/org.nextks.weather/backend/weather.sock`. No old-ID profile
is searched. Normal **current-ID** update/uninstall keeps that ID's data; same-ID
reinstall can reuse it. That is not old-to-new migration.

## Explicit legacy purge

The tool is maintained in the NextKde core repository as
[`tools/purge-legacy-apps.py`](../../tools/purge-legacy-apps.py). Run it as the
owning desktop user, never root or sudo. These are commands for a human to review
and execute, not actions performed by Settings or during this implementation:

```sh
# Read-only inventory; inspect every DELETE / UNINSTALL / RETAINED / BLOCKED line.
python3 tools/purge-legacy-apps.py --app calendar
# Only after making any desired backup and closing applications/helpers:
python3 tools/purge-legacy-apps.py --app calendar --apply
# Select calendar, calculator, weather or all. Noninteractive destructive consent:
python3 tools/purge-legacy-apps.py --app all --apply --yes
```

`--apply` requires typing `DELETE LEGACY APPS AND DATA` in a terminal unless
`--yes` is supplied. **Deletion includes personal data and is irreversible.**
The tool does not install a replacement, migrate, back up or restore data.

It only deletes:

- Old short-key source roots/state after exact retired appId/installer ownership,
  revision, known installed-file and activation-link checks. Calendar includes
  owned old Todo artifacts. Replaced links, unknown files or pending transactions
  block application; missing owned activation links can be skipped on retry.
- One unambiguous exact old **user** Flatpak app ref using Flatpak itself, with
  `--no-related` and without runtime autoremove or `--delete-data`; it then removes
  the separately listed exact old-ID private directory.
- Fixed old native private locations: `NextKde/kos-<app>.conf` and corresponding
  cache, Calendar's `$XDG_DATA_HOME/kos/pim` and old Todo settings/cache, Weather's
  `$XDG_STATE_HOME/quickshell/kos-weather/standalone-backend`.

It does not guess ownership of plain historical core/distro/Nix binaries or delete
`/usr`, `/usr/local`, the whole core, shared runtimes, ListenFree or KMusic. Such
candidates are `RETAINED`, requiring their original manager. Shared
`NextKde/KosApplications.conf` and core Weather state are kept because they are
not exclusively owned by these three apps. Non-default historical profiles,
backups and withdrawn development-migration journals are not searched or deleted.
Do not claim a full-machine cleanup when retained items remain.

System/custom-installation or multiple old Flatpak refs, unavailable inventory,
unsafe ancestors/ownership, symlinked data roots, special files, writable-by-others
nodes, overlapping paths or running writers cause refusal. Symlinks inside a
listed private tree are unlinked, not traversed. Source locks, inventory and file
snapshots are checked again before mutation; new identity paths are protected.
Flatpak list output may abbreviate commits even with `active:full`; for retired IDs,
the tool resolves the full commit with installation-scoped `info --show-commit`
and rejects a mismatch before uninstalling. Unrelated apps are never uninstalled.
Same command names mean the tool can conservatively require closing a new app too.

This is **not an atomic transaction**. Flatpak uninstall or a later deletion can
fail after earlier actions completed; external auto-start or concurrent changes
must be stopped manually. A changed tree is refused, not silently rescanned and
accepted. Incomplete source roots/orphan state need manual ownership review;
retry does not promise recovery from every partial failure. No processes are
killed and no services are automatically stopped. Default XDG layouts are the
supported scope; symlinked HOME/XDG or custom Flatpak environment overrides are
refused rather than guessed.

Exit codes: `0` preview or completed listed cleanup; `2` blocked/error (an apply
may be partial); `3` listed cleanup completed with external candidates retained;
`130` terminal confirmation cancelled. Preview never means cleanup completed.
Review printed retained items even when preview returns zero.

## Calendar exchange is optional, not a delivery gate

New applications start with their own defaults. Calculator history, Weather
locations/units and appearance are not inherited. No old-profile readback is
required. Calendar's existing Export/Import iCalendar menus remain available for
human-selected ICS exchange, not a full-profile migration: metadata groups/lists,
images and background permissions are not packaged, and reminder handover is not
automatic. Sandbox file access and notifications still require manual acceptance.
Old migration markers/journals stay in old locations; the new app neither opens
nor finalizes them. Preserve those artifacts for manual recovery if needed.

## Current source-version cleanup

Current-ID program revision cleanup is separate from legacy purge:

```sh
tools/install-apps.sh --backend=source --app calculator cleanup-plan
tools/install-apps.sh --backend=source --app calculator prune --yes
# In kos-apps:
python3 packaging/installer.py --app calculator cleanup-plan
python3 packaging/installer.py --app calculator prune --yes
```

It keeps current and the most recent other owned revision, refuses unknown
contents and preserves personal data/logs. Program journal recovery and installed
ownership checks remain; they are not a profile migration framework.

See [manual acceptance](ProfileMigrationAcceptance.md) and
[widget integration](WidgetIntegration.md). Compilation is not runtime acceptance;
no new signed release or publication is implied by these source edits.
