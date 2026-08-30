# KOS Calendar

KOS Calendar is a standalone Qt Quick application. It never imports the
Quickshell runtime or files under `desktop/`.

## Current status

The first development milestone provides an independently buildable and
installable application, the shared KOS visual foundation, and an accessible
month-view shell. Event persistence, recurrence, reminders, and iCalendar
import/export will be supplied by the versioned local PIM service.

## Build

From the repository root:

```bash
cmake --preset calendar-dev
cmake --build --preset calendar-dev
```

The executable is written below `.build/calendar-dev/apps/calendar/`.

## Planned scope

- Month, week, day, and agenda views.
- Local event creation and editing, including all-day events.
- Time zones, recurrence, reminders, and search.
- iCalendar import and export through KCalendarCore.
- Keyboard navigation and screen-reader labels.

Cloud accounts, CalDAV, and Akonadi integration are intentionally deferred.
