# App/widget integration — contract and manual acceptance

Native/Flatpak coexistence is allowed by the Settings application store. Widget
source selection is a separate concern: any ambiguity described below governs
which summary or app a widget uses, never permission to install a Flatpak.

Current boundary: 2026-11-05, new identities and default native paths only.
Production compilation is not runtime or sandbox acceptance. No applications,
graphical sessions or automated tests were run for this boundary change. Earlier
runtime evidence describes earlier revisions. Current signed releases and runtime
availability remain separate delivery concerns.

## Behavior

- Calendar's date grid does not depend on app installation. Personal events/todos
  require an unambiguous installed desktop entry and its matching summary.
- With no Weather app, the shared WeatherService uses core weather. With a unique
  app it uses only that app's summary, never core data disguised as app data.
- Missing/invalid/unsupported data is not an empty calendar or completed todo list.
  Valid old data is explicitly cached/stale. Source changes clear old contents.
- Clicks use an identity token, recheck the installation and launch its exact entry;
  stale installation tokens fail instead of opening a different identity. This is
  launcher acceptance, not proof that the app processed the requested item.
- Missing apps lead to Settings with the app selected; no automatic installation,
  removal, migration, process termination or reminder handover occurs.
- Weather is not made a new persistent daemon. Open the app to update its summary;
  its collection timestamp is distinct from summary publication time.

## Supported scope

Widget integration supports standard installations using default application data
paths. Native apps and the platform must share the desktop session's XDG data/state
environment; Flatpak data uses the exact app identity's standard private directory.
Configured Flatpak installation locations are supported separately from custom
application data profiles.

A non-empty native `KOS_PIM_STORAGE_DIR` visible to the platform returns
unsupported. Calendar v2 summaries also identify their storage mode/path; custom
or mismatched profiles are rejected. New Weather always uses its bundled private
backend and ignores `KOS_DATA_SOCKET` in both native and Flatpak builds.

This is not detection of arbitrary launch environments. An override set only in
an app's wrapper, desktop command or separately launched process may be invisible
to the platform; an earlier default-path summary may still exist. Such launches,
including app-only XDG overrides, are outside the supported integration scope:
correct source matching is not guaranteed, nor is an unsupported warning promised.
No process scanning, profile registry, directory search, copying or migration is
added to cover them. Use a standard launch with default data paths for acceptance.

## Fixed read-only summary interface

Calendar publishes `widget-snapshot.json` in
GenericDataLocation/org.nextks.calendar/pim (native), or
GenericDataLocation/kos/pim (Flatpak).
Weather publishes `widget-snapshot.json` in its standalone backend directory:
`$XDG_STATE_HOME/org.nextks.weather/standalone-backend` (native; XDG_STATE_HOME
falls back to `~/.local/state`), or
GenericDataLocation/state/quickshell/kos-weather/standalone-backend (Flatpak).
Native Weather uses `$XDG_RUNTIME_DIR/org.nextks.weather-<uid>/weather.sock`
(with the system temporary directory as runtime-root fallback). Flatpak uses
`$XDG_RUNTIME_DIR/app/org.nextks.weather/backend/weather.sock`.
Neither app reads or migrates the old native application's profile.
Host readers map the latter and Calendar to the exact app's
`~/.var/app/org.nextks.<app>/data/` directory. No additional sandbox filesystem
permission is requested; no ICS, metadata.json, private state.json or preferences
are read. Unsupported/custom paths are not searched or copied.

`widgetContractVersion=2`, exact appId, channel (native/flatpak), storageMode and
generatedAt bind the data. Calendar uses payload schemaVersion=1 plus the required
v2 envelope, storagePath/timeZone and its bounded event/todo subset.
Weather wraps the current schemaVersion=1 weather fields. Writes are atomic.
The reader accepts only current-user regular files, walks without following
symlinks, limits the file to 512 KiB, JSON depth/array/object/string sizes and
validates expected field types. Unsupported layouts fail closed.

Weather validation follows the standalone Go producer's fields: required current
readings include finite temperature/apparent temperature, humidity, wind, integer
weather code, boolean day/night and a valid ISO time; location requires ID/name
and bounded coordinates. Saved locations cannot repeat IDs. Hourly rows require
all core fields and precipitation probability (at most 48 rows); daily rows
require ISO dates in increasing order, ordered high/low temperatures and
precipitation probability (at most seven rows). Optional sunrise/sunset may be
absent or empty at polar locations. Optional extension readings and air quality
are type/range checked when present; these fields are optional in the current schema.
Timestamps must be non-negative safe integers, collection cannot be in the
future, and expiry cannot precede collection. No current reading returns missing,
not ready. A refresh-error snapshot with otherwise valid readings is cached/stale.
This validates shape and selected ranges, not provider truth, forecast completeness
or hourly monotonicity across daylight-saving transitions. Core weather's direct
JSONL path does not pass through this independent-app validator.
Calendar becomes stale after 12 minutes or a different date/timezone; Weather
uses publication age plus actual fetchedAt/staleAt (at most two hours fresh).
A timestamp over one minute in the future is invalid. Only new org.nextks.*
identities and the current widget contract are supported. Old native Calendar
summaries and retired Flatpak identities are not consumed.

