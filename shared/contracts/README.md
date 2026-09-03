# Shared contracts

This directory is the source of truth for data exchanged across runtime
boundaries. Contracts are versioned so the Quickshell process, Go data service,
platform daemon, and standalone settings application can be upgraded and
validated independently.

- [`platform.v1.md`](platform.v1.md) defines the Unix-socket JSON Lines
  request/response/event envelope, operation names, and stable error model.
- [`shortcuts.v1.json`](shortcuts.v1.json) defines the global shortcut IDs,
  default key bindings, and Shell IPC targets used by `kos-platform shortcuts`.
- [`weather-v1.schema.json`](weather-v1.schema.json) defines the persisted and
  socket-delivered shared weather object.
- [`pim-v1.schema.json`](pim-v1.schema.json) defines Calendar/Todo objects and
  their D-Bus payload boundary.

When adding a field, keep existing fields backward-compatible within the same
major contract version. A breaking change requires a new version and updates
to every client listed in the contract's implementation notes.
