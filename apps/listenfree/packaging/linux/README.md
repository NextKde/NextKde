# KOS ListenFree Linux build

KOS ListenFree is the NextKDE adaptation of ListenFree. It is installed as
`listenfree`, with desktop ID `listenfree.desktop`, and replaces the legacy
`kos-music` installation. The old source and user data remain available. Keep the upstream component notices in
`licenses/` when distributing a build. The existing ListenFree data directory
and MPRIS name remain compatible across upgrades.

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
