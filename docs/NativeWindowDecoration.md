# KOS native decoration controls

[简体中文](NativeWindowDecoration.zh-CN.md)

Server-decorated applications such as Konsole use actual KDecoration buttons
owned by `kos_decoration`. Green maximizes/restores, yellow minimizes and red
closes. Bridge neither paints over them nor samples their background. They do
not participate in overlay right-click placement adjustment.

Button positions and ordering follow KDE's left/right decoration button lists.
The centered caption reserves space for both groups and elides as needed.
Optional KDE menu, pin, shade and stacking controls retain their native actions.
Traffic lights accept left-click; green does not enter fullscreen.

KOS window appearance remains the common switch; always/hover glyph preference
is read from the same configuration as other KOS controls. Legacy overlay
geometry, tint, showButtons and forced-paint rules do not override native
controls. Their saved values remain available for fallback CSD applications.

Bridge recognizes `_kos_native_decoration_controls`, drops old hit regions and
tint timers and skips the overlay even with an `always` override. Old decorations
without this capability retain the fallback so mixed-version upgrades do not
remove their only controls. Install both plugins and load them at the next login;
do not hot-reload a running KWin plugin.

Calendar, Weather and Settings retain [cooperative controls](CooperativeWindowControls.md).
Firefox retains its [own chrome buttons](FirefoxWindowButtons.md). Unadapted CSD
applications retain overlay fallback. All automated validation is VM-only; see
[acceptance instructions](../tests/native-decoration/README.md).

Forma/Mayonnaise applications draw and hit-test their own OpenGL traffic lights.
Bridge preserves those controls on CSD windows identified by the verified
Mayonnaise desktop IDs (Calculator, Finder, Music, Photos, Settings, TaskManager,
Terminal, TextEditor, VideoPlayer) and Forma IDs (AppStore, Mail, PolkitAgent,
Screenshot). Matching uses the exact Wayland app ID or X11 class token, not a
title, executable name or namespace prefix. Overlay geometry and forced-paint
rules do not override that ownership. Bridge clears old overlay hit regions,
adjust sessions and tint caches, so these windows incur no overlay sampling.
Server-decorated windows retain their decoration's controls. Explicit cooperative
surface negotiation continues to take precedence over this application policy.
