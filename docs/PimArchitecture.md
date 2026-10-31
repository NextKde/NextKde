# Local PIM architecture

Calendar and Reminders are two workspaces in one Qt Quick application, backed by one local service.
They share one `PimClient` instance and the same detail/edit popovers. `kos-todo` is a compatibility launcher that execs Calendar; it has no UI or separate data store.

```text
KOS Calendar: Calendar / Reminders
                  |
           Kos.Pim client
                  |
     org.nextkde.Kos.Pim1 (session D-Bus)
                  |
          kos-pim-service
      KCalendarCore MemoryCalendar
          /                 \
  calendar.ics          metadata.json
                          (task lists)
                  |
      org.freedesktop.Notifications
```

## Ownership and activation

`kos-pim-service` is the only writer. It owns events, todos, list metadata,
recurrence expansion, iCalendar import/export, and reminder scheduling.
The unified application uses the `Kos.Pim` client module and never open the storage
files directly. D-Bus activates the service on first use. A user systemd unit
is also installed, but installation does not enable proactive startup. Reminders
are processed while the service is running; they do not independently activate
it before a client first uses it.

The session-bus name and object are both versioned:

- service/interface: `org.nextkde.Kos.Pim1`
- object: `/Pim`
- change signal: `changed(qulonglong revision)`

Every call returns one compact JSON string. `snapshot()` follows
`shared/contracts/pim-v1.schema.json`; mutating calls return `ok`, `revision`,
and an optional `item`, or a stable error object. `eventsForRange()` expands
event recurrences for an inclusive date range of at most 730 days and caps one
response at 5,000 occurrences. The same range response expands dated VTODO
entries into `todoOccurrences`, allowing Calendar to render recurring tasks
without duplicating recurrence logic in QML.

`importHolidays(path)` adds VEVENT entries from an iCalendar file under
`calendarId: holidays`. It skips VTODO entries and existing UIDs, clears event
alarms and linked Todo metadata, and preserves recurrence/date information.
It cannot replace the existing calendar. The existing `importIcalendar(path,
replaceExisting)` method keeps its behavior.

### Managed holiday calendars

Snapshots optionally expose `holidaySources` (the built-in region catalog) and
`holidayCalendars` (only sources the user has added). The metadata JSON persists
source descriptors alongside the existing calendar ICS. No source is enabled by
locale or downloaded before the user adds it.

- `addHolidayCalendar(payload)`: `{type: "country", region, name}`, `{type: "url",
  url, name}` or `{type: "file", path, name}`. Returns the new descriptor as `item`.
- `refreshHolidayCalendar(id)`: atomically replaces this source's events after
  validating the complete download/file. Failed refreshes retain cached events.
- `setHolidayCalendarEnabled(id, enabled)`: persists the Calendar display preference.
- `removeHolidayCalendar(id)`: removes only the descriptor and its owned events.

Network requests use delayed D-Bus replies, a 20-second deadline, a 20 MiB size
limit and at most four redirects without HTTPS downgrade. The catalog currently
uses Apple public holiday ICS feeds for eight regions. Custom subscriptions accept
HTTP(S), with webcal normalized to HTTPS. Successful network sources refresh after
24 hours; failed attempts retry no more than hourly while the service runs.

Events are namespaced by source ID and the SHA-256 of the upstream UID, preserving
recurrence relationships while avoiding collisions with personal events and other
subscriptions. VTODO entries and notification alarms are excluded. Managed events
cannot be edited/deleted individually. Existing legacy holiday events get one
Imported holidays descriptor; empty stores retain an empty source list.

## Event and task relationships

Calendar can mirror a VEVENT as a VTODO. The VTODO uses standard iCalendar
`RELATED-TO` to reference its VEVENT, while KOS reverse-lookup properties keep
the relationship efficient and survive a local round trip. The public snapshot
exposes `linkedTodoId` on events and `linkedEventId` on tasks.

For a linked pair, title, description, start/due date, all-day state, and the
supported recurrence preset synchronize in both directions. The event retains
its duration when the due date is changed from Todo. Completion belongs to the
task and is projected into Calendar as `linkedTodoCompleted`. Only the event
owns an alarm, preventing duplicate notifications.

Deletion is deliberately non-destructive: removing either incidence preserves
and unlinks the counterpart. Disabling a link from the event editor follows the
same rule. Ordinary dated tasks do not require a paired event; Calendar displays
their VTODO occurrences directly.

