# KOS Calendar

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Calendar is a standalone Qt Quick application. It never imports the Quickshell runtime or files under `desktop/`.

## Current status

The application is independently buildable and installable. Its macOS-inspired layout provides month, week, day, and year views, a mini calendar, search, an agenda, all-day and timed events, recurrence presets, reminders, and iCalendar import/export. Dated KOS Todo tasks appear alongside events and keep their completion state. A versioned D-Bus PIM service owns KCalendarCore persistence and desktop notifications; the UI never reads its files directly.

## Calendar and Todo integration

- Every Todo task with a due date appears in Calendar. Recurring task occurrences are expanded by the PIM service for the visible range.
- Add offers **Event** and **Reminder**. Reminders use the existing Todo backend; Default, Work, Personal and Family are calendar categories, independent of Todo list membership.
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

The sidebar groups Default, Work, Personal and Family under My calendars, with
independent event visibility filters. Scheduled reminders appear under Other with a separate visibility checkbox
unaffected by those filters. New events use Default; existing Personal metadata is
preserved. Legacy Sport and unknown IDs appear under Default without rewriting
imported metadata or Todo lists. Today remains in the toolbar and keyboard shortcut,
and is removed from the sidebar.
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

## Holiday calendars

No holiday calendar is added by default. Other initially contains Scheduled
reminders and Add holiday calendar. A source appears only after a successful add.

- Country or region automatically downloads an Apple public holiday calendar for
  China, the US, UK, Japan, Germany, France, Australia or Canada.
- Custom accepts an HTTP(S)/webcal subscription address or imports a local `.ics` file.
- Each source has its own visibility checkbox and Refresh / Remove calendar menu.
- Online sources refresh daily while the PIM service runs. Failed downloads retain
  cached events. File sources refresh only when requested, using the original file.
- Source events are read-only, have namespaced UIDs, retain dates and recurrence,
  exclude tasks and alarms, and can be removed without affecting personal data.

Date coverage and updates depend on the external provider; the Chinese feed does
not guarantee statutory adjusted workday coverage. Legacy imports remain visible
as Imported holidays.

Local calendar categories are persisted by the PIM service. Use the heading’s + to add, and each row’s anchored LiquidPopover to edit name/color or delete. Deletion confirms migration of events and reminders to the protected default calendar; Todo lists stay independent. Holiday action menus use the same popover.

### Calendar colors

