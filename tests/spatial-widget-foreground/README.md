# Desktop subject occlusion

Run `python3 tests/spatial-widget-foreground/run.py` in a Wayland session with
Quickshell, QtTest and Pillow available. Build `kos_spatial3d` first. The default
plugin import root is `.build/kosctl/qml`; override it with
`SPATIAL_QML_IMPORT_PATH` for another build directory.

The fixture uses the production renderers with generated RGB images, a
subject matte and 16-bit depth. It checks both shader fallback and actual 3D mesh
rendering, full subject occlusion through card centers, transparent matte regions,
file protection even inside widget bounds, per-widget hover reveal and restoration,
mouse clicks through the subject, editing, movement and empty layouts.
QML state is confined to fixture singletons and never writes the user's settings.
Captured images and runtime logs are saved under `tmp/spatial-widget-*`.