Desktop detection enumerates fixed IDs in standard XDG application directories
and Flatpak exports, deduplicating canonical files. Read-only libflatpak inventory
includes the user installation and all configured system installations (including
custom paths), and every installed app branch/architecture for the fixed IDs.
Multiple refs or native/Flatpak coexistence are ambiguous even when only one ref
has a desktop export. Inventory failure is unavailable, never not-installed.
Inventory workers wait up to one second for the shared source-context lock,
off the GUI thread, so concurrent Calendar/Weather polls can complete in turn.
Longer source/operation contention still returns unknown installation state;
the wait does not bypass the context lock or the existing inspection deadline.
An installed ref without a usable export is unavailable; an orphan export cannot
be used as installation evidence. The unique export must resolve to the unique
current ref's deployment export. Its installation/scope/branch/arch/commit/origin
are included in the source token so updates invalidate earlier click tokens.
Unregistered arbitrary directories are not discovered or searched; add them to
Flatpak's normal configured installation mechanism rather than expecting home
scanning. This implementation still requires manual multi-install/ref acceptance.

## IPC

`application.widget-snapshot` accepts `{app: calendar|weather}` and returns state,
message, installed/sourceToken when uniquely resolved, and payload only when
validated. States: not-installed, ambiguous, unavailable, missing, invalid,
unsupported, ready, stale. Work is off the main thread; same-key reads coalesce.
Each app has at most one inspection worker shared by reads and open preflight
(two workers total for the two fixed keys). A conflicting preflight returns
widget-query-busy. The existing reply queue remains bounded (32 per peer, 256
across operations). A 15-second monotonic inspection deadline replies with
widget-query-timeout, requests libflatpak cancellation and discards any late
result. Its task slot remains occupied until the worker actually exits; further
requests fail fast instead of enqueueing replacement workers. Opening-requester
disconnect requests cancellation; shared reads retain their original deadline,
and disconnected listeners are removed by platform transport handling.

Cancellation is cooperative: directory/file syscalls and some library work may
not stop promptly. This is a bounded response/admission policy, not a hard kill
or a guarantee of prompt worker/platform shutdown. A stalled worker can occupy
its one slot indefinitely, without reporting absent/ready or launching an app.
The response timer depends on a responsive platform event loop. KIO launch time
is separate from the inspection deadline.

`application.widget-open` accepts the same app plus sourceToken and options:
Calendar date (ISO), view (fixed enum), item; Weather location. Only these fields
are allowed, strings are bounded and control characters rejected. The exported
entry's wrapper is preserved; KDE launch handling receives quoted fixed options.
No caller-provided executable/path/command is accepted. Errors include
invalid-widget-app/options, source-changed, busy and application-launch-failed.
Immediately before and after KService loading, the platform rechecks canonical
entry resolution, bounded regular-file contents and SHA256. For Flatpak it also
checks installation/app/<id>/current, the inspected branch's active deployment,
and that deployment's desktop export against the inspected canonical entry.
Unknown layouts or changes reject with source-changed; wrapper options are not
rebuilt from a different installation. Final local checks also reject an expired
preflight before launching.

This narrows, but cannot eliminate, an external update/uninstall race after the
last check: there is no cross-manager transaction/lock through KIO or Flatpak
activation. Executable bytes and already-running app identity are not pinned.
Local checks/KService loading run on the platform thread and filesystem stalls
can delay the event loop/deadline response; no hard syscall deadline is claimed.

Shell polling is 30 seconds, one in-flight read per app, with reconnect/catalog
invalidation and discarded late generations. Per-app read revisions also discard
polls invalidated by a launch result without overlapping replacement reads.
Launch responses for a superseded source do not reset the newly displayed source.
Core weather snapshot reads are serialized/coalesced and invalidated on source or
data-transport changes. Calendar/reminder widgets retain their last validated
summary in memory through transient inspection failures, reconnects and catalog
reloads, explicitly marked as cached. A confirmed different source, absent or
ambiguous installation, missing/invalid summary or unsupported profile clears it.
Without a validated summary, reminder widgets show the source status rather than
a zero count or completed-tasks message, including at the smallest size. Calendar's
date grid stays independent of the app, with source status also shown on narrow cards.

