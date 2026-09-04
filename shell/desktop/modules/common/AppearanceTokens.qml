pragma Singleton
import QtQuick

// Semantic shell-shape values. Consumers should depend on these roles instead
// of branching on shellStyle themselves. Values describe geometry and motion;
// color continues to come from the active system palette and glass material.
QtObject {
    id: tokens

    readonly property int version: 6
    readonly property string style: AppearanceConfigService.shellStyle
    readonly property bool isWindows12: style === "windows12"
    readonly property bool isMacos: style === "macos"
    readonly property bool isMaterial: style === "material"

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
        // Reserve the same breathing room on both sides of the Dock: between
        // the glass and the screen edge, and between the glass and maximised
        // windows. Keep this as a separate semantic role so it can diverge in
        // a future design without changing DockWindow's layout contract.
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
            : tokens.isMaterial ? 20 : 26
        readonly property int gap: tokens.isWindows12 ? 8
            : tokens.isMaterial ? 12 : 10
        readonly property int elevation: tokens.isWindows12 ? 2
            : tokens.isMaterial ? 3 : 1
        readonly property string surfaceMode: tokens.isWindows12 ? "acrylic"
            : tokens.isMaterial ? "tonal" : "glass"
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
        readonly property int popupOpenDuration: 200
        readonly property int popupCloseDuration: 140
        readonly property real popupStartScale: 0.94
        readonly property real popupAnchorOffset: 8
    }
}
