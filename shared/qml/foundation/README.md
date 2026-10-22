# Foundation

[English architecture](../../../docs/Architecture.md) · [简体中文](../../../docs/Architecture.zh-CN.md)

Canonical Qt Quick AppTheme, application controls, window infrastructure and
kinetic scrolling exported by `Kos.Ui`. This directory does not import Quickshell,
KWin, NextKde services or Wayland-specific modules. Optional application preference
objects are supplied by consuming applications; no native blur bridge is included.

Keep the CMake module, local qmldir and demo facade synchronized when adding types.
See [component integration](../../../docs/Components.md) for examples and state ownership.
