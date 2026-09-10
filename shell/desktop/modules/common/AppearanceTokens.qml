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
    readonly property bool isDarkTheme: systemPalette.window.r * 0.2126
        + systemPalette.window.g * 0.7152
        + systemPalette.window.b * 0.0722 < 0.5

    function _mix(base, tint, amount, alpha) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount,
            base.g + (tint.g - base.g) * amount,
            base.b + (tint.b - base.b) * amount,
            alpha === undefined ? 1.0 : alpha)
    }

    readonly property QtObject colors: QtObject {
        readonly property color primary: tokens.seedColor
        readonly property color onPrimary: tokens.isDarkTheme
            ? Qt.rgba(0.05, 0.05, 0.07, 1) : Qt.rgba(1, 1, 1, 1)
        readonly property color secondary: tokens._mix(tokens.seedColor,
            Qt.rgba(1, 1, 1, 1), 0.32)
        readonly property color surface: tokens.isDarkTheme
            ? tokens._mix(Qt.rgba(0.055, 0.055, 0.07, 1), tokens.seedColor, 0.16)
            : tokens._mix(Qt.rgba(0.97, 0.97, 0.98, 1), tokens.seedColor, 0.08)
        readonly property color surfaceContainer: tokens.isDarkTheme
            ? tokens._mix(Qt.rgba(0.085, 0.085, 0.10, 1), tokens.seedColor, 0.20)
            : tokens._mix(Qt.rgba(0.93, 0.94, 0.96, 1), tokens.seedColor, 0.12)
        readonly property color surfaceContainerHigh: tokens.isDarkTheme
            ? tokens._mix(Qt.rgba(0.12, 0.12, 0.14, 1), tokens.seedColor, 0.22)
            : tokens._mix(Qt.rgba(0.88, 0.89, 0.93, 1), tokens.seedColor, 0.14)
        readonly property color onSurface: tokens.isDarkTheme
            ? Qt.rgba(0.94, 0.95, 1, 1) : Qt.rgba(0.10, 0.10, 0.12, 1)
        readonly property color onSurfaceVariant: tokens.isDarkTheme
            ? Qt.rgba(0.76, 0.78, 0.84, 1) : Qt.rgba(0.30, 0.31, 0.36, 1)
        readonly property color outline: tokens.isDarkTheme
            ? Qt.rgba(0.78, 0.80, 0.88, 0.34) : Qt.rgba(0.25, 0.26, 0.30, 0.30)
        readonly property color error: Qt.rgba(0.88, 0.26, 0.28, 1)
        readonly property color scrim: Qt.rgba(0, 0, 0,
            tokens.isDarkTheme ? 0.42 : 0.24)
    }

    readonly property QtObject shape: QtObject {
        readonly property real extraSmall: tokens.isMaterial ? 4 : 5
        readonly property real small: tokens.isMaterial ? 8 : 10
        readonly property real medium: tokens.isMaterial ? 12 : 14
        readonly property real large: tokens.isMaterial ? 16 : 20
        readonly property real extraLarge: tokens.isMaterial ? 28 : 26
        readonly property real full: 999
    }

    readonly property QtObject state: QtObject {
        readonly property color hover: tokens.colors.primary
        readonly property color pressed: tokens.colors.primary
        readonly property color selected: tokens.colors.primary
        readonly property color disabled: tokens.colors.onSurfaceVariant
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
            : tokens.isMaterial ? 0.34 : 0.45
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
        readonly property real materialOpacity: tokens.isMaterial ? 0.94 : 1.0
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
