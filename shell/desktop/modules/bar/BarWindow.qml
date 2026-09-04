import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.dock
import qs.desktop.modules.common
import qs.desktop.modules.applauncher
import qs.desktop.modules.platform

// One concrete top Bar surface. Its content is shared with the optional
// unified Dock host; this file owns layer-shell geometry and auto-hide.
PanelWindow {
    id: root

    property bool barEnabled: true

    WlrLayershell.namespace: "quickshell-bar"
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    // The Bar lives on Top, but the fullscreen launcher (a Top surface
    // covering the whole output) must render beneath the Bar. While that
    // launcher is open, the Bar promotes to Overlay; the launcher demotes
    // itself to Top in the same frame.
    WlrLayershell.layer: (AppLauncherService.open
        && AppLauncherConfigService.displayMode === "fullscreen")
        ? WlrLayer.Overlay : WlrLayer.Top
    implicitHeight: ConfigService.barHeight
    readonly property bool transparentMode:
        AppearanceConfigService.barLayoutMode === "transparent"
    // Only the floating capsule needs wallpaper between it and maximised
    // windows. Full-width and transparent Bars intentionally remain flush,
    // matching the contiguous macOS menu-bar layout.
    readonly property int workspaceBreathingGap:
        AppearanceConfigService.barLayoutMode === "floating" ? 8 : 0

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

    readonly property int reservedWorkspaceHeight: (root.barEnabled
        && hide.workspaceReserved)
        ? Math.round(implicitHeight + margins.top + workspaceBreathingGap) : 0
    exclusiveZone: root.reservedWorkspaceHeight
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

    function publishWorkspaceReservation() {
        if (root.screen)
            WorkspaceLayoutService.updateBar(root.screen,
                root.reservedWorkspaceHeight)
    }

    onScreenChanged: publishWorkspaceReservation()
    onReservedWorkspaceHeightChanged: publishWorkspaceReservation()
    Component.onCompleted: publishWorkspaceReservation()

    // The transparent layout deliberately leaves only the content: it must not
    // register a backdrop region, otherwise KWin adds blur/refraction behind
    // it. Other Bar layouts still use the regular compositor glass pipeline.
    BackgroundEffect.blurRegion: (!root.transparentMode && root.visible
        && (AppearanceConfigService.effectiveBarBlur > 0.005
            || AppearanceConfigService.effectiveBarLiquid > 0.005))
        ? barBlurRegionHolder : null

    Region {
        id: barBlurRegionHolder
        RoundedBlurRegion {
            id: barBlurRegion
            item: barWrapper
            // The floating Bar keeps a full capsule corner equal to 50% of
            // its height, so the curvature remains proportional when users
            // choose a different Bar size.
            radius: (AppearanceConfigService.barLayoutMode === "floating")
                ? barWrapper.height * 0.5 : 0
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
                        id: barDateStatus
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                    }

                    // This loader only exists in the standalone top Bar.
                    // DesktopEnvironment disables Bar entirely when it is
                    // integrated into the Dock, so the Dock never owns or
                    // fetches an application menu.
                    GlobalMenu {
                        anchors.left: barDateStatus.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        maximumWidth: Math.max(0, barStatusArea.x - x - 18)
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
