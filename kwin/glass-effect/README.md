# NextKDE Glass effect

This directory contains NextKDE's modified Glass effect, based on the
[upstream Glass project](https://github.com/4v3ngR/kwin-effects-glass), a fork of
Plasma's blur effect. Its settings and shader capabilities are not the NextKDE
product contract; Shell surface behavior is defined by the shared tokens and
versioned surface-shape protocol.

## Integration and maintenance

- Use [Getting started](../../docs/GettingStarted.md) for NextKDE installation and
  updates, and [Development](../../docs/Development.md) for VM/CI builds.
- [Appearance architecture](../../docs/AppearanceArchitecture.md) owns Shell
  material presets, opacity and scrim. [Window appearance](../../docs/WindowAppearance.md)
  owns compositor integration and the surface-shape protocol.
- [Effect configuration](docs/configuration.md) describes the underlying options.
  Upstream screenshots and standalone package instructions remain in the
  [upstream README](https://github.com/4v3ngR/kwin-effects-glass/blob/main/README.md).
- Rebuild native plugins after an incompatible KWin/Qt upgrade, then log out/in or
  reboot. Do not hot-replace plugins in a running compositor. The three SDK CI
  builds do not replace live VM acceptance.

Glass conflicts with the stock blur effect and other blur forks. The Plasma
Translucency effect can also reduce blur strength; investigate those interactions
before changing NextKDE material settings. Ordinary window-rule transparency and
an application's declared blur region follow different paths; see the configuration guide.

## Provenance

Keep the source SPDX copyright/license notices and the bundled [license](LICENSE).
Upstream credits include [a-parhom/LightlyShaders](https://github.com/a-parhom/LightlyShaders)
for CMake files, [PKMNPlatin](https://github.com/PKMNPlatin/kwin-effects-snell-glass)
for refraction work, and [avitretiak](https://github.com/avitretiak) /
[dnmodder](https://github.com/dnmodder) for compatibility patches.
