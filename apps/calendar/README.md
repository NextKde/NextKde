# KOS Calendar

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Calendar is a standalone Qt Quick application. It never imports the
Quickshell runtime or files under `desktop/`.

## Current status

The application is independently buildable and installable. Its macOS-inspired
layout provides month, week, and day views, a mini calendar, search, an agenda,
all-day and timed events, recurrence presets, reminders, and iCalendar
import/export. Dated KOS Todo tasks appear alongside events and keep their list
colors and completion state. A versioned D-Bus PIM service owns KCalendarCore
persistence and desktop notifications; the UI never reads its files directly.

## Calendar and Todo integration

- Every Todo task with a due date appears in Calendar. Recurring task
  occurrences are expanded by the PIM service for the visible range.
- An event editor can enable **Also show this event as a task in Todo** and
  choose the target list and priority.
- A linked pair synchronizes title, notes, schedule, all-day state, and the
  editable recurrence preset in both directions. Completing the task is shown
  immediately in Calendar.
- Calendar owns the reminder of a linked pair to prevent duplicate desktop
  notifications.
- Removing either side, or disabling the event link, preserves the counterpart
  and only removes the relationship. This avoids surprising data loss.

## Build

From the repository root:

```bash
cmake --preset calendar-dev
cmake --build --preset calendar-dev
```

The executable is written below `.build/calendar-dev/apps/calendar/`.

## Version 1 boundary

- Included: month/week/day views, mini calendar, search, selected-day agenda,
  event CRUD, scheduled Todo display and editing, linked event/task pairs,
  timezone-aware local storage, all-day events, recurrence presets, reminders,
  iCalendar files, keyboard shortcuts, and screen-reader labels.
- Deferred: drag-to-reschedule, timezone selection UI, attendee scheduling,
  advanced recurrence editing, cloud accounts, CalDAV, and Akonadi integration.

Calendar and Todo share only the `Kos.Pim` contract and service. Neither
application imports the other's code. See `docs/PimArchitecture.md` for data
ownership, compatibility rules, and safety limits.
