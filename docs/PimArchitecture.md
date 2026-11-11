# Calendar and task integration

Calendar, its Reminders workspace, PIM storage/service and their tests are owned
by [NextKde/kos-apps](https://github.com/NextKde/kos-apps). Core does not build,
install or activate a PIM service. Implementation details and application-private
storage rules belong to that repository.

Core widgets use the read-only, versioned summary described in
[App/widget integration](app-store/WidgetIntegration.md). They never read ICS,
metadata or preferences directly and never mutate the application's PIM data.

- Current application identity: `org.nextks.calendar`.
- Native summary: `$XDG_DATA_HOME/org.nextks.calendar/pim/widget-snapshot.json`.
- Flatpak summary: `~/.var/app/org.nextks.calendar/data/kos/pim/widget-snapshot.json`.
- The application owns `org.nextks.calendar.Pim`; core widgets do not call that
  bus service. The retired native bus name and profile are not fallbacks.
- `application.widget-snapshot` reads a bounded summary only after resolving an
  unambiguous current installation. `application.widget-open` rechecks its source
  token and launches that exact desktop entry with fixed date/view/item options.
- `PimWidgetService.qml` projects this contract into the desktop calendar. A
  missing, stale, unsupported or ambiguous source remains explicit; the date
  grid itself does not require the application.

The app publishes `widgetContractVersion=2` with `appId`, channel, storage mode,
storage path, generation time and the schema-version-1 event/task payload.
Custom profiles are outside the supported integration scope. See the canonical
[integration contract](app-store/WidgetIntegration.md) for validation, polling,
launch races and VM acceptance, and [application identities](app-store/ProfileMigration.md)
for current paths and optional legacy cleanup.
