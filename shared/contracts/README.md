# Shared contracts

This directory is the source of truth for data exchanged across runtime
boundaries. Contracts are versioned so the Quickshell process, Go data service,
platform daemon, and standalone settings application can be upgraded and
validated independently.

- [`platform.v1.md`](platform.v1.md) defines the Unix-socket JSON Lines
  request/response/event envelope, operation names, and stable error model.
- [`weather-v1.schema.json`](weather-v1.schema.json) defines the persisted and
  socket-delivered shared weather object.
- [`pim-v1.schema.json`](pim-v1.schema.json) defines Calendar/Todo objects and
  their D-Bus payload boundary.
- [`shortcuts.v1.json`](shortcuts.v1.json) is the source for the global
  shortcut IDs, default key bindings, and Shell IPC targets used by
  `kos-platform shortcuts`. At runtime the Shell's ShortcutsService
  (shell/desktop/modules/shortcuts/) is the authority: it composes the Exec
  lines for the live Shell instance and applies the set through the
  `shortcuts.apply` platform operation. A shortcut added to the contract must
  also be added to that service's defaults.

When adding a field, keep existing fields backward-compatible within the same
major contract version. A breaking change requires a new version and updates
to every client listed in the contract's implementation notes.
