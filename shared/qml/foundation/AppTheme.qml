pragma Singleton

import QtQuick

QtObject {
    id: theme

    // KosApplicationWindow binds these values to the shared C++ preferences
    // object. Controls can stay application-agnostic and still update live.
    property string appearanceMode: "system"
    property string materialMode: "auto"
    property real materialOpacity: 0.86
    property string accentName: "system"
    property bool reduceTransparency: false
    property bool reduceMotion: false
    property bool nativeBlurAvailable: false

    readonly property SystemPalette systemPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }

    readonly property color lightWindowSeed: "#f3f6fb"
    readonly property color lightBaseSeed: "#ffffff"
    readonly property color lightSidebarSeed: "#e8eef7"
    readonly property color lightTextSeed: "#172033"
    readonly property color darkWindowSeed: "#151a23"
    readonly property color darkBaseSeed: "#202733"
    readonly property color darkSidebarSeed: "#263142"
    readonly property color darkTextSeed: "#f4f7fb"
    readonly property color defaultAccentSeed: "#3478f6"
    readonly property color purpleAccentSeed: "#8b5cf6"
    readonly property color greenAccentSeed: "#16875f"
    readonly property color orangeAccentSeed: "#d66a20"
    readonly property color blackSeed: "#000000"
    readonly property color whiteSeed: "#ffffff"

    // Headless QPA plugins and partially configured themes can expose a
    // transparent or same-colour palette. Treat that as unavailable instead
    // of turning an application window into a transparent black surface.
    readonly property bool systemPaletteValid: {
        const background = systemPalette.window
        const foreground = systemPalette.windowText
        return background.a > 0.01 && foreground.a > 0.01
            && Math.abs(relativeLuminance(background)
                        - relativeLuminance(foreground)) > 0.18
    }
    readonly property color rawSystemWindow: systemPaletteValid
        ? opaque(systemPalette.window) : lightWindowSeed
    readonly property bool systemDark: relativeLuminance(rawSystemWindow) < 0.28
    readonly property bool dark: appearanceMode === "dark"
        || (appearanceMode !== "light" && systemDark)
    readonly property bool followsSystemAppearance:
        appearanceMode !== "light" && appearanceMode !== "dark"

    readonly property color paletteWindow: followsSystemAppearance && systemPaletteValid
        ? opaque(systemPalette.window) : (dark ? darkWindowSeed : lightWindowSeed)
    readonly property color paletteBase: followsSystemAppearance
            && systemPaletteValid && systemPalette.base.a > 0.01
        ? opaque(systemPalette.base) : (dark ? darkBaseSeed : lightBaseSeed)
    readonly property color paletteText: followsSystemAppearance && systemPaletteValid
        ? opaque(systemPalette.windowText) : (dark ? darkTextSeed : lightTextSeed)
    readonly property color systemAccent: systemPaletteValid
            && systemPalette.highlight.a > 0.01
        ? opaque(systemPalette.highlight) : defaultAccentSeed
    readonly property color accent: {
        if (accentName === "blue") return defaultAccentSeed
        if (accentName === "purple") return purpleAccentSeed
        if (accentName === "green") return greenAccentSeed
        if (accentName === "orange") return orangeAccentSeed
        return systemAccent
    }

    // Forced Light/Dark modes never inherit the opposite system background.
    readonly property color window: mix(
        paletteWindow, dark ? darkWindowSeed : lightWindowSeed,
        followsSystemAppearance ? (dark ? 0.52 : 0.16) : 0.08)
    readonly property color windowTint: mix(window, accent, dark ? 0.07 : 0.045)
    readonly property color windowRaised: mix(
        paletteBase, dark ? darkBaseSeed : lightBaseSeed,
        followsSystemAppearance ? (dark ? 0.48 : 0.16) : 0.08)
    readonly property color sidebar: mix(
        window, dark ? darkSidebarSeed : lightSidebarSeed, 0.58)
    readonly property color card: mix(windowRaised, accent, dark ? 0.035 : 0.018)
    readonly property color cardHover: mix(card, accent, dark ? 0.10 : 0.065)
    readonly property color field: mix(card, window, dark ? 0.20 : 0.34)
    readonly property color button: mix(windowRaised, accent, dark ? 0.085 : 0.045)
    readonly property color buttonHover: mix(button, accent, dark ? 0.13 : 0.09)
    readonly property color buttonPressed: mix(button, accent, dark ? 0.21 : 0.16)

    readonly property bool glassActive: !reduceTransparency
        && (materialMode === "glass"
            || (materialMode === "auto" && nativeBlurAvailable))
    readonly property real effectiveMaterialOpacity: !glassActive ? 1.0
        : (nativeBlurAvailable
           ? clamp(materialOpacity, 0.72, 0.98)
           : Math.max(0.93, clamp(materialOpacity, 0.72, 0.98)))
    readonly property color windowSurface: withAlpha(
        window, effectiveMaterialOpacity)
    readonly property color windowTintSurface: withAlpha(
        windowTint, effectiveMaterialOpacity)
    readonly property color sidebarSurface: withAlpha(
        sidebar, glassActive ? (nativeBlurAvailable ? 0.36 : 0.32) : 1)
    readonly property color cardSurface: withAlpha(
        card, glassActive ? (nativeBlurAvailable ? 0.54 : 0.46) : 1)
    readonly property color fieldSurface: withAlpha(
        field, glassActive ? (nativeBlurAvailable ? 0.62 : 0.54) : 1)

    readonly property color border: dark
        ? Qt.rgba(1, 1, 1, 0.13)
        : Qt.rgba(0.10, 0.16, 0.25, 0.14)
    readonly property color text: paletteText
    readonly property color mutedText: mix(paletteText, window, dark ? 0.46 : 0.36)
    readonly property bool accentUsesDarkText:
        contrastRatio(accent, blackSeed) >= contrastRatio(accent, whiteSeed)
    readonly property color accentText: accentUsesDarkText
        ? blackSeed : whiteSeed
    // Move interaction states away from their foreground luminance so hover
    // and pressed feedback improves contrast instead of washing text out.
    readonly property color accentHover: mix(
        accent, accentUsesDarkText ? whiteSeed : blackSeed, 0.10)
    readonly property color accentPressed: mix(
        accent, accentUsesDarkText ? whiteSeed : blackSeed, 0.18)
    readonly property color positive: dark ? "#30d58a" : "#16875f"
    readonly property color warning: dark ? "#ffb340" : "#b96800"
    readonly property color destructive: dark ? "#ff6961" : "#d83b3b"

    readonly property int smallRadius: 10
    readonly property int mediumRadius: 16
    readonly property int largeRadius: 24
    readonly property int spacing: 12
    readonly property int pageMargin: 24
    readonly property real densityScale: Math.max(0.88, Math.min(1.28,
        (Application.font.pixelSize > 0 ? Application.font.pixelSize : 13) / 13))
    readonly property int controlHeight: Math.round(36 * densityScale)
    readonly property int sidebarWidth: Math.round(246 * densityScale)
    readonly property int compactSidebarWidth: Math.round(196 * densityScale)
    readonly property int motionFast: reduceMotion ? 0 : 120
    readonly property int motionNormal: reduceMotion ? 0 : 220

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function withAlpha(colorValue, alpha) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b,
                       clamp(alpha, 0, 1))
    }

    function opaque(colorValue) {
        return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, 1)
    }

    function mix(first, second, secondAmount) {
        const amount = clamp(secondAmount, 0, 1)
        return Qt.rgba(first.r * (1 - amount) + second.r * amount,
                       first.g * (1 - amount) + second.g * amount,
                       first.b * (1 - amount) + second.b * amount,
                       1)
    }

    function linearChannel(value) {
        return value <= 0.04045 ? value / 12.92
                                : Math.pow((value + 0.055) / 1.055, 2.4)
    }

    function relativeLuminance(colorValue) {
        return linearChannel(colorValue.r) * 0.2126
            + linearChannel(colorValue.g) * 0.7152
            + linearChannel(colorValue.b) * 0.0722
    }

    function contrastRatio(first, second) {
        const firstLuma = relativeLuminance(first)
        const secondLuma = relativeLuminance(second)
        return (Math.max(firstLuma, secondLuma) + 0.05)
            / (Math.min(firstLuma, secondLuma) + 0.05)
    }
}
