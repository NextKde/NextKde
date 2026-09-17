# KOS Lock Screen (`apps/lockscreen`)

An iPadOS-flavoured lock screen for KDE Plasma, drawn by `kscreenlocker` — a
real session lock, not an overlay.

Unlike the other directories under `apps/`, this is **not** an executable. It
is a Plasma Look-and-Feel package (KPackage) whose only job is to replace the
QML that `kscreenlocker_greet` draws: authentication, idle locking, sleep
hooks, and every lock entry point stay owned by kscreenlocker.

## Layout

```
metadata.json                 KPackage metadata (Plasma/LookAndFeel, id org.kos.desktop)
contents/defaults             Inherits Breeze Dark so switching themes changes nothing else
contents/lockscreen/
    LockScreen.qml            Greeter entry point (kscreenlocker contract) + password input + wallpaper takeover
    LockClock.qml             Oversized clock + date (liquid-glass numerals masked from the backdrop)
tests/headless/               Offscreen harness: asserts the state machine and the takeover, renders lock.png
    wallpaper-sample.png      Wallpaper used by the harness (a real lock screen shows the user's own)
```

## What the greeter gives the QML

kscreenlocker_greet injects `authenticator` (PAM conversation:
`startAuthenticating()` / `respond()` / `succeeded` / `failed`), `wallpaper`
(the Plasma wallpaper item), `config`, and the `kscreenlocker_*` globals. It
reads `viewVisible` off the root object and connects to its `clearPassword()`
and `notificationRepeated()` signals. Only plain QtQuick plus those objects may
be used here — no Quickshell, no Kos.Ui.

## Development loop

```sh
# Make the package visible to the greeter (user level, no root). Note the
# plasma/shells/ root: the greeter resolves its skin from a Shell package, and
# look-and-feel/ is not searched for the lock screen at all -- both conditions
# are verified by tests/theme-resolution.
mkdir -p ~/.local/share/plasma/shells
ln -s "$PWD" ~/.local/share/plasma/shells/org.kos.desktop
kwriteconfig6 --file plasmashellrc --group Shell --key ShellPackage org.kos.desktop

# Offscreen assertions + a rendered preview, no real lock needed:
./tests/headless/run.sh

# See it on the real greeter:
/usr/lib/kscreenlocker_greet --testing
```

Every lock spawns a fresh greeter process, so edited QML takes effect on the
next lock — no shell or compositor restart. Switch to it with "Global Theme →
KOS Lock Screen" in System Settings (or `kdeglobals [KDE] LookAndFeelPackage`).

## Input

A password field, nothing else — no numeric keypad. An account password is an
arbitrary string (letters, punctuation, spaces), and a digits-only UI would
lock some users out of their own session. Enter submits, Escape clears the
field and asks the greeter to forget the pending secret, "显示密码" toggles
cleartext, and a caps-lock hint appears while caps lock is on (via
`org.kde.plasma.private.keyboardindicator`, the same module upstream uses).

## The wallpaper, and why the theme draws it again

The `wallpaper` the greeter hands over is the root item of a wallpaper package.
`org.kde.image` paints through a C++ `TransientImage` whose texture is built
from the geometry the item had *when it loaded* — geometry that belongs to the
greeter, and that this theme only takes over afterwards. On a HiDPI panel (this
project's is 3840x2160 at scale 2) that texture can stop at the logical size, so
a 1920x1080 picture gets stretched over 3840x2160 physical pixels: the wallpaper
reads as "a very low resolution image". Those pixels are gone — grabbing the
item, playing with `layer`, or nudging the package into re-decoding all end up
sampling the same undersized texture.

So the theme does not use its pixels. After adopting the item it walks that
subtree depth-first for the still image the package resolved (name resolution
and `#dark`-style fragments are already done in there, so reading the result
beats reading the config), then decodes that file itself with a plain `Image`
and `sourceSize = size x devicePixelRatio`, drawn over the package's own copy.
When no file is found (animated or video wallpapers) nothing is drawn and the
greeter's picture is what shows.

Two details that come with it: the walk is retried every 5s, because the package
builds its image after we adopt it and a slideshow swaps files underneath us;
and the URL has to be absolute, because a relative one is resolved against the
file that wrote it — the package, not us — so relative URLs are left alone.

**The diagnostic switch**: set `debug: true` at the top of `LockScreen.qml` and
the lock screen paints screen size / dpr / root size / the injected item's size
and layer / what the walk found / what we decode and the Image status into its
top-left corner. This theme runs in a process nothing can attach to, so that
readout is the only way to see what it actually received.

**Do not "fix" softness with a larger `FastBlur` radius.** It picks its internal
resolution from the absolute radius: at radius 64 roughly 80% of every output
pixel comes from the 1/16 and 1/32 buffers — 120x67 and 60x34 on a 1080p display
— which is not "a blurred wallpaper" but "a low resolution picture", and only
looks softer. Use `MultiEffect` if a heavier blur is really wanted.

## Later

- ~~Wire the package into `tools/kosctl` deployment~~ done:
  `KOS_INSTALL_LOCKSCREEN=1 ./tools/kosctl install` ships it to
  `$prefix/share/plasma/shells/` **and** `$prefix/share/plasma/look-and-feel/`
  (the greeter only searches the former; the latter is for
  `plasma-apply-lookandfeel` and the settings page) and points
  `plasmashellrc [Shell] ShellPackage` at it; `kosctl sync` refreshes the
  package too. NixOS (`nix/package.nix`) is still open — otherwise NixOS
  installs will not ship it (the same gap that hit `Kos.SurfaceShape`).
- Unlock/lock transition animations (the KWin-side "suck the windows in"
  prototype lives in the vendored effect, not here).
