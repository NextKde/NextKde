# KOS Calendar

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Calendar is a standalone Qt Quick application. It never imports the Quickshell runtime or files under `desktop/`.

## Current status

The application is independently buildable and installable. Its macOS-inspired layout provides month, week, and day views, a mini calendar, search, an agenda, all-day and timed events, recurrence presets, reminders, and iCalendar import/export. Dated KOS Todo tasks appear alongside events and keep their list colors and completion state. A versioned D-Bus PIM service owns KCalendarCore persistence and desktop notifications; the UI never reads its files directly.

## Calendar and Todo integration

- Every Todo task with a due date appears in Calendar. Recurring task occurrences are expanded by the PIM service for the visible range.
- An event editor can enable **Also show this event as a task in Todo** and choose the target list and priority.
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
- Deferred: drag-to-reschedule, timezone selection UI, attendee scheduling, advanced recurrence editing, cloud accounts, CalDAV, and Akonadi integration.

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

## Material alignment (GalleryDesign 2.10)

Liquid toolbar buttons retain their glass edges without an added accent focus ring.
The continuous ordinary sidebar composites only its background at 0.95 opacity,
with QML blur of the actual in-window base plane. Text remains opaque.
Menus, detail popovers and combo-box option popups use one liquid panel and ordinary
interior rows. Popups stay in the same window and exclude themselves from their
capture; editor dropdowns sample the editor panel. Reduced transparency or missing
GPU sampling uses opaque fallback surfaces. No KWin liquid plugin is involved.
The Day/Week/Month/Year selector samples the same chrome backdrop through the
shared liquid optics. Its track and sliding selection use neutral glass with no
accent focus overlay; keyboard selection and an opaque fallback remain available.
Pressing expands the sampled lens to 1.12 scale with stronger refraction; selection
slides and rebounds using OutBack easing. A short pulse also covers quick clicks
and keyboard changes. Labels/hit targets stay fixed; reduced motion settles directly.
Toolbar search also samples glass, with neutral text selection and no added liquid
focus ring. Action backgrounds animate press/release and optical transitions while
icons stay fixed. Tooltips use same-window liquid panels, including settings tips.
The settings dialog uses an opaque ordinary panel and ordinary segmented controls. Its in-window material host
is opt-in: Auto/Glass use available QML sampling, Solid and Reduce Transparency
stop it without relying on KWin. The shared opacity preference scales each role's
coverage relative to its 0.86 default, preserving lighter controls and denser panels;
it never fades foreground text. Typography, selector/field geometry and editor
footer sizes retain the previous compact design.
