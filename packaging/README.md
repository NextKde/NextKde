# Packaging

Cross-project release packaging, generated templates, and legacy launchers
belong here. The four independent application modules keep their final desktop
entries beside their source under `apps/<name>/data/`; CMake installs each
entry with its owning executable so a one-app build stays self-contained.

`packaging/desktop/kos-settings.desktop.in` remains a template because the
pre-existing Settings application still uses its separate build path. D-Bus
service files and autostart entries for shared services remain beside the
service CMake target that installs them.
