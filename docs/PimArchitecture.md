# Local PIM architecture

Calendar and Todo are separate Qt Quick processes backed by one local service.
The applications share a versioned data contract, not UI or application code.

```text
KOS Calendar             KOS Todo
      \                     /
       +--- Kos.Pim client +
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
Calendar and Todo use the `Kos.Pim` client module and never open the storage
files directly. D-Bus activates the service on first use; an XDG autostart
entry starts it proactively in a desktop session so reminders work before an
application window is opened.

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
