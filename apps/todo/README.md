# KOS Todo

KOS Todo is a standalone Qt Quick task manager. It shares a versioned local
PIM contract with KOS Calendar but does not import Calendar or Shell code.

## Current status

The first milestone supplies an independently buildable application and a
keyboard-accessible inbox prototype. Prototype tasks are intentionally
in-memory until the local PIM service owns durable storage and reminders.

## Build

```bash
cmake --preset todo-dev
cmake --build --preset todo-dev
```

The executable is written below `.build/todo-dev/apps/todo/`.

## Planned scope

- Lists, tasks, subtasks, priorities, and manual ordering.
- Due dates, recurrence, completion history, and reminders.
- Inbox, Today, Planned, Completed, filters, and search.
- Transactional local persistence shared with Calendar through a service.

Cloud collaboration and third-party task accounts are deferred.
