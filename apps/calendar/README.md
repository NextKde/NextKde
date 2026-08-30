# KOS Calendar

KOS Calendar is a standalone Qt Quick application. It never imports the
Quickshell runtime or files under `desktop/`.

## Current status

The application is independently buildable and installable. Its functional
month view supports local event creation, editing and deletion, all-day and
timed events, recurrence presets, reminders, and iCalendar import/export. A
versioned D-Bus PIM service owns KCalendarCore persistence and desktop
notifications; the UI never reads its files directly.

## Build

From the repository root:

```bash
cmake --preset calendar-dev
cmake --build --preset calendar-dev
```

The executable is written below `.build/calendar-dev/apps/calendar/`.

## Version 1 boundary

- Included: month grid, selected-day agenda, event CRUD, timezone-aware local
  storage, all-day events, daily/weekly/monthly/yearly recurrence, reminders,
  iCalendar files, keyboard shortcuts, and screen-reader labels.
- Deferred: week/day views, timezone selection UI, search, attendee scheduling,
  advanced recurrence editing, cloud accounts, CalDAV, and Akonadi integration.

Calendar and Todo share only the `Kos.Pim` contract and service. Neither
application imports the other's code. See `docs/PimArchitecture.md` for data
ownership, compatibility rules, and safety limits.
