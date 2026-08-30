# KOS Todo

**[English](README.md) | [中文](README.zh-CN.md)**

KOS Todo is a standalone Qt Quick task manager. It shares a versioned local
PIM contract with KOS Calendar but does not import Calendar or Shell code.

## Current status

The application is independently buildable and installable. Tasks and lists
are durably stored by the shared local PIM service. The UI provides Inbox,
Today, Planned, Completed, and custom-list views; quick add; task editing;
completion; due dates; priorities; recurrence presets; reminders; and notes.
The Calendar smart view lists tasks created from Calendar events. Linked tasks
carry a visible badge, and edits to their title or due date are reflected in
both applications. Any task with a due date also appears in Calendar even when
it is not linked to an event.

## Build

```bash
cmake --preset todo-dev
cmake --build --preset todo-dev
```

The executable is written below `.build/todo-dev/apps/todo/`.

## Version 1 boundary

- Included: persistent lists and tasks, filtered views, a Calendar-linked smart
  view, due dates, completion, iCalendar priorities, recurrence, reminders,
  notes, and keyboard shortcuts.
- The service contract already preserves parent IDs and manual order so later
  subtask/reordering UI does not require a storage migration.
- Deferred: search, subtask creation controls, drag reordering, list
  edit/delete controls, completion history UI, collaboration, and third-party
  task accounts.

Calendar and Todo are separate applications and share only the versioned
`Kos.Pim` service contract. See `docs/PimArchitecture.md`.
