import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// One material recipe for controls, notifications and their glass buttons.
// Hosts supply geometry, clipping and transition opacity, not a second tint.
LiquidGlassPanel {
    cornerExponent: 2.0
    baseColor: ThemeService.backgroundColor
    material: "regular"
    materialDepth: 0
    blurSigma: tonal ? -1 : Math.max(6, 18 * AppearanceConfigService.effectiveLauncherBlur)
    scrimEnabled: AppearanceTokens.surface.usesBackdrop
    scrimLevel: AppearanceTokens.bar.popupScrimLevel
    ambientPrimary: WallpaperColorSource.primary
    ambientSecondary: WallpaperColorSource.secondary
    ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
}