Preset colors use a historical Apple Calendar reference: red #FB0055, orange #FB8208,
yellow #FEC309, green #56D72B, blue #1D9BF6, purple #BF57DA, brown #90714C.
Source: [Matt Stone’s direct OS X El Capitan 10.11.3 observations](https://matt-stone.co.uk/change-colours-microsoft-office-365-shared-calendars-apple-calendar-os-x/).
These are not verified macOS 15/27 color constants. [Apple’s current guide](https://support.apple.com/guide/calendar/icl1030/mac)
confirms preset and custom colors but supplies no hex table. Default/work/personal/family
map to purple/orange/blue/green by this app’s choice, not an Apple-mandated category mapping.
Custom colors support a color dialog and #RRGGBB entry. They remain opaque and persist
only on Save/Add. Cancel leaves stored colors unchanged. Untouched old bundled colors
upgrade; marked custom colors and renamed categories retain their values.

### Contextual editing and range selection

Toolbar + opens the creation editor directly; the Reminders workspace only creates reminders. Creation, details
and editing use anchored LiquidContentPopover; they never dim the calendar.
New-draft Event/Reminder tabs retain separate drafts; existing records retain their
type. Date/repeat/notification options expand inside ordinary grouped content.
Save is explicit; outside click/Escape discards the displayed draft.

Day/week empty time cells support vertical mouse range selection in 15-minute
steps, both directions, with edge scrolling. Release opens a prefilled event
popover anchored to the selected range. Existing chips still open their details;
Return on a focused empty cell still creates. Month multi-day dragging and
rescheduling existing events by dragging are not implemented by this change.
Natural-language quick entry is not offered.

Explicit native interaction review after building: `python3 apps/calendar/tests/run-popover-review.py`.
Run only on an authorized graphical session. It uses temporary PIM data and an
isolated session bus, and checks forward/reverse selection, draft switching,
create/details/edit persistence without touching user records.


## Unified Calendar and Reminders (2026-10-28)

One Calendar window and one PIM client serve both workspaces. Switch in the sidebar, the toolbar when collapsed, or with Ctrl+Tab. Calendar keeps its date and view; Reminders keeps its list/filter. Each workspace retains its search query.

Reminders supports All, Today, Scheduled, Completed, list filters and title/notes search across dated and undated tasks. Create, details and edit use the same liquid content popovers. List assignment, priority, recurrence and notifications are editable; untouched imported recurrence rules are preserved. Lists can be created, renamed and removed; removing a list moves its tasks to the protected Inbox.

`--view reminders` opens this workspace. The legacy `kos-todo` executable forwards to Calendar's existing instance, and its application-menu entry is hidden. PIM storage stays in place. Runtime and visual checks for this iteration run only in the VM with temporary data and a separate D-Bus session.

### Reminder organization

Reminders belong to one list; flags are independent of priority. The Flagged view
collects unfinished flagged tasks across lists. The row's plus action creates a
subtask in the same list using the shared editor. List views allow collapsing
children; date and search views keep matching tasks visible independently.
Completion is independent. Moving a parent moves its descendants; deleting a
parent preserves children as top-level tasks. Cyclic parent relationships are
rejected by the PIM service. These features use the existing ordinary controls
inside the shared liquid popover.

### Groups, sections, tags and saved views

- Use the sidebar + menu to create a list or group. Empty groups persist. Select a group name to aggregate its lists; its arrow only folds the sidebar. Rename/remove via the group menu; removal keeps lists and reminders. Move a list using the group selector in its editor.
- A reminder's **Section** organizes its list. Subtasks follow their parent's
  section. **Tags** accept space/comma-separated names, optionally prefixed with
  `#`; the sidebar searches a tag across lists. Tags use iCalendar categories.
- Create a **Smart list** using the list editor's Type selector. It matches all
  configured source-list, tag, date, flag and priority conditions against unfinished
  reminders. It owns no tasks. New reminders inherit its conditions; deleting this
  saved view does not delete tasks. Existing lists keep their original type.
- Drag the task's handle to the top/bottom half of another row to place it before/
  after that row in a regular list, or onto a sidebar list to move it. Date/search/
  smart views preserve their computed ordering; tasks can still be dragged from
  these views into a regular list. Dropping on a sibling row adopts its parent and
  section; cyclic nesting is rejected. Moving into a sidebar list makes the task
  top-level. Parent moves carry descendants.
- Metadata extensions are optional for old records. Ordering preserves full double
  precision. Groups and ordered sections persist independently in metadata, along with per-list view mode. Legacy names migrate automatically. Section/flag/order
  persist as custom iCalendar fields, with tags stored as standard categories.

For an isolated graphical acceptance run (only on an authorized machine):
`KOS_CALENDAR_REVIEW_FIXTURE=ReminderOrganization.qml.inc python apps/calendar/tests/run-popover-review.py`
The fixture uses a temporary PIM store and checks grouping, smart-list creation,
labels, hierarchy, actual mouse dragging and light/dark layouts.

### Compact list customization and reminder details

List editing offers 18 preset colors and 18 shared vector icons; there is no HEX/RGB
entry. Existing saved colors are retained. Sidebar list badges are 18 px with 12 px
labels and compact, vertically centered rows.

Reminder editing uses shared SettingsGroup/SettingsItem for title/notes, date/time, organization and task attributes. Toggle time to enable the hour/minute picker (today is filled in when needed). Expand Tags to type or toggle existing tags. The **URL** field accepts HTTP/HTTPS links. **Add images**
opens a local file picker; thumbnails support removal and opening in the system
viewer. Details show tags, a link action and thumbnails.

Up to eight PNG/JPEG/WebP/GIF/BMP images are supported (10 MB and 25 megapixels per
image). Saving copies validated images into the PIM data directory, so moving the
original does not break the reminder. Removing an attachment removes its reference;
image storage is retained conservatively for shared references/backups. Local image
references are not portable email/cloud attachments. URL uses the standard iCalendar
URL field. Imported images are decoded before acceptance.

### Inline creation, sections and columns

Click a section's trailing empty row to enter a reminder; Return saves and continues, Escape cancels, and empty titles are discarded. Existing titles edit in place; completion and the details popover have separate controls. There is no separate quick-entry form above the list.

In a regular list, right-click the content area or use Add section. Empty sections persist. Their menus rename/reorder/remove them; removing a section keeps its tasks in Other. List/column mode persists per list. Columns represent sections of one list, with horizontal scrolling at narrow widths; group aggregation remains a list view.

Run `KOS_CALENDAR_REVIEW_FIXTURE=ReminderHierarchy.qml.inc python3 apps/calendar/tests/run-popover-review.py .build/apps-release` only in an authorized session. It uses a temporary store and isolated bus and captures `/tmp/calendar-hierarchy-*.png`.
