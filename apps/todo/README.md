# Reminders compatibility launcher

**[English](README.md) | [中文](README.zh-CN.md)**

Reminders now lives inside KOS Calendar. Switch between Calendar and Reminders in the sidebar, or in the toolbar when the sidebar is collapsed. `Ctrl+Tab` also switches workspaces.

`kos-todo` only forwards old shortcuts, pinned launchers and scripts. It replaces its process with `kos-calendar --view reminders`; there is no separate window, QML module or storage. Its desktop entry has `NoDisplay=true`, leaving Calendar as the visible application. Legacy QML sources remain for migration reference and are not built or installed.

Existing lists, tasks, dates, completion, priorities, recurrence, notifications and notes remain in the same PIM service, without copying or migrating storage. Dated reminders also appear in calendar views. The unified workspace supports All, Today, Scheduled, Completed, list filters and search. Create, details and edit use the shared Calendar popovers. Removing a list moves its tasks to Inbox.

```bash
cmake --preset todo-dev
cmake --build --preset todo-dev
```

`KOS_BUILD_TODO=ON` also builds Calendar. Legacy `--view today|planned|completed|inbox|calendar` and `--item ID` work; the old `calendar` filter means tasks linked to calendar events.

Subtask editing, drag reordering and cloud sync remain outside this iteration. See [Calendar](../calendar/README.md).
