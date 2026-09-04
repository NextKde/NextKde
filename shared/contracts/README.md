# Shared contracts

This directory is the source of truth for data exchanged across runtime
boundaries. Contracts are versioned so the Quickshell process, Go data service,
platform daemon, and standalone settings application can be upgraded and
validated independently.

- [`platform.v1.md`](platform.v1.md) defines the Unix-socket JSON Lines
  request/response/event envelope, operation names, and stable error model.
- Global shortcut IDs, default key bindings, and Shell IPC targets live in
  the Shell's ShortcutsService (shell/desktop/modules/shortcuts/), which is
  the single source of truth: it composes the Exec lines for the live Shell
  instance and applies the set through the `shortcuts.apply` platform
  operation. The contract test in `platform/tests/test_contract.py` keeps
  the service's default table in check.

When adding a field, keep existing fields backward-compatible within the same
major contract version. A breaking change requires a new version and updates
to every client listed in the contract's implementation notes.
