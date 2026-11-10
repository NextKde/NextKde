# Notification click confirmation

Run validation only in a VM or hosted CI.

`kos-notifications.activation` checks identity matching, rejects unvalidated
launch ids, and evaluates the production KWin snapshot during the animation
focus lag. `activated` remains an animation hint; `focusConfirmed` changes only
when the live KWin focus changes, and must produce a new snapshot.

`kos-shell.notification-open` loads the shipping QML controller with injected
providers. It covers confirmed focus, minimized windows, optimistic KWin
state, foreign-toplevel activation, command failures, launch failures,
timeouts, repeated clicks, destroyed/replaced notifications, and resident
notification policy. It is part of the required headless CI inventory.

With a configured test build in the VM:

```sh
ctest --test-dir .build/debug \
  -R '^(kos-notifications.activation|kos-shell.notification-open)$' \
  --output-on-failure
```

For compositor acceptance, use a private D-Bus session, an isolated virtual
KWin output/configuration, the current `kwin/window-bridge.js`, and a separate
platform socket. Exercise the production controller, WindowService and Dock
launch path with a real Wayland client. Check cold launch, minimized restore,
background raise, and unchanged restored geometry. Completion must coincide
with `toplevel.focusConfirmed`, not merely a command receipt or `activated`.

Timeout preserves the notification and does not invoke another default action:
a slow launch may still finish. A definite activation/launch failure may invoke
the notification's default action; that API confirms dispatch, not the sending
application's eventual handling. Older KWin bridges lacking `focusConfirmed`
conservatively retain the notification rather than assert successful focus.
