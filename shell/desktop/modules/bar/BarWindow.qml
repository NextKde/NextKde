import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.dock
import qs.desktop.modules.common
import qs.desktop.modules.applauncher

// One concrete top Bar surface. Its content is shared with the optional
// unified Dock host; this file owns layer-shell geometry and auto-hide.
PanelWindow {
    id: root

    property bool barEnabled: true

    WlrLayershell.namespace: "quickshell-bar"
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.layer: WlrLayer.Top
    implicitHeight: ConfigService.barHeight

    // ── Auto-hide controller ──
    BarAutoHideController {
        id: hide
        mode: AppearanceConfigService.barVisibilityMode
        configReady: AppearanceConfigService.ready
        windowDataReady: WindowService.providerReady
        targetScreen: root.screen
        barHeight: root.implicitHeight
        edgeMargin: 15
        pointerInsideBar: contentHoverHandler.hovered
        popupOpen: barContentLoader.item?.statusArea?.anyPanelOpen ?? false
        launcherOpen: AppLauncherService.open
    }

    // Only "always" mode reserves a permanent top workspace strip.
    // In "smart" or "persistent" modes, exclusiveZone stays at 0 so
    // maximised windows extend to the top of the screen.
    exclusiveZone: (AppearanceConfigService.barVisibilityMode === "always" && root.barEnabled)
        ? implicitHeight : 0
    visible: root.barEnabled

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: (AppearanceConfigService.barLayoutMode === "floating")
            ? (AppearanceConfigService.barVisibilityMode !== "always" ? 8 : 6)
            : 0
        left: (AppearanceConfigService.barLayoutMode === "floating") ? 15 : 0
        right: (AppearanceConfigService.barLayoutMode === "floating") ? 15 : 0
    }

    // KWin's glass effect uses this region for both blur and liquid
    // refraction, so a liquid-only Bar must keep publishing it.
    BackgroundEffect.blurRegion: (root.visible
        && (AppearanceConfigService.effectiveBarBlur > 0.005
            || AppearanceConfigService.effectiveBarLiquid > 0.005))
        ? barBlurRegionHolder : null

    Region {
        id: barBlurRegionHolder
        RoundedBlurRegion {
            id: barBlurRegion
            item: barWrapper
            radius: (AppearanceConfigService.barLayoutMode === "floating") ? 12 : 0
        }
    }

    // ── Visual Bar content ──
    Item {
        id: barWrapper
        x: 0
        y: hide.offsetY
        width: root.width
        height: root.height
        opacity: hide.barOpacity
        visible: root.barEnabled && hide.revealProgress > 0.001

        LiquidGlassSurface {
            id: barGlassBackground
            anchors.fill: parent
            radius: (AppearanceConfigService.barLayoutMode === "floating") ? 12 : 0
            visible: true
            baseColor: ThemeService.backgroundColor
            surfaceOpacity: 1.0
            blurStrength: AppearanceConfigService.effectiveBarBlur
            liquidStrength: AppearanceConfigService.effectiveBarLiquid
            ambientPrimary: WallpaperPaletteService.primary
            ambientSecondary: WallpaperPaletteService.secondary
            ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
            border.width: 1
            border.color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.10)
        }

        HoverHandler {
            id: contentHoverHandler
        }

        Loader {
            id: barContentLoader
            anchors.fill: parent
            anchors.leftMargin: (AppearanceConfigService.barLayoutMode === "floating") ? 10 : 16
            anchors.rightMargin: (AppearanceConfigService.barLayoutMode === "floating") ? 10 : 16
            active: root.barEnabled
            sourceComponent: Component {
                Item {
                    id: barContentItem
                    readonly property alias statusArea: barStatusArea

                    BarDateStatus {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                    }

                    BarStatusArea {
                        id: barStatusArea
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }

    // ── Touch-top invisible trigger ──
    // A 8px hit area at the screen top to reveal Bar when hovered in hide modes.
    Item {
        id: topTriggerArea
        x: 0
        y: 0
        width: root.width
        height: hide.handleActive ? 8 : 0
        visible: hide.handleActive

        HoverHandler {
            id: topHoverHandler
            enabled: hide.handleActive
            onHoveredChanged: {
                if (hovered) {
                    hide.handleEntered()
                } else {
                    hide.handleExited()
                }
            }
        }

        TapHandler {
            enabled: hide.handleActive
            onTapped: hide.handleClicked()
        }
    }

    // Input mask mirror for visual content and top trigger.
    Item {
        id: barHitRegion
        x: 0
        y: hide.offsetY
        width: root.width
        height: root.height
        visible: false
    }

    Item {
        id: topHitRegion
        x: 0
        y: 0
        width: root.width
        height: hide.handleActive ? 8 : 0
        visible: false
    }

    // Shape the input region so transparent background passes clicks through.
    mask: Region {
        Region { item: barHitRegion }
        Region { item: topHitRegion }
    }
}
