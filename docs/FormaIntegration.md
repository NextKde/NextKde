# Forma application integration

[简体中文](FormaIntegration.zh-CN.md)

## User-facing boundary

Settings → **Integration status** → **Forma applications** has an opt-in
**Enable Forma** switch. The default is off. Enabling it selects installed Forma
applications for supported file/media defaults and desktop entry points; it does
not install or remove software, restart services, change the browser, or replace
KOS Settings. **Apply again** includes applications installed since the previous
application. Missing applications are listed and skipped.

The fixed roles are Finder, Terminal, Text, Photos, Video, Music, Calculator,
Task Manager, Screenshot, App Store and Mail. Music is preferred for audio;
Video is the fallback when Music is absent. Only explicitly supported MIME and
scheme defaults are changed. PDF and archives are not assigned to unsupported
Forma applications. Calculator and Task Manager are launch roles, not artificial
MIME associations.

Forma Terminal currently accepts a working directory, not KDE's `-e` command
execution interface. It is available for direct/Dock launching, but the integration
preserves the existing `TerminalApplication` and `TerminalService` execution
preferences so `Terminal=true` applications are not newly broken by the switch.

## Ownership and recovery

`platform/src/daemon/FormaIntegration.*` owns installation checks, configuration
writes and a bounded schema-1 ownership journal under
`$XDG_STATE_HOME/quickshell/kos/forma-integration.json`.

Before changing any defaults it durably records each affected key's prior value,
whether that key existed, and the value Forma owns. Reapplying does not replace
that original backup. User MIME defaults live in `mimeapps.list`; an existing
user `kde-mimeapps.list` is also handled so a higher-priority override does not
silently defeat the choice. Unrelated keys and system defaults remain unchanged.

Disabling restores only keys still holding the value this integration wrote.
A later manual choice is not overwritten. Previously absent keys are removed,
not replaced by empty IDs or an assumed KDE default. Damaged/unsupported state
is rejected instead of treated as an empty backup. Partial-write errors keep
recovery information; the Settings **Restore previous preferences** action
retries restoration before another takeover. The confirmed `enabled` value is
not flipped optimistically on failure or disconnection.

## Runtime paths

- Settings → `SettingsBridge` → Shell `forma-integration` IPC target →
  `FormaIntegrationService` → versioned `integration.forma.get/set` platform
  operations. QML never writes host MIME files or runs system commands.
- The system menu prefers Forma App Store and exposes Forma Task Manager for
  **Force Quit** when enabled and installed. **System Settings** continues to
  activate `kos-settings`; **About This Computer** retains the information center.
- Existing KDE pins are projected to available Forma equivalents in
  `DockModelService`. Persisted pin IDs/order are not rewritten merely by enabling
  the switch. Disabling returns to the original pins; explicit unpin/reorder
  operations continue to target the corresponding saved entry. Running KDE
  windows and explicit application-launcher choices retain their identities.
  Explicit Forma, KOS and KDE Settings pins are never substituted in either mode;
  preserving KOS's system-menu Settings action does not replace a user's pinned app.
- `screenshot.capture` prefers the installed Forma Screenshot desktop entry in
  Forma mode, retaining the original tool fallback otherwise.
- Dock click and context-menu **Open** both use `file.open-trash`. The daemon
  chooses Finder when enabled and installed, or when Finder is already the
  user's default directory handler. It passes a local
  `$XDG_DATA_HOME/Trash/files` URL through the Finder desktop entry's `%f`, which
  expands to a native path. Finder recognizes that path as its Trash view with
  restore/empty controls; `trash:` and `file://` are not CLI directory arguments.
  Empty home-trash directories are prepared, symlink destinations are rejected,
  and the existing Dolphin `trash:` fallback remains for other configurations.
  This does not expand the current home-trash state/empty scope to other mounts.

An old/missing platform service shows unavailable/error state and does not apply
preferences. Deploy matching platform, Shell and Settings products before testing;
source QML with an older installed service is not a completed integration.

## Verification boundary

Build and run only in a dedicated VM or hosted CI, per [Development](Development.md).
`kos-platform.forma-integration` covers isolated preference ownership/restoration;
`kos-platform.forma-trash` uses fake desktop entries, isolated XDG roots and the
real KIO launch path to check native Trash argv, screenshot preference and unsafe
path rejection. Settings page contracts cover pending/confirmed/error states;
Dock model tests cover optional role substitution and projected unpinning.
These test definitions are not evidence that the current change has passed them.
Real VM acceptance must also exercise the switch, install-missing/reapply flow,
manual-default preservation, all relevant file types and the actual Finder window.

The authoritative wire contract is [platform.v1](../shared/contracts/platform.v1.md).
