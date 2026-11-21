# KOS lock screen

A MacLock-inspired **native KDE Plasma session lock**, not a Quickshell overlay. `kscreenlocker_greet` continues to own PAM, idle locking, suspend integration and lock shortcuts. The SDDM login screen is unchanged.

## Presentation

The date and clock sit at the top; a compact media card, account avatar and password capsule form the lower center. Optional notifications occupy the upper-right corner. Weather/calendar widgets are no longer part of the default layout.

Still images retain the resolved-file HiDPI takeover: the theme walks the greeter's wallpaper item for its resolved absolute image URL and decodes at logical size × DPR. Unknown/animated providers remain owned by the wallpaper plugin. GPU effects use `MultiEffect` and a shared, preblurred wallpaper texture for glass refraction. Neither passwords nor desktop windows are captured. Software rendering retains plain text, the wallpaper and translucent fallback cards. Optional effects, avatar, media and notifications are isolated behind Loaders.

Media uses standard MPRIS, including the existing player-selection policy and lyric metadata. Lyrics are collapsed by default; there is no external lyric/video scraping. Artwork is limited to local files or inline image data because the greeter disallows network access. Passwords remain arbitrary strings. Enter/the arrow submit once only after PAM's secret prompt is ready; an asynchronous startup retains the field instead of dropping the first password. Escape or greeter clearing cancels the pending intent; it expires after 10 seconds without replaying a secret later. Caps-lock and failure hints remain visible, and PAM's own password delay is respected. The existing activity-driven PAM retry controller is retained; it does not poll cameras in the background.

## Settings and installation

Open **KOS Settings → Lock screen**, or `kos-settings --page=lockscreen`:

- KOS (MacLock style) / system-default skin.
- Independent lock wallpaper, shared image library, local file picker and a safe static preview.
- Media controls and privacy-only notification toggles.
- An explicitly clicked **Lock now** action.

Appearance keys are declared in `contents/lockscreen/config.xml`. KScreenLocker loads them from `kscreenlockerrc [Greeter][LnF][General]`. Wallpaper writes go to `[Greeter][Wallpaper][org.kde.image][General]`, with `WallpaperPlugin=org.kde.image` in `[Greeter]`. Desktop wallpaper IPC, `[Daemon]` lock policy and unknown configuration entries are not changed.

**A global Look-and-Feel selection is not the lock-screen selector.** The greeter resolves `plasma/shells/org.kos.desktop/contents/lockscreen/LockScreen.qml`; the top-level `X-Plasma-APIVersion` must be `2`. Removing the optional skin directory invokes KDE's system fallback while retaining the KOS desktop package.

Settings and `kosctl` share the `LockScreenSettings` lifecycle. Durable resources live under `$prefix/share/kos/lockscreen`, independent of the checkout. A write lock, ownership checks, same-filesystem staging and atomic exchange prevent partially deployed entry points. GUI theme changes never change `ShellPackage` or overwrite unrecognized/symlinked skins. Core upgrades preserve the user's enabled state.

Explicit installation, from the repository root:

```bash
./tools/kosctl install lockscreen
```

Restore the system skin:

```bash
./tools/kosctl uninstall lockscreen
```

Standalone CLI installs retain the original ShellPackage backup/restore behavior. Build first if the current Settings backend is not available. Every lock launches a fresh greeter, so deployed QML changes take effect on the next lock. Nix runtime installation is not verified.

## Notification bridge

The existing desktop notification owner publishes an in-memory projection through `lockscreen.notifications-publish`. The platform exposes read-only `NotificationsJson` on session service `org.kos.LockScreen`, path `/org/kos/LockScreen`, interface `org.kos.LockScreen1`.

It never claims `org.freedesktop.Notifications`. The projection has at most four rows, with app name/icon/time only; summary and body are always empty. Blocked sources, disabled history and do-not-disturb suppress it. Disconnect or a 30-second lease expiry clears the projection. No persistent notification history is loaded. See `shared/contracts/platform.v1.md`.

## Verification and safe preview

From the repository root, without locking the session:

```bash
bash apps/lockscreen/tests/headless/run.sh
```

```bash
dbus-run-session -- env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input apps/lockscreen/tests/preview/tst_layout.qml
```

A safe window with a fake authenticator and sample media/notifications saves an image and exits:

```bash
dbus-run-session -- env QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl qml6 apps/lockscreen/tests/preview/Preview.qml -- --wallpaper /absolute/path/wallpaper.png --output /tmp/kos-lockscreen-preview.png
```

Layout tests cover desktop, small, portrait and narrow screens, optional-content settings, malformed notification data, the clock and automatic wallpaper re-adoption after the greeter reparents it. Existing authentication, media-selection and theme-resolution tests are retained.

Notification end-to-end tests copy the production `LockNotifications.qml` and its glass dependencies unchanged into a temporary config root. A private D-Bus and real platform bridge exercise both the model and rendered card labels: existing/late owners, four-row replacement, empty snapshots, publisher disconnect and service loss/restart.

```bash
cmake -S tests/lockscreen-notifications -B .build/lockscreen-notifications-tests
```

```bash
cmake --build .build/lockscreen-notifications-tests -j 4
```

```bash
ctest --test-dir .build/lockscreen-notifications-tests --output-on-failure
```

Real-password authentication, monitor hotplug and suspend/resume still require acceptance testing in a recoverable session.

## Shader licensing

`LockGlass.qml` and `liquidglass.frag` are adapted from MacShell/MacLock, copyright Rickky, under MIT; `LICENSE.MacShell` ships with the assets. No third-party fonts, screenshot wallpaper or album media were copied. The old `LockClock.qml` and its SDDM counterpart remain unchanged; this skin uses `MacLockClock.qml`.

After changing the shader, rebuild the shipped QSB; never compile shaders inside the greeter:

```bash
/usr/lib/qt6/bin/qsb --qt6 --qsbversion 64 -o apps/lockscreen/contents/lockscreen/liquidglass.frag.qsb apps/lockscreen/contents/lockscreen/liquidglass.frag
```
