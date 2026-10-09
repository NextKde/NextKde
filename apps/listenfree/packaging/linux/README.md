# KOS ListenFree Linux build

KOS ListenFree is the NextKDE adaptation of ListenFree. It is installed as
`listenfree`, with desktop ID `listenfree.desktop`, and replaces the legacy
`kos-music` installation. The old source and user data remain available. Keep the upstream component notices in
`licenses/` when distributing a build. The existing ListenFree data directory
and MPRIS name remain compatible across upgrades.

For the complete NextKDE application bundle, run:

```sh
./tools/kosctl install apps
```

The installer checks dependencies and prints missing package names and install
commands for Arch and Ubuntu. It requires Qt 6.10+ (Arch rolling / Ubuntu
26.04+ stock packages), KDE Frameworks 6 and Go 1.26+ for the data service.
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
Qt 6.10+, Qt WebEngine, KDE Frameworks 6 WindowSystem, FFmpeg, OpenSSL, zlib and
ICU development files must also be available. Individual `LISTENFREE_*` CMake
paths can be used instead of the SDK layout.

The executable and private audio runtime install under `opt/listenfree` within
the chosen prefix. The launcher sets the private library and plugin paths.
After installation run `update-desktop-database PREFIX/share/applications`.
NextKDE's `tools/register-default-apps.py` migrates legacy music associations, retains other chosen defaults, backs up and removes the old installed music files, and retires temporary Todo/Calendar/Weather preview entries.
File-manager launches accept paths and file URLs, including multiple files;
subsequent launches deliver those files to the resident instance.

This component has its own dependency and test requirements. NextKDE's ordinary
data/service test preset does not implicitly enable it. Run its CTest suites from
the configured build with the private libraries and Qmmp plugins on their paths.