## Persistence and compatibility

The default data directory is `$XDG_DATA_HOME/kos/pim` (normally
`~/.local/share/kos/pim`). `KOS_PIM_STORAGE_DIR` overrides it for tests. Events
and VTODO entries are serialized by KCalendarCore into `calendar.ics`; KOS-only
list ordering is stored in versioned `metadata.json`. Both files use
`QSaveFile`, so each individual replacement is atomic. A storage load failure
makes the service read-only instead of overwriting data.

Version 1 accepts daily, weekly, monthly, and yearly recurrence presets. More
complex rules imported from iCalendar are preserved and exposed as `custom`,
but the current editors do not rewrite them. All-day event ends follow the
iCalendar exclusive-end convention. Task priorities use the iCalendar 0–9
field, and reminders are offsets from event start or task due time.

## Safety limits

- Mutation payload: at most 1 MiB; event/task title at most 512 characters.
- Description: 32 KiB; location: 1 KiB; list name: 128 characters.
- iCalendar import: an existing absolute local file, at most 20 MiB.
- Reminder scan: the next 30 days, delivered through the standard desktop
  notification service; completed tasks are skipped.
- A rejected update is applied to a clone and cannot partially modify the
  in-memory item.

The relationship fields are additive optional properties in the version-1
JSON contract, so existing version-1 clients continue to read snapshots.

## Deliberate version-1 boundary

CalDAV, Akonadi, cloud accounts, cross-device sync, attendee scheduling, and
server-side conflict resolution are out of scope. Adding them should use a
provider/sync layer behind this service rather than coupling either UI to
Akonadi. Calendar now owns month/week/day presentation and search, but
drag-to-reschedule, attendee scheduling, timezone selection, and advanced
recurrence editing remain later UI work. Todo persists the data model for
subtasks and manual order, while creation/reordering controls remain later UI
work.

## Verification

The store tests cover restart persistence, recurrence expansion, reminders,
invalid-update isolation, linked-pair bidirectional updates, safe unlinking,
task occurrence expansion, and iCalendar round trips. Isolated session-bus
tests exercise service mutations, client synchronization, change signals, and
an actual `org.freedesktop.Notifications.Notify` call. QML smoke tests load both
application roots with a software renderer; KWin virtual-Wayland checks cover
Calendar month/week/day layouts and Calendar-linked Todo presentation.

## Calendar category and notification activation contract

`calendarId` is optional on both event and todo JSON records and stored in
`X-KOS-CALENDAR-ID`. Calendar's built-in IDs are `work`, `personal`, `sport`.
They do not replace `listId` or migrate existing Todo lists. Linked pairs copy
calendar category metadata along with their synchronized fields.

Notifications follow the [freedesktop notification protocol](https://specifications.freedesktop.org/notification/latest/protocol.html):
`default` opens Calendar details; `complete` updates a todo through the store.
The service maps returned notification IDs to item IDs, forwards optional
`ActivationToken`, and drops mappings on close or notification-server restart.
Calendar activation uses its existing Application1 D-Bus interface, with a direct
executable fallback for cold starts. This mapping is session-local: restarting
PIM loses action targets for previously issued notifications. There is no new
Akonadi or external account dependency.

### Managed local calendars

Snapshot `calendars` stores stable IDs, names, colors and optional `builtinName` in metadata.json, separately from Todo lists and holiday subscriptions. `createCalendar`, `updateCalendar` and `removeCalendar` expose JSON mutations. Existing stores receive Default/Work/Personal/Family once; persisted deletions survive restart. Default is protected. Removal migrates matching events and reminders (including legacy personal records) to default without deleting content or altering Todo list IDs. Names are trimmed and limited to 128 characters; colors accept #RRGGBB.

## Reminder organization records

Snapshot v1 adds optional `groups: [{id,name}]`, ordered `list.sections: [{id,name}]`, and `list.viewMode` (`list`/`columns`). `saveGroup(id,payload)` and `saveSection(listId,id,payload)` create with an empty ID, or rename/reorder existing records; `removeGroup` preserves lists/tasks, while `removeSection` clears task section membership without deleting tasks. Group rename atomically updates list membership, and section rename atomically updates tasks. Legacy group/section names migrate into persistent records on load and save. Empty records survive restart. Duplicate names and invalid positions are rejected before mutation.
