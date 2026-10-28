# Canonical Demo controls

This module packages the required controls from `nextkdeAppDemo/shared/qml` under
`Kos.Demo` so Calendar and Settings use the actual Demo implementations without changing other
apps' legacy `Kos.Ui` module. QML, GLSL and QSB files are byte-for-byte copies of the
canonical Demo sources; upstream-sha256.json records each synchronized file.
The namespace/build metadata are the only packaging additions. Preserve the GPL-3.0
license of the parent project and upstream. Do not edit visual implementations here:
update the canonical Demo first, then sync source/assets and hashes together.

Hosts supply geometry, state, theme preferences and real sibling capture sources.
They must not recreate optical layers or animations around these controls. The
liquid controls retain their glass edge on keyboard focus without an accent outline.
Solid keyboard focus remains semantic. Tooltips use the same shared liquid material
at 0.7 coverage, 14 px corners and 11 px opaque secondary text; their capture source
must exclude the popup overlay.