Lock-screen publication uses the fixed `lockscreen.weather-publish` operation,
not state staging or generic file.copy. The shell coalesces property changes and
sends six bounded display strings; the platform generates escaped data-only QML.
It pins the existing current-user lockscreen directory, checks LockScreen.qml,
writes a sibling temporary file and commits with renameat. It never creates the
theme directory. A removed/replaced directory cannot redirect that commit or be
recreated by this operation. A theme removed after the final check may still
leave a feed in a surviving directory; this is not a full uninstall transaction.

Publication runs synchronously in platform request-dispatch order with no detached
copy worker, so a later processed publication cannot be overwritten by an older
worker finishing last. Client timeout does not undo an already committed write.
Local filesystem calls have no hard wall-clock deadline; a stalled filesystem can
block platform dispatch. Ordering is request arrival, not source age across
multiple independent shell instances. Old in-flight copies from a pre-upgrade
platform must finish/exit before manual acceptance of the new path. There is no
fallback to generic copying when the platform lacks the new capability.
Settings navigation is fixed to Calendar/Weather and scoped to KOS_SHELL_DIR;
the platform first connects to an existing window, otherwise attempts one spawn,
then waits up to 20 seconds for acknowledgement. Failed launch/navigation returns
settings-navigation-failed to the component. Success means the loaded QML root
accepted the destination, not that the page rendered or installation succeeded.
The app page requests a one-shot reveal after its target delegate/layout exists;
repeat navigation can reveal the same card again. Routine model refresh does not
continually reset scrolling. Selected is translated; viewport/layout visibility
still requires human acceptance, and no keyboard focus change is claimed.
Component feedback maps installation states and known launch errors to shared
English/Chinese/Brazilian Portuguese messages, translated at display time so a
language switch need not wait for polling. Detailed platform diagnostics stay in
the response records, rather than being used as untranslated UI copy.
Application launch guards remain held through KIO job destruction, rather than
being released after installation lookup. Inspect visible outcomes manually.

## Manual acceptance — all pending

Only use disposable user data. Do not prepare automation or fault-injection scripts.

| Scenario | Human check | Status |
| --- | --- | --- |
| No apps | Date grid remains; no retained PIM data; core weather; click selects Settings app, cancel installs nothing | Pending |
| Unique native/user/system Flatpak | Open app, edit data, wait for summary/poll; same-source dates/items/city; already-running window navigates | Pending; sandbox release blocked |
| First launch/closed Weather | Missing summary prompts opening; closed app cache is explicit, no hidden new background service | Pending |
| Old native/retired app | Not a current installation/source; no old summary contract or cross-identity fallback | Pending |
| Duplicate/hidden/broken exports | Explicit ambiguity/unavailable; no arbitrary target | Pending |
| Multiple refs/custom configured installations | Detect non-exported branches/architectures, user+system duplicates and native coexistence; refuse ambiguity. Unexported installed ref and failed inventory are unavailable, not absent | Pending |
| External uninstall/update/reinstall | Poll clears old data; clicking old token refuses changed entry | Pending |
| Missing/damaged/oversized/symlink/unreadable summary | Bounded failure, no false empty/ready, next valid summary heals | Pending |
| Wrong schema/field types/identity | Reject, no previous-source contents retained | Pending |
| Known custom native source | Visible Calendar storage override is unsupported; Weather ignores KOS_DATA_SOCKET and uses its bundled backend. App-only XDG wrapper environments are outside scope, not a promised detection case | Pending |
| Old/future time, suspend, midnight/timezone | Cache label, no false current-day empty success; correct current date | Pending |
| Disconnect/reconnect/late replies/double click | No stale overwrite, request pile-up or cross-identity fallback; visible errors | Pending |
| Core/app source switching | All WeatherService consumers agree; refresh doesn't mutate wrong backend | Pending |
| Lock screen invalidation | Old weather feed replaced by empty placeholders when unavailable/stale | Pending |
| Small/large/narrow cards | Status has reserved space, no overflow/obscured controls; usable click | Pending |
| Settings already open/starting | Select app without extra window; startup race/error visible | Pending |

Known pending runtime acceptance: installed-ref inventory, UI layout, sandbox
file/layout behavior, live language switching, Settings card reveal and the known
custom-source rejection described above. Settings acknowledgement remains
root acceptance, not rendered-page acknowledgement; no additional render-ack
protocol or arbitrary-environment ownership framework is planned in this scope.
Launch-entry revalidation and cooperative inventory cancellation/slot retention
still need manual acceptance. The residual post-check/external-manager race is
not eliminated. Lock-feed filesystem stalls, multi-shell ownership and full
uninstall coordination remain limits of its fixed publication operation, not
additional mechanisms to implement for this handoff. Compilation does not waive
manual acceptance or the separate signed-release/runtime-trust blockers.
