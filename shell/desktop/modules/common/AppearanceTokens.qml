pragma Singleton
import QtQuick

// Semantic shell-shape values. Consumers should depend on these roles instead
// of branching on shellStyle themselves. Values describe geometry and motion;
// color continues to come from the active system palette and semantic roles.
QtObject {
    id: tokens

    readonly property int version: 8
    readonly property string style: AppearanceConfigService.shellStyle
    readonly property bool isWindows12: style === "windows12"
    readonly property bool isMacos: style === "macos"
    readonly property bool isMaterial: style === "material"

    readonly property SystemPalette systemPalette: SystemPalette {
        colorGroup: SystemPalette.Active
    }
    readonly property color seedColor: AppearanceConfigService.wallpaperSeedColor.a > 0
        ? AppearanceConfigService.wallpaperSeedColor : systemPalette.highlight
    readonly property bool systemIsDark: systemPalette.window.r * 0.2126
        + systemPalette.window.g * 0.7152
        + systemPalette.window.b * 0.0722 < 0.5
    // Explicit light/dark choices must override KDE; only "system" follows
    // SystemPalette. Material therefore selects the corresponding matugen
    // light or dark scheme instead of imposing one mode on both choices.
    readonly property bool isDarkTheme:
        AppearanceConfigService.themeMode === "dark" ? true
        : AppearanceConfigService.themeMode === "light" ? false
        : systemIsDark

    function _mix(base, tint, amount, alpha) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount,
            base.g + (tint.g - base.g) * amount,
            base.b + (tint.b - base.b) * amount,
            alpha === undefined ? 1.0 : alpha)
    }

    function _luminance(value) {
        return value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
    }

    // Tonal-Spot-style fallback used when no external Material color utility
    // is installed. It creates the same semantic tone ladder as M3; a future
    // HCT/matugen loader can replace the role values without touching views.
    function _tone(source, hueShift, saturationScale, lightness, alpha) {
        const hue = (source.hslHue < 0 ? 0 : source.hslHue)
        const shiftedHue = (hue + hueShift + 1.0) % 1.0
        const saturation = Math.max(0.08, Math.min(0.72,
            source.hslSaturation * saturationScale))
        return Qt.hsla(shiftedHue, saturation, lightness,
            alpha === undefined ? 1.0 : alpha)
    }

    readonly property QtObject colors: QtObject {
        readonly property color primary: MaterialThemeService.color("primary", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 1.0, tokens.isDarkTheme ? 0.80 : 0.40))
        readonly property color primaryForeground: MaterialThemeService.color("on_primary", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#221a00" : "#ffffff")
        readonly property color primaryContainer: MaterialThemeService.color("primary_container", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.82, tokens.isDarkTheme ? 0.30 : 0.90))
        readonly property color primaryContainerForeground: MaterialThemeService.color("on_primary_container", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#f7f2fa" : "#1d1b20")
        readonly property color secondary: MaterialThemeService.color("secondary", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0.035, 0.42, tokens.isDarkTheme ? 0.80 : 0.40))
        readonly property color secondaryForeground: MaterialThemeService.color("on_secondary", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#211a00" : "#ffffff")
        readonly property color secondaryContainer: MaterialThemeService.color("secondary_container", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0.035, 0.38, tokens.isDarkTheme ? 0.30 : 0.90))
        readonly property color secondaryContainerForeground: MaterialThemeService.color("on_secondary_container", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#f7f2fa" : "#1d1b20")
        readonly property color tertiary: MaterialThemeService.color("tertiary", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0.16, 0.56, tokens.isDarkTheme ? 0.80 : 0.40))
        readonly property color tertiaryContainer: MaterialThemeService.color("tertiary_container", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0.16, 0.48, tokens.isDarkTheme ? 0.30 : 0.90))
        readonly property color tertiaryContainerForeground: MaterialThemeService.color("on_tertiary_container", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#f7f2fa" : "#1d1b20")
        readonly property color background: MaterialThemeService.color("background", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.12, tokens.isDarkTheme ? 0.06 : 0.98))
        readonly property color surface: MaterialThemeService.color("surface", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.12, tokens.isDarkTheme ? 0.06 : 0.98))
        readonly property color surfaceContainerLow: MaterialThemeService.color("surface_container_low", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.14, tokens.isDarkTheme ? 0.10 : 0.96))
        readonly property color surfaceContainer: MaterialThemeService.color("surface_container", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.16, tokens.isDarkTheme ? 0.12 : 0.94))
        readonly property color surfaceContainerHigh: MaterialThemeService.color("surface_container_high", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.18, tokens.isDarkTheme ? 0.17 : 0.90))
        readonly property color surfaceContainerHighest: MaterialThemeService.color("surface_container_highest", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.20, tokens.isDarkTheme ? 0.22 : 0.86))
        // Keep end-4's Material layer hierarchy, but retain enough wallpaper
        // pigment in the dark branch that different wallpapers do not all
        // collapse into visually identical charcoal cards. Light surfaces use
        // the unmodified Material roles; dark surfaces remain dark and keep
        // their ordered elevation while borrowing a restrained primary tint.
        readonly property color layer0: tokens._mix(background, primary,
            tokens.isDarkTheme ? 0.12 : 0.01)
        readonly property color layer1: tokens.isDarkTheme
            ? tokens._mix(surfaceContainerLow, primary, 0.10)
            : surfaceContainerLow
        readonly property color layer2: tokens.isDarkTheme
            ? tokens._mix(surfaceContainer, primary, 0.09)
            : surfaceContainer
        readonly property color layer3: tokens.isDarkTheme
            ? tokens._mix(surfaceContainerHigh, primary, 0.08)
            : surfaceContainerHigh
        readonly property color layer4: tokens.isDarkTheme
            ? tokens._mix(surfaceContainerHighest, primary, 0.07)
            : surfaceContainerHighest
        readonly property bool surfaceIsDark:
            tokens._luminance(surfaceContainer) < 0.48
        // QML reserves onXxx names for signal handlers, so foreground roles
        // use explicit, QML-safe names instead of Material's onSurface form.
        readonly property color surfaceForeground: MaterialThemeService.color("on_surface", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#f7f2fa" : "#1d1b20")
        readonly property color surfaceVariantForeground: MaterialThemeService.color("on_surface_variant", tokens.isDarkTheme,
            tokens.isDarkTheme ? "#c9c5d0" : "#49454f")
        readonly property color outline: MaterialThemeService.color("outline", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.16, tokens.isDarkTheme ? 0.60 : 0.50))
        readonly property color outlineVariant: MaterialThemeService.color("outline_variant", tokens.isDarkTheme,
            tokens._tone(tokens.seedColor, 0, 0.14, tokens.isDarkTheme ? 0.30 : 0.80))
        readonly property color error: MaterialThemeService.color("error", tokens.isDarkTheme,
            tokens.isDarkTheme ? Qt.rgba(1.0, 0.71, 0.67, 1) : Qt.rgba(0.73, 0.10, 0.12, 1))
        readonly property color scrim: Qt.rgba(0, 0, 0,
            tokens.isDarkTheme ? 0.42 : 0.24)
    }

    readonly property QtObject shape: QtObject {
        // Matches the practical scale used by end4-pC: 6/8/12/17/23/30.
        readonly property real unsharpened: tokens.isMaterial ? 6 : 5
        readonly property real extraSmall: tokens.isMaterial ? 8 : 5
        readonly property real small: tokens.isMaterial ? 12 : 10
        readonly property real medium: tokens.isMaterial ? 17 : 14
        readonly property real large: tokens.isMaterial ? 23 : 20
        readonly property real extraLarge: tokens.isMaterial ? 30 : 26
        readonly property real full: 999
    }

    readonly property QtObject state: QtObject {
        readonly property color hover: tokens._mix(tokens.colors.layer2,
            tokens.colors.surfaceForeground, 0.08)
        readonly property color pressed: tokens._mix(tokens.colors.layer2,
            tokens.colors.surfaceForeground, 0.12)
        readonly property color selected: tokens.colors.primaryContainer
        readonly property color disabled: Qt.rgba(tokens.colors.surfaceVariantForeground.r,
            tokens.colors.surfaceVariantForeground.g,
            tokens.colors.surfaceVariantForeground.b, 0.38)
    }

    readonly property QtObject typography: QtObject {
        readonly property string recommendedDisplayFamily: "SF Pro Display"
        readonly property bool hasRecommendedDisplayFamily:
            Qt.fontFamilies().indexOf(recommendedDisplayFamily) >= 0
        // An empty family delegates fallback to the user's Qt/KDE font setup.
        readonly property string displayFamily: hasRecommendedDisplayFamily
            ? recommendedDisplayFamily : ""
    }

    readonly property QtObject dock: QtObject {
        readonly property string form: tokens.isWindows12 ? "taskbar"
            : tokens.isMaterial ? "navigationDock" : "floatingDock"
        readonly property string position: "bottom"
        readonly property real radiusRatio: tokens.isWindows12 ? 0.20
            : tokens.isMaterial ? 0.50 : 0.45
        readonly property real horizontalPaddingRatio: tokens.isWindows12 ? 0.24
            : tokens.isMaterial ? 0.32 : 0.40
        readonly property real verticalPaddingRatio: tokens.isWindows12 ? 0.12
            : tokens.isMaterial ? 0.16 : 0.20
        readonly property real itemSpacingRatio: tokens.isWindows12 ? 0.07
            : tokens.isMaterial ? 0.08 : 0.09
        readonly property real dividerMarginRatio: tokens.isWindows12 ? 0.16
            : tokens.isMaterial ? 0.18 : 0.20
        readonly property int edgeMargin: tokens.isWindows12 ? 0
            : tokens.isMaterial ? 8 : 5
        // Match the float between the glass and the screen edge with an equal
        // visual breathing space between the glass and windows. DockWindow
        // applies this only while the Dock is permanently visible, so hidden
        // modes do not create an invisible spatial dead strip.
        readonly property int workspaceGap: edgeMargin
        readonly property string indicatorStyle: tokens.isWindows12 ? "underline"
            : tokens.isMaterial ? "tonal" : "dot"
        readonly property real indicatorLengthRatio: tokens.isWindows12 ? 0.42
            : tokens.isMaterial ? 0.34 : 0.13
        readonly property real indicatorThicknessRatio: tokens.isMacos ? 0.13 : 0.07
        readonly property real activeRadiusRatio: tokens.isWindows12 ? 0.18
            : tokens.isMaterial ? 0.28 : 0.30
        // Material Dock body opacity is independent from other Material
        // surfaces so its wallpaper blending can be tuned without fading
        // widgets, the launcher, or the Bar.
        readonly property real materialSurfaceOpacity: 0.30
        readonly property string activeBackgroundMode: tokens.isWindows12
            ? "subtle" : tokens.isMaterial ? "tonal" : "glass"
        readonly property bool magnificationEnabled: tokens.isMacos
        readonly property real hoverScale: tokens.isMacos ? 1.20 : 1.0
        readonly property real hoverLiftRatio: tokens.isMacos ? 0.08 : 0.0
    }

    readonly property QtObject bar: QtObject {
        // Bar keeps one visual language across shell styles. Integration is a
        // user choice, not an implicit Windows-theme side effect.
        readonly property string placement: "top"
        readonly property int height: 35
        readonly property int radius: 0
        readonly property string surfaceMode: "transparent"
        readonly property bool unifiedWithDock:
            AppearanceConfigService.barIntegratedWithDock
    }

    readonly property QtObject widget: QtObject {
        readonly property int radius: tokens.isWindows12 ? 12
            : tokens.shape.large
        // Only the Material card body is translucent; widget content remains
        // fully opaque for legibility over changing wallpapers.
        readonly property real materialSurfaceOpacity: 0.70
        readonly property int gap: tokens.isWindows12 ? 8
            : tokens.isMaterial ? 12 : 10
        readonly property int elevation: tokens.isWindows12 ? 2
            : tokens.isMaterial ? 3 : 1
        readonly property string surfaceMode: tokens.isWindows12 ? "acrylic"
            : tokens.isMaterial ? "tonal" : "glass"
        readonly property color surfaceColor: tokens.isMaterial
            ? tokens.colors.surfaceContainer : "transparent"
        readonly property color elevatedSurfaceColor: tokens.isMaterial
            ? tokens.colors.surfaceContainerHigh : "transparent"
    }

    readonly property QtObject glass: QtObject {
        readonly property real dockBlur: AppearanceConfigService.effectiveDockBlur
        readonly property real dockLiquid: AppearanceConfigService.effectiveDockLiquid
        readonly property real barBlur: AppearanceConfigService.effectiveBarBlur
        readonly property real barLiquid: AppearanceConfigService.effectiveBarLiquid
        readonly property real launcherBlur: AppearanceConfigService.effectiveLauncherBlur
        readonly property real launcherLiquid: AppearanceConfigService.effectiveLauncherLiquid
        readonly property real blurStrength: dockBlur
        readonly property real liquidStrength: dockLiquid
        readonly property real highlightMultiplier: tokens.isWindows12 ? 0.72
            : tokens.isMaterial ? 0.55 : 1.0
        readonly property real ambientMultiplier: tokens.isWindows12 ? 0.85
            : tokens.isMaterial ? 0.70 : 1.0
        readonly property real materialOpacity: 1.0
        readonly property real borderOpacity: tokens.isMaterial ? 0.30 : 0.16
    }

    readonly property QtObject motion: QtObject {
        readonly property int fastDuration: tokens.isWindows12 ? 120
            : tokens.isMaterial ? 100 : 135
        readonly property int normalDuration: tokens.isWindows12 ? 180
            : tokens.isMaterial ? 220 : 200
        readonly property int slowDuration: tokens.isWindows12 ? 260
            : tokens.isMaterial ? 300 : 360
        readonly property int standardEasing: tokens.isMaterial
            ? Easing.OutQuart : Easing.OutCubic
        readonly property bool springEnabled: tokens.isMacos
        // Anchored popups share Launchpad's entrance rhythm: a short cubic
        // settle from 0.96 scale with a directional fade/translation.
        readonly property int popupOpenDuration: 150
        readonly property int popupCloseDuration: 140
        readonly property real popupStartScale: 0.96
        readonly property real popupAnchorOffset: 20
    }
}
