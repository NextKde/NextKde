# KOS Greeter

Standalone greetd login UI using KWin Wayland and Quickshell. Authentication is handled by greetd/PAM; the authenticated session starts the supported Plasma Wayland command. The app does not modify PAM or execute arbitrary user themes before login.

- [Installation, updates and recovery](INSTALL.zh-CN.md)
- [中文说明](README.zh-CN.md)
- [Temporary test and rollback](TEMPORARY-TEST.zh-CN.md)
- [Display configuration](../../docs/kos-greeter/contracts/machine-outputs.md)
- [Session handoff](../../docs/kos-greeter/contracts/session-handoff.md)
- [Optional compositor handoff experiment](experimental/drm-handoff/README.md)

Dependencies include Python 3/Pillow, greetd, KWin Wayland, Quickshell with Greetd support, Qt Quick Controls and Plasma Wayland. Use `apps/greeter/bin/kos-greeter-session --check` for a read-only dependency check.

The installed login wallpaper is a consented public copy. It remains until explicitly replaced or revoked; changing the desktop wallpaper does not automatically publish it. Update using `./tools/install-greeter.sh --refresh-wallpaper`; revoke using the same command with `--no-wallpaper-sync`.

Tests use fake authentication or isolated virtual compositors, not real passwords. Generated logs, screenshots and videos default to `.build/greeter-tests/` and are not committed. Display fixtures live in `tests/fixtures/outputs/`.

```sh
node apps/greeter/tests/lifecycle.test.cjs
node apps/greeter/tests/entry-protocol.test.cjs
python3 apps/greeter/tests/outputs.test.py
python3 apps/greeter/tests/display.test.py
python3 apps/greeter/tests/install.test.py
```

Cross-compositor black frames, physical DRM/VT continuity and real PAM login still require machine-specific acceptance; isolated tests do not prove these behaviors.
