# KOS Calendar

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Calendar is a standalone Qt Quick application. It never imports the Quickshell runtime or files under `desktop/`.

## Current status

The application is independently buildable and installable. Its macOS-inspired layout provides month, week, day, and year views, a mini calendar, search, an agenda, all-day and timed events, recurrence presets, reminders, and iCalendar import/export. Dated KOS Todo tasks appear alongside events and keep their completion state. A versioned D-Bus PIM service owns KCalendarCore persistence and desktop notifications; the UI never reads its files directly.

## Calendar and Todo integration

- Every Todo task with a due date appears in Calendar. Recurring task occurrences are expanded by the PIM service for the visible range.
- Add offers **Event** and **Reminder**. Reminders use the existing Todo backend; Work, Personal and Sport are calendar categories, independent of Todo list membership.
- Existing linked event/task pairs remain editable, including their target list and priority. New entries use the two explicit creation flows.
- A linked pair synchronizes title, notes, schedule, all-day state, and the editable recurrence preset in both directions. Completing the task is shown immediately in Calendar.
- Calendar owns the reminder of a linked pair to prevent duplicate desktop notifications.
- Removing either side, or disabling the event link, preserves the counterpart and only removes the relationship. This avoids surprising data loss.

## Build

From the repository root:

```bash
cmake --preset calendar-dev
cmake --build --preset calendar-dev
```

The executable is written below `.build/calendar-dev/apps/calendar/`.

## Version 1 boundary

- Included: month/week/day views, mini calendar, search, selected-day agenda, event CRUD, scheduled Todo display and editing, linked event/task pairs, timezone-aware local storage, all-day events, recurrence presets, reminders, iCalendar files, keyboard shortcuts, and screen-reader labels.
- Deferred: drag-to-reschedule, timezone selection UI, attendee scheduling, advanced recurrence editing, cloud accounts, and CalDAV. Akonadi is explicitly excluded.

Calendar and Todo share only the `Kos.Pim` contract and service. Neither application imports the other's code. See `docs/PimArchitecture.md` for data ownership, compatibility rules, and safety limits.

## Compact interface

Calendar follows nextkdeAppDemo's GalleryDesign 2.9: 224px ordinary sidebar,
26px liquid toolbar actions, 28px solid form fields and compact dialog footers.
The month grid and selected-day agenda use flat content surfaces. The agenda
height follows its item count; long lists scroll within a bounded viewport.
Week/day positioning is clamped to the timeline's scroll extent, including late
hours and window resizing. Event/task validation and deletion confirmation stay
in their editors; the shared footer only emits action requests.

The optical material is opt-in at the shared UI boundary. Application source
previews therefore need a freshly built calendar binary containing
`LiquidCompactSurface`; an older installed binary cannot load this source tree.

## Material alignment (nextkdeAppDemo)

Calendar uses the canonical Demo `LiquidActionButton`, `LiquidTextField`,
`LiquidSegmentedControl` and `LiquidSurface` implementations packaged as `Kos.Demo`.
The source and shaders in `shared/demo-ui` are byte-for-byte snapshots of the Demo
working tree, with a SHA-256 manifest. The separate module preserves legacy Kos.Ui
consumers in other apps. Toolbar action buttons use the strong intensity preset;
the search field uses light intensity. Both retain compact dimensions.
Calendar owns placement, state and capture sources only; it
adds no optical rims, tint/blur layers, press pulses or rebound animations. Liquid
focus retains the material edge; the original button's legacy ring is hidden via
its supported focusRingColor property. Ordinary fallback keeps semantic focus.

The sidebar follows the standalone Demo's desktop-alpha mode: one ordinary,
continuous background at opacity 0.95, with fully opaque text. The window has no
opaque backing under it; the right content plane remains opaque. There is no real
in-window scene underneath the sidebar to blur, so no dummy blur pass or duplicated
page is supplied. Normal desktop alpha composition does not sample or blur desktop
pixels and does not request KWin liquid effects. Collapsing the sidebar removes its
background coverage. Solid/reduced-transparency/software modes use opaque material.

Menus, details, option popups and tooltips use one canonical liquid surface with
same-window QML underlay blur; their rows/text remain ordinary and opaque. Editor
popups sample the editor, excluding themselves. Settings use an opaque ordinary
panel and ordinary selectors. Auto/Glass use QML sampling; Solid and Reduce
Transparency stop it. The opacity preference scales the canonical fill token
relative to its 0.86 default (the default preserves Demo's 0.35 control fill), and
scales floating-panel coverage separately without fading foreground content.

## Calendar categories, details and notifications

The sidebar exposes Work, Personal and Sport with independent visibility filters.
Both VEVENT and VTODO use optional `calendarId` metadata; missing or unknown IDs
appear under Personal, without rewriting imported metadata or Todo lists.
The add menu creates either an event or a dated reminder. Details show category,
time, notes, repeat/notification settings and completion controls where applicable.
Editors wait for the service result before closing; failed saves retain the form.
Changing unrelated fields preserves existing custom recurrence and alarm values.

Notification default actions activate Calendar with `--item event:<uid>` or
`--item todo:<uid>`, or launch it when closed. Reminder notifications also support
completion. The service forwards compositor activation tokens and forgets closed
notification IDs. Desktop notification servers may omit actions; reminders require
the PIM service to be running. No automatic startup policy is installed by this UI
iteration. See [the iteration plan](ITERATION_PLAN.zh-CN.md) for acceptance and the
separate follow-up backlog.
