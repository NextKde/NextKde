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
    readonly property color darkBg: Qt.rgba(0, 0, 0, 0.1)
    readonly property color darkFg: Qt.rgba(1.0, 1.0, 1.0, 0.92)
    readonly property color darkAccent: Qt.rgba(0.20, 0.60, 1.0, 1.0)
    readonly property color darkDivider: Qt.rgba(1.0, 1.0, 1.0, 0.15)
    readonly property color darkTooltipBg: Qt.rgba(0.18, 0.18, 0.20, 0.95)
    readonly property color darkIndicator: Qt.rgba(0.20, 0.60, 1.0, 0.85)
    readonly property color darkBorder: Qt.rgba(1.0, 1.0, 1.0, 0.10)
    readonly property color darkHighlight: Qt.rgba(1.0, 1.0, 1.0, 0.28)

    // ═══════════════════════════════════════════════════
    // Light palette
    // ═══════════════════════════════════════════════════
    readonly property color lightBg: Qt.rgba(0.95, 0.95, 0.97, 0.35)
    readonly property color lightFg: "#000000"
    readonly property color lightAccent: Qt.rgba(0.0, 0.50, 0.90, 1.0)
    readonly property color lightDivider: Qt.rgba(0.0, 0.0, 0.0, 0.12)
    readonly property color lightTooltipBg: Qt.rgba(0.92, 0.92, 0.94, 0.95)
    readonly property color lightIndicator: Qt.rgba(0.0, 0.50, 0.90, 0.75)
    readonly property color lightBorder: Qt.rgba(0.0, 0.0, 0.0, 0.10)
    readonly property color lightHighlight: Qt.rgba(1.0, 1.0, 1.0, 0.55)

    // ═══════════════════════════════════════════════════
    // Exposed (reactively toggled)
    // ═══════════════════════════════════════════════════
    readonly property color backgroundColor: isDark ? darkBg : lightBg
    readonly property color foregroundColor: isDark ? darkFg : lightFg
    readonly property color accentColor: isDark ? darkAccent : lightAccent
    readonly property color dividerColor: isDark ? darkDivider : lightDivider
    readonly property color tooltipBackground: isDark ? darkTooltipBg : lightTooltipBg
    readonly property color indicatorColor: isDark ? darkIndicator : lightIndicator
    readonly property color borderColor: isDark ? darkBorder : lightBorder
    readonly property color highlightColor: isDark ? darkHighlight : lightHighlight
}
