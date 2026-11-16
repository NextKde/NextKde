pragma Singleton
import QtQuick

// Host-declared in-scene backdrop for the QML glass fallback. The item is
// usually a hidden copy of the scene backdrop: LiquidGlassSurface captures
// it with hideSource, so it never paints but still feeds every surface.
// Null keeps every existing surface on its previous path.
QtObject {
    property Item sourceItem: null

    // KWin scrim presets. The compositor path (LiquidGlassPanel) and the QML
    // fallback (LiquidGlassSurface) must compress a backdrop identically, so
    // both resolve their cap/decay here instead of carrying private copies.
    function scrimCap(level) {
        return level === "readable" ? 0.72
            : level === "balanced" ? 0.47
            : level === "transparent" ? 0.22
            : level === "subtle" ? 0.15 : 0.5
    }
    function scrimDecay(level) {
        return level === "readable" ? 1.0
            : level === "balanced" ? 0.75
            : level === "transparent" ? 0.5
            : level === "subtle" ? 0.45 : 1.0
    }

    // Which way the scrim pushes. Same rule as the compositor path: follow the
    // appearance switch when the user enabled it, otherwise stay black.
    readonly property int defaultScrimTint:
        AppearanceConfigService.glassFollowsAppearanceMode
            ? (AppearanceTokens.isDarkTheme ? 0 : 1) : 0
}
