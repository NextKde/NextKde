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
    blurOverrideEnabled: true
    // The normalized minimum maps to KWin blur level 1.
    blurStrength: 0
    scrimEnabled: AppearanceTokens.surface.usesBackdrop
    scrimLevel: "transparent"
    ambientPrimary: WallpaperColorSource.primary
    ambientSecondary: WallpaperColorSource.secondary
    ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
}
