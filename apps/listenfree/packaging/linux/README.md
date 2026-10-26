# KOS ListenFree Linux build

[简体中文](README.zh-CN.md)

KOS ListenFree is the NextKDE adaptation of ListenFree. It is installed as
`listenfree`, with desktop ID `listenfree.desktop`, and replaces the legacy
`kos-music` installation. The old source and user data remain available. Keep the upstream component notices in
`licenses/` when distributing a build. The existing ListenFree data directory
and MPRIS name remain compatible across upgrades.

To include ListenFree in the NextKDE application installation, explicitly opt in:

```sh
./tools/kosctl install apps --with-listenfree
```

Without `--with-listenfree`, only Calendar, Calculator, Todo and Weather are installed.

The audio-enabled installer checks dependencies and prints missing package names and install
commands for Arch and Ubuntu. It requires Qt 6.10+ (with a matching Qt/KF6 toolchain), KDE Frameworks 6 and Go 1.26+ for the data service.
Older Ubuntu stock Qt cannot satisfy this requirement; installing the same
old package again is insufficient. A complete compatible Qt/KF6 toolchain
can be supplied through the usual CMake and pkg-config search paths.

QuickJS-ng 0.16.2 and patched Qmmp 2.4.1 are downloaded, SHA-256 verified,
built and cached privately under `.build/listenfree-sdk`. TagLib 2.3.1 is
also built privately when the system version is insufficient. No root access
is used for these builds. System dependencies remain managed by the distribution.
The first build needs network access; valid sources and SDK artifacts are reused.
To prepare only the SDK, run `./tools/prepare-listenfree-sdk.sh`.
An existing compatible SDK can still be supplied with `KOS_LISTENFREE_SDK`.

Build independently, or enable `KOS_BUILD_LISTENFREE` in the NextKDE tree:

```sh
cmake -S apps/listenfree -B .build/listenfree -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
  -DKOS_LISTENFREE_SDK=/path/to/listenfree-sdk \
  -DLISTENFREE_BUILD_TESTS=ON
cmake --build .build/listenfree --target listenfree listenfree-sourcehost
cmake --install .build/listenfree
```

From a standalone ListenFree checkout, use `-S .` instead. The SDK is a dependency
prefix, not a copy of user settings. Its layout is `prefix/` (TagLib 2.3.1,
QuickJS-ng 0.16.2, patched Qmmp 2.4.1 and plugins), `vendor/qmmp-2.4.1/` (the
corresponding patched sources), and optionally `deps/usr/` for matching native
development packages. Qmmp patch order is documented in
`licenses/THIRD-PARTY-NOTICES.txt`; source and binary plugins must use the same
patch set. Do not use the unmodified system Qmmp as a drop-in replacement.
Qt 6.10+, KDE Frameworks 6 WindowSystem, FFmpeg, OpenSSL, zlib and
ICU development files must also be available. Individual `LISTENFREE_*` CMake
paths can be used instead of the SDK layout.

The executable and private audio runtime install under `opt/listenfree` within
the chosen prefix. The launcher sets the private library and plugin paths.
After installation run `update-desktop-database PREFIX/share/applications`.
NextKDE's `tools/register-default-apps.py --with-listenfree` migrates legacy music associations, retains other chosen defaults, backs up and removes the old installed music files, and retires temporary Todo/Calendar/Weather preview entries.
File-manager launches accept paths and file URLs, including multiple files;
subsequent launches deliver those files to the resident instance.

Run contributor builds, tests and runtime verification only in a VM or hosted CI.
This component has its own dependency and test requirements. NextKDE's ordinary
data/service test preset does not implicitly enable it. Run its CTest suites from
the configured build with the private libraries and Qmmp plugins on their paths.

## Optional features and installation size

The default player requires neither Qt WebEngine nor Qt Multimedia. Local/online
audio, Cookie login, static artwork, lyrics and spectrum visualizations remain available.
FFmpeg remains an audio decoding/HLS dependency; disabling video does not remove it.

| CMake option | Default | Effect |
| --- | --- | --- |
| `LISTENFREE_BUILD_WEB_LOGIN` | `OFF` | Builds the separate `listenfree-web-login` executable; requires Qt WebEngine. |
| `LISTENFREE_BUILD_VIDEO` | `OFF` | Enables MV playback, animated artwork and local/Wallpaper Engine video backgrounds; requires Qt Multimedia and its QML module. |
| `LISTENFREE_BUILD_TOOLS` | `OFF` | Includes development probes and benchmarks in the default build. |
| `LISTENFREE_STRIP_INSTALL` | `ON` | Strips Release installations, including copied private audio libraries/plugins; keeps build-tree symbols. |

Enable video with `./tools/kosctl install apps --with-listenfree-video`, or configure
`-DLISTENFREE_BUILD_VIDEO=ON` directly. Turning it off excludes the video native sources
and video QML files from the application, hides their controls, and falls back to static
artwork/automatic backgrounds for saved video preferences. Lyrics and spectrum remain
usable. The installer explicitly resets both optional flags on each run, so an old CMake
cache cannot silently restore heavy dependencies.

Web login is selected at login time. If the helper is absent, the login action offers
installation instructions and Cookie login remains available. Build/install the helper
independently using the [bundled instructions](../web-login/install.txt); no audio SDK is
needed for that build. Alternatively enable `LISTENFREE_BUILD_WEB_LOGIN=ON` in the player
build and install it explicitly with:

```sh
cmake --install .build/listenfree --component listenfree-web-login --strip
```

A normal player installation never includes the helper, even when its build option is ON.
Package maintainers should place its WebEngine dependency on the optional package only.
The player searches beside its executable, then PATH. The helper accepts a provider ID and
the existing profile directory, verifies login, and saves credentials in the same system
keyring namespace. Exit code 0 triggers account refresh; 1 means cancellation. Failure or
a ten-minute timeout does not terminate the player. Cookie values never travel through
process arguments, logs or temporary files. Install the helper from the same revision as
the player and into the same prefix.

Use `-DLISTENFREE_STRIP_INSTALL=OFF` without `cmake --install --strip` to retain installed
Release symbols for diagnostics. Debug/RelWithDebInfo installations retain symbols unless
`--strip` is explicitly requested. Distribution debug packages can extract symbols from
the build tree before stripping. The NextKDE app installer uses `--strip` explicitly.

For feature changes, test OFF/OFF, ON/OFF, OFF/ON and ON/ON configurations in a VM/CI.
Run CTest with `QT_QPA_PLATFORM=offscreen`, `QMMP_PLUGINS` and the private library path set;
video/rendering tests also need a VM graphical session. Check the light installed ELF
closure and launch it with the optional runtime libraries/QML module unavailable, including
settings and immersive views with pre-existing video preferences. Install the helper through
its explicit component and verify that a normal install leaves it absent.
