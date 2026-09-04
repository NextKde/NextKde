pragma Singleton
import QtQuick

// ────────────────────────────────────────────────────────────────
// DockThemeService — Dark / light colour palette.
// Switches reactively when ConfigService.theme changes.
// Every visual component binds to these colours; no hardcoded values.
// ────────────────────────────────────────────────────────────────

QtObject {
    id: svc

    property SystemPalette systemPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }

    readonly property bool systemIsDark: {
        const color = systemPalette.window
        return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 < 0.5
    }
    // The user can explicitly select light/dark or follow the Qt/KDE palette.
    property bool isDark: ConfigService.theme === "system"
        ? systemIsDark : ConfigService.theme !== "light"

    // ═══════════════════════════════════════════════════
    // Dark palette
    // ═══════════════════════════════════════════════════
    // Liquid Glass keeps a neutral, theme-stable body behind its adaptive
    // reflections.  The material may borrow colour from the wallpaper, but
    // it must not borrow so much luminance that label contrast collapses.
    readonly property color darkBg: Qt.rgba(0.055, 0.065, 0.090, 0.72)
    readonly property color darkFg: Qt.rgba(0.985, 0.990, 1.000, 1.0)
    readonly property color darkSecondaryFg: Qt.rgba(0.985, 0.990, 1.000, 0.82)
    readonly property color darkTertiaryFg: Qt.rgba(0.985, 0.990, 1.000, 0.62)
    readonly property color darkAccent: Qt.rgba(0.20, 0.60, 1.0, 1.0)
    readonly property color darkDivider: Qt.rgba(1.0, 1.0, 1.0, 0.18)
    readonly property color darkTooltipBg: Qt.rgba(0.18, 0.18, 0.20, 0.95)
    readonly property color darkIndicator: Qt.rgba(0.20, 0.60, 1.0, 0.85)
    readonly property color darkBorder: Qt.rgba(1.0, 1.0, 1.0, 0.16)
    readonly property color darkHighlight: Qt.rgba(1.0, 1.0, 1.0, 0.28)

    // ═══════════════════════════════════════════════════
    // Light palette
    // ═══════════════════════════════════════════════════
    readonly property color lightBg: Qt.rgba(0.940, 0.950, 0.975, 0.78)
    readonly property color lightFg: Qt.rgba(0.055, 0.065, 0.085, 1.0)
    readonly property color lightSecondaryFg: Qt.rgba(0.055, 0.065, 0.085, 0.72)
    readonly property color lightTertiaryFg: Qt.rgba(0.055, 0.065, 0.085, 0.62)
    readonly property color lightAccent: Qt.rgba(0.0, 0.50, 0.90, 1.0)
    readonly property color lightDivider: Qt.rgba(0.055, 0.065, 0.085, 0.16)
    readonly property color lightTooltipBg: Qt.rgba(0.92, 0.92, 0.94, 0.95)
    readonly property color lightIndicator: Qt.rgba(0.0, 0.50, 0.90, 0.75)
    readonly property color lightBorder: Qt.rgba(0.055, 0.065, 0.085, 0.14)
    readonly property color lightHighlight: Qt.rgba(1.0, 1.0, 1.0, 0.55)

    // ═══════════════════════════════════════════════════
    // Exposed (reactively toggled)
    // ═══════════════════════════════════════════════════
    readonly property color backgroundColor: isDark ? darkBg : lightBg
    readonly property color foregroundColor: isDark ? darkFg : lightFg
    readonly property color secondaryForegroundColor: isDark
        ? darkSecondaryFg : lightSecondaryFg
    readonly property color tertiaryForegroundColor: isDark
        ? darkTertiaryFg : lightTertiaryFg
    readonly property color accentColor: isDark ? darkAccent : lightAccent
    readonly property color dividerColor: isDark ? darkDivider : lightDivider
    readonly property color tooltipBackground: isDark ? darkTooltipBg : lightTooltipBg
    readonly property color indicatorColor: isDark ? darkIndicator : lightIndicator
    readonly property color borderColor: isDark ? darkBorder : lightBorder
    readonly property color highlightColor: isDark ? darkHighlight : lightHighlight
}
