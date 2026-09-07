import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.desktop.modules.applauncher
import qs.desktop.modules.dock
import qs.desktop.modules.common
import qs.desktop.modules.platform

// One concrete output-bound Dock layer surface.
//
// Hosts the DockAutoHideController (show-mode state machine) and slides the
// dock glass around within this single, permanently-mapped surface. Hiding
// never destroys the window, toggles visible, or changes anchors — it only
// moves dockWrapper via the controller's single reveal-progress-derived offset,
// and shapes the input region with a mask so transparent areas pass clicks
// through (docs/DockArchitecture.md, "Visibility modes and auto-hide").
PanelWindow {
    id: root

    // Distinguish this surface from other quickshell panels so the glass
    // plugin can give it its own highlight direction.
    WlrLayershell.namespace: "quickshell-dock"
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    // The Dock lives on Top, but the fullscreen launcher (a Top surface
    // covering the whole output) must render beneath the Dock. While that
    // launcher is open, the Dock promotes to Overlay; the launcher demotes
    // itself to Top in the same frame.
    WlrLayershell.layer: (AppLauncherService.open
        && AppLauncherConfigService.displayMode === "fullscreen")
        ? WlrLayer.Overlay : WlrLayer.Top

    // ── Position-aware anchoring ──
    // The surface clings directly to the configured screen edge (margins = 0);
    // the 5px float moves inside as an inset on dockWrapper, and the reveal
    // handle tucks 6px inside the true edge, so the Home Indicator can sit
    // right at the physical edge while the glass keeps breathing room (§9.2).
    //
    // A bottom dock spans the full screen width; a side dock now spans the full
    // screen height (anchored top+bottom) so it can host the full-height reveal
    // handle, with the glass column vertically centred inside.
    //
    // position is a per-edge literal baked into the matching Component in
    // Dock.qml; switching edges recreates this window instead of patching a
    // live one, so the anchors below are final from the first commit.
    //
    // A bottom dock spans the full screen width (left+right) and hangs from the
    // bottom edge; a side dock spans the full screen height (top+bottom) on its
    // edge. Anchoring only top (without bottom) would let a side surface
    // collapse to the implicit thickness and become 0-height.
    property string position: "bottom"
    property Component leadingAccessory: null
    property Component trailingAccessory: null
    property bool clockInInfoCarousel: false
    readonly property bool vertical: root.position === "left"
        || root.position === "right"
    readonly property int edgeMargin: AppearanceTokens.dock.edgeMargin
    readonly property int workspaceGap: AppearanceTokens.dock.workspaceGap
    // Wayland does not expose a trustworthy QWindow global position to QML.
    // Derive this layer surface's compositor-global origin from the output it
    // is explicitly bound to and from the anchors declared below.
    readonly property real surfaceGlobalX: (root.screen ? root.screen.x : 0)
        + (root.position === "right"
            ? (root.screen ? root.screen.width : root.width) - root.width
            : 0)
    readonly property real surfaceGlobalY: (root.screen ? root.screen.y : 0)
        + (root.position === "bottom"
            ? (root.screen ? root.screen.height : root.height) - root.height
            : 0)

    anchors: ({
        top: root.vertical,
        bottom: true,
        left: root.position === "bottom" || root.position === "left",
        right: root.position === "bottom" || root.position === "right"
    })
    margins { left: 0; top: 0; right: 0; bottom: 0 }

    // Cross-edge thickness = glass + float. Length is forced by the anchors
    // (full screen along the anchored edge); these set the other dimension.
    implicitHeight: root.vertical ? 0 : dockContainer.height + root.edgeMargin
    implicitWidth: root.vertical ? dockContainer.width + root.edgeMargin : 0

    // ── Auto-hide controller ──
    // One controller per surface; inputs come from the singleton services and
    // the container's interaction state. It owns revealProgress, timers and
    // the reveal animation.
    DockAutoHideController {
        id: hide
        mode: ConfigService.visibilityMode
        configReady: ConfigService.ready
        windowDataReady: WindowService.providerReady
        position: root.position
        targetScreen: root.screen
        dockWidth: dockContainer.width
        dockHeight: dockContainer.height
        edgeMargin: root.edgeMargin
        pointerInsideDock: dockContainer.pointerInside
        editing: dockContainer.editMode
        dragging: dockContainer.draggedPinnedLoader !== null
        popupOpen: DockModelService.activeDockPopup !== null
        launcherOpen: AppLauncherService.open
    }

    // Dock never changes the compositor work area. New ordinary windows avoid
    // its full-reveal rectangle through the KWin one-shot placement rule;
    // maximized windows may reach the screen edge and naturally trigger smart
    // hide when they overlap the Dock.
    exclusiveZone: 0

    // The custom KWin glass effect consumes this region for both backdrop
    // blur and liquid refraction. Keep publishing it when either channel is
    // active; gating only on blur makes a liquid-only Dock fully transparent.
    BackgroundEffect.blurRegion: (root.visible
        && (AppearanceConfigService.effectiveDockBlur > 0.005
            || AppearanceConfigService.effectiveDockLiquid > 0.005))
        ? dockBlurRegionHolder : null

    Region {
        id: dockBlurRegionHolder
        RoundedBlurRegion {
            id: glassRegion
            item: dockWrapper
            radius: dockContainer.pillRadius
        }
        // The reveal bar's backdrop blur. visualBar is a direct child of the
        // handle at the window origin, so its x/y are already surface coords.
        // Radius matches the pill's own capsule so the frosted halo sits
        // exactly under the visible bar (§6.4).
        RoundedBlurRegion {
            id: barRegion
            item: revealHandle.visualBar
            radius: Math.min(revealHandle.visualThickness,
                revealHandle.barLength) / 2
        }
    }

    // Stable, full-reveal position of the glass inside the surface. Always
    // derived from surface/container size — never the animated transform.
    readonly property real restX: root.vertical
        ? (root.position === "right"
            ? root.width - root.edgeMargin - dockContainer.width
            : root.edgeMargin)
        : (root.width - dockContainer.width) / 2
    readonly property real restY: root.vertical
        ? (root.height - dockContainer.height) / 2
        : root.height - root.edgeMargin - dockContainer.height

    function publishWorkspaceLayout() {
        if (!root.screen || dockContainer.width <= 0 || dockContainer.height <= 0)
            return
        WorkspaceLayoutService.updateDock(root.screen, root.position, {
            x: root.surfaceGlobalX + root.restX,
            y: root.surfaceGlobalY + root.restY,
            width: dockContainer.width,
            height: dockContainer.height
        }, root.workspaceGap)
    }

    Timer {
        id: layoutPublishTimer
        interval: 0
        repeat: false
        onTriggered: root.publishWorkspaceLayout()
    }

    onScreenChanged: layoutPublishTimer.restart()
    onPositionChanged: layoutPublishTimer.restart()
    onRestXChanged: layoutPublishTimer.restart()
    onRestYChanged: layoutPublishTimer.restart()
    onSurfaceGlobalXChanged: layoutPublishTimer.restart()
    onSurfaceGlobalYChanged: layoutPublishTimer.restart()

    Connections {
        target: dockContainer
        function onWidthChanged() { layoutPublishTimer.restart() }
        function onHeightChanged() { layoutPublishTimer.restart() }
    }

    Component.onCompleted: layoutPublishTimer.restart()

    Item {
        id: dockWrapper
        // Slide along toward the edge as revealProgress reaches 0. The mask
        // region (dockHitRegion) shares these exact coordinates so input tracks
        // the moving glass.
        x: hide.offsetX + root.restX
        y: hide.offsetY + root.restY
        width: dockContainer.width
        height: dockContainer.height
        opacity: hide.dockOpacity
        scale: hide.dockScale
        transformOrigin: root.vertical
            ? (root.position === "right" ? Item.Right : Item.Left)
            : Item.Bottom

        DockContainer {
            id: dockContainer
            targetScreen: root.screen
            surfaceOriginX: root.surfaceGlobalX
            surfaceOriginY: root.surfaceGlobalY
            leadingAccessory: root.leadingAccessory
            trailingAccessory: root.trailingAccessory
            clockInInfoCarousel: root.clockInInfoCarousel
        }
    }

    // Input mask mirror for the dock glass. Invisible; its geometry equals
    // dockWrapper's (including the hide offset). Keeping it a sibling (rather
    // than using dockWrapper directly) lets the mask region move independently
    // of the visual wrapper (opacity/scale) while still matching its area.
    Item {
        id: dockHitRegion
        x: hide.offsetX + root.restX
        y: hide.offsetY + root.restY
        width: dockContainer.width
        height: dockContainer.height
        visible: false
    }

    // White Home Indicator + pointer hit target, parked at the true screen edge.
    DockRevealHandle {
        id: revealHandle
        position: root.position
        windowWidth: root.width
        windowHeight: root.height
        fadeOpacity: hide.handleOpacity
        dockWidth: dockContainer.width
        dockHeight: dockContainer.height
        // Wallpaper ambient, same liquid material as the dock's popups.
        ambientPrimary: WallpaperPaletteService.primary
        ambientSecondary: WallpaperPaletteService.secondary
        ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
        active: hide.handleActive
        onEntered: hide.handleEntered()
        onExited: hide.handleExited()
        onClicked: hide.handleClicked()
    }

    // §5.8: a window becoming urgent (non-fullscreen) temporarily reveals the
    // dock for 2200ms; the temp-clear handler then re-evaluates per show mode.
    Connections {
        target: DockModelService
        function onUrgentWindowAppeared() {
            hide.requestReveal("urgent", DockAnimation.smartHideUrgentRevealMs)
        }
    }

    // Shape the input region to the moving dock glass + the reveal handle hit
    // target (union). Everything else in this transparent surface passes clicks
    // through. In "always" mode the handle target collapses to zero.
    mask: Region {
        Region { item: dockHitRegion }
        Region { item: revealHandle.hitTarget }
    }
}
