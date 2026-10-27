# Canonical Demo controls

This module packages the required controls from `nextkdeAppDemo/shared/qml` under
`Kos.Demo` so Calendar uses the actual Demo implementations without changing other
apps' legacy `Kos.Ui` module. QML, GLSL and QSB files are byte-for-byte copies of the
maintainer's Demo working tree on 2026-10-27; upstream-sha256.json records each file.
The namespace/build metadata are the only packaging additions. Preserve the GPL-3.0
license of the parent project and upstream. Do not edit visual implementations here:
update the canonical Demo first, then sync source/assets and hashes together.

Hosts supply geometry, state, theme preferences and real sibling capture sources.
They must not recreate optical layers or animations around these controls. The
current upstream action button still exposes a legacy focus ring: Calendar uses its
supported focusRingColor property to hide it on liquid material only, as required
by the newer Demo focus contract. Solid keyboard focus remains semantic.
