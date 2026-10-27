import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.dock

// IslandWindow — the top-edge island surface.
//
// Ported from the NookX Dynamic Island (com.monsterwl.NookX 2026.10.6).
// The original is an NSPanel per screen, anchored to the top edge, whose
// content is a SwiftUI island that expands on hover or click.
//
// This is the Quickshell equivalent, following the same PanelWindow pattern
// as the launcher and the desktop-lyrics surface: an Overlay-layer window
// that spans the whole output (so centring the island is reliable) while its
// input mask is restricted to the island's own rectangle — without the mask
// the entire top strip would swallow clicks meant for the panel underneath,
// which is exactly what the original's per-region hit test prevented.
//
// The reveal value drives width, height and radius together, so the shape
// morphs continuously rather than swapping between two layouts.
PanelWindow {
    id: window

    // --- Geometry ---------------------------------------------------------
    readonly property var config: IslandConfigService
    readonly property var service: IslandService

    // The collapsed bar is the resting shape; the expanded panel is the
    // target. The reveal value interpolates between them.
    readonly property real collapsedWidth: config.width
    readonly property real collapsedHeight: config.height

    // The original's expanded island is not a scaled-up pill. It is a wide,
    // shallow slab that spans almost the whole screen -- measured on the
    // reference capture it covers about 92% of the screen width at roughly
    // 5.2:1, with the widgets packed into the left third and the rest
    // deliberately empty. Its corner radius is about a fifth of its height,
    // far larger than the collapsed pill's half-height, which is why the
    // radius is interpolated to a height-derived value instead of being h/2
    // all the way through.
    // Measured from the reference capture by scanning the panel's own pixel
    // bounds (not by eye): 1400 x 328 device pixels, bottom corner radius 74,
    // left content padding 52, gap between content blocks 55. The panel is
    // therefore 4.27:1 with a corner that is 22.6% of its height -- a much
    // taller, more rounded slab than the 5.87:1 / 17% the port had.
    readonly property real screenWidth: screen ? screen.width : 1920
    // Max with the collapsed width: config.width can be as large as 720, and
    // on a small output 0.80 * screenWidth can fall below it, which would make
    // "expanding" animate the panel narrower than the pill it started from.
    readonly property real expandedWidth:
        Math.max(collapsedWidth,
            Math.min(screenWidth * 0.92,
                Math.min(screenWidth * 0.80, 1520) * config.expandedScale))
    readonly property real expandedHeight: Math.round(expandedWidth / 4.27)
    readonly property real expandedRadius: Math.round(expandedHeight * 0.226)
    readonly property real collapsedRadius: collapsedHeight / 2

    readonly property real currentWidth:
        collapsedWidth + (expandedWidth - collapsedWidth) * service.reveal
    readonly property real currentHeight:
        collapsedHeight + (expandedHeight - collapsedHeight) * service.reveal

    // One radius curve, interpolated from the capsule's half-height to the
    // expanded panel's large corner. The shape mode then only decides corner
    // *continuity*, not corner size: squircle switches the outline onto the
    // continuous-curvature profile the shell's SquircleMask draws.
    readonly property real currentRadius:
        collapsedRadius + (expandedRadius - collapsedRadius) * service.reveal

    // Measured from the reference corner: a superellipse with exponent 2.8
    // fits the edge to 0.68px mean error, while a circular arc of the same
    // radius misses by 4.91px -- seven times worse. It is a continuous
    // (squircle) corner, not a circular one.
    //
    // The exponent is interpolated too, not switched: the collapsed pill must
    // stay a true capsule (at radius h/2 an exponent above 2 starts reading as
    // a rounded square), while the expanded panel must relax into the
    // continuous corner. So the capsule is circular, the panel is continuous,
    // and the shape mode only decides how far that goes.
    // The notch shape, imported from Islet (Claritys11/islet, MIT): the top
    // edge is a straight cut and only the bottom is rounded, with two small
    // quarter discs at the top corners that blend the cut into the screen
    // edge. The reference capture of NookX shows the same flare.
    readonly property bool isNotch: config.shapeMode === "notch"

    readonly property real targetExponent:
        config.shapeMode === "squircle" ? 2.8 : 2.0
    readonly property real currentExponent:
        2.0 + (targetExponent - 2.0) * service.reveal

    // The mask must be chosen by the mode, never by the animated exponent.
    // Toggling `layer.enabled` does not re-render an item that has already
    // painted (the shell documents this in AppIcon.qml), so switching the mask
    // on part-way through the expansion would blank the surface. At exponent
    // 2.0 the mask draws an ordinary circular corner, so it can stay on for
    // the whole animation and the exponent alone carries the change.
    readonly property bool usesShapeMask:
        IslandConfigService.shapeMode === "squircle"

    // The island's outline. The drop target's highlight rides on it.
    readonly property color outlineColor: IslandService.dropTargeted
        ? Qt.rgba(0.29, 0.87, 0.5, 0.9)
        : Qt.rgba(1, 1, 1, 0.07)

    // The material. The reference panel is opaque near-black, not a tinted
    // glass: at 0.88 alpha over a bright wallpaper the port read blue-grey
    // and the black slab was lost. 0.95 still lets a hint of the backdrop
    // through at the edges, where the rounded corner meets the desktop.
    readonly property color surfaceColor: {
        switch (IslandConfigService.backgroundMode) {
        case "solid": return Qt.rgba(0.016, 0.016, 0.019, 1.0)
        case "none": return "transparent"
        default: return Qt.rgba(0.028, 0.029, 0.033, 0.95)
        }
    }

    // --- Behaviour --------------------------------------------------------
    property bool outputAvailable: false
    visible: config.enabled && outputAvailable

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "kos-island"
    // The island floats above the panel; a top-anchored window at the panel
    // layer would be covered by fullscreen windows.
    WlrLayershell.layer: WlrLayer.Overlay
    // The island never takes keyboard focus on its own: a top-edge panel that
    // steals the keyboard from the window underneath is unusable. The app
    // picker is the one surface that needs to type (it has a search field),
    // so focus is granted on demand only while it is open. The flag is pushed
    // up from the content rather than read off it through the id, because a
    // binding here is evaluated before the children exist.
    property bool pickerOpen: false
    WlrLayershell.keyboardFocus: pickerOpen
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors { left: true; right: true; top: true; bottom: true }
    implicitWidth: screen ? screen.width : 1920
    implicitHeight: screen ? screen.height : 1080

    // Only the island's own rectangle accepts pointer events; the rest of
    // the full-output window stays click-through, exactly like the
    // original's per-region hit test.
    mask: Region { item: surface }

    // --- Shadow -----------------------------------------------------------
    // The panel floats over the desktop, so it casts. A sibling of the
    // surface rather than a child, because the surface clips and would cut
    // the shadow off exactly at the edge it is supposed to fall away from.
    // Opacity, not visible: KosCardShadow already hides itself until it has
    // a card to cast from, and overriding `visible` would defeat that guard
    // and paint a block of shading over an empty rectangle for the first
    // frame after the surface maps.
    KosCardShadow {
        cardWidth: surface.width
        cardHeight: surface.height
        cornerRadius: window.currentRadius
        cornerExponent: window.currentExponent
        offsetX: 0
        offsetY: 18
        softness: 40
        shadowColor: Qt.rgba(0, 0, 0, 0.55)
        opacity: IslandConfigService.backgroundMode === "none" ? 0 : 1
        x: surface.x + surface.width / 2 - width / 2
        y: surface.y + surface.height / 2 - height / 2
    }

    // --- The ears --------------------------------------------------------
    // Quarter discs of the surface colour at the top corners, outside the
    // panel's rectangle: the top edge reads as a curve that flows into the
    // screen instead of a hard cut. Imported from Islet's NotchIsland.
    Repeater {
        model: window.isNotch ? 2 : 0
        Shape {
            required property int index
            readonly property real r: 12
            width: r
            height: r
            x: index === 0 ? surface.x - r : surface.x + surface.width
            y: surface.y
            transform: Scale {
                origin.x: 6
                xScale: index === 0 ? 1 : -1
            }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: window.surfaceColor
                strokeColor: "transparent"
                startX: 0
                startY: 0
                PathLine { x: 12; y: 0 }
                PathLine { x: 12; y: 12 }
                PathArc { x: 0; y: 0; radiusX: 12; radiusY: 12 }
            }
        }
    }

    // --- Surface ----------------------------------------------------------
    Rectangle {
        id: surface

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        // KOS can put its bar at the top of the screen, where the island
        // would otherwise sit on top of it and swallow the clicks that
        // belong to the bar. Below a top bar the island floats on its own,
        // the way the original floats under the macOS menu bar.
        anchors.topMargin: IslandConfigService.topMargin
            + (ConfigService.position === "top" ? ConfigService.barHeight : 0)

        width: window.currentWidth
        height: window.currentHeight
        radius: window.currentRadius
        // The surface itself paints nothing: the material is either the
        // compositor's glass (below) or the opaque plate (below that). It is
        // still a Rectangle so the mask-free clip and the anchored geometry
        // stay where they were.
        color: "transparent"
        clip: true

        // --- The material -------------------------------------------------
        // The reference island is a filtered backdrop, not a painted colour:
        // its own state carries blurIntensity / saturation / brightness, and
        // its panel stays near-black even over bright water because the tint
        // is composited onto a blurred, compressed backdrop.
        //
        // This is the shell's existing glass path, the one the Dock and every
        // popup use. When the compositor owns the finish this panel paints
        // nothing at all -- KWin draws blur, refraction and the rim -- and the
        // adaptive scrim is what keeps white text readable when the wallpaper
        // behind is bright. When it does not, the same component falls back to
        // its own QML finish using baseColor, so the island can never end up
        // unpainted.
        LiquidGlassPanel {
            id: glass
            anchors.fill: parent
            visible: IslandConfigService.backgroundMode === "glass"
            radius: window.currentRadius
            cornerExponent: window.currentExponent
            // The panel sits at 0,0 inside the surface; the surface is what
            // carries the island's offset within the layer surface.
            blurAnchor: surface
            scrimEnabled: true
            // The knob drives the compositor's own contrast scrim, so the
            // panel can go from a bare blur to the near-opaque slab the
            // reference shows over a bright wallpaper, without a rebuild.
            scrimLevel: "custom"
            scrimCap: 0.25 + 0.6 * IslandConfigService.glassStrength
            scrimDecay: 0.6 + 0.5 * IslandConfigService.glassStrength
            // Text-dense surface over arbitrary wallpapers: this is the
            // preset that is allowed to ramp towards opaque near a bright
            // backdrop, which is what the original's near-black panel is.
            scrimLevel: "readable"
            material: "thick"
            materialDepth: 1.0
            // The theme tints the glass rather than repainting it: a few
            // percent of the accent over the blurred backdrop is enough to
            // tell 群青 from 银朱 without turning the panel into a colour.
            tintColor: config.accentColor
            tintOpacity: config.theme === "graphite" ? 0 : 0.06
            surfaceOpacity: 1.0
            baseColor: Qt.rgba(0.028, 0.029, 0.033, 0.95)

            // One line at startup, because the two failure modes look
            // identical on screen: a compositor that owns the finish and a
            // compositor that quietly does not. This says which one it is
            // without the user having to guess from a screenshot.
            Component.onCompleted: Qt.callLater(function() {
                if (IslandConfigService.backgroundMode !== "glass")
                    return
                const info = glass.inspectGlass()
                console.log("[Island] glass path=" + (glass.useKwinEffect ? "kwin" : "qml")
                    + " continuousBlur=" + info.continuousBlurSupported
                    + " shapeActive=" + info.shapeActive
                    + " sigma=" + info.blurSigma)
            })
        }

        // --- The opaque plate ---------------------------------------------
        // Solid and "no background" modes never blur. The plate keeps the
        // continuous outline through the same SDF mask the glass uses, so the
        // silhouette does not change when the material does.
        Rectangle {
            id: plate
            anchors.fill: parent
            // Always visible. In glass mode it is almost transparent and only
            // exists to carry the silhouette: the expanded panel's rounded
            // top corners are drawn here, so they cannot depend on whether the
            // compositor decided to honour the shape we published. Relying on
            // the glass alone is what made the top edge read as a square edge.
            radius: window.currentRadius
            color: IslandConfigService.backgroundMode === "glass"
                ? Qt.rgba(0, 0, 0, 0.04 + 0.34 * IslandConfigService.glassStrength)
                : window.surfaceColor
            border.width: window.usesShapeMask ? 0 : 1
            border.color: window.outlineColor
            layer.enabled: window.usesShapeMask
            layer.effect: SquircleMask {
                cornerRadius: window.currentRadius
                cornerExponent: window.currentExponent
                // The notch has a straight top edge: the top corners take no
                // radius at all, the bottom ones keep the full radius. The
                // shader only splits them when both are given, so every other
                // shape keeps the outline it had.
                radiusTop: window.isNotch ? 0 : -1
                radiusBottom: window.isNotch ? window.currentRadius : -1
                // The host's own size, never the window's: the effect works
                // in the layer's coordinate space, which is this plate's rect.
                maskWidth: plate.width
                maskHeight: plate.height
                borderWidth: 1
                borderColor: window.outlineColor
            }
        }

        // The original's material modes: glass gets a subtle gradient sheen.
        Rectangle {
            id: sheen
            anchors.fill: parent
            radius: parent.radius
            // A specular, not a material: at full strength it would haze the
            // blurred backdrop the glass is there to show.
            opacity: IslandConfigService.backgroundMode === "glass"
                ? 0.45 * (1 - 0.6 * IslandConfigService.glassStrength) : 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.055) }
                GradientStop { position: 0.32; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.14) }
            }
        }

        // --- The one pointer source ---------------------------------------
        // This MouseArea is the ancestor of the entire island content. It is
        // also the island's only hover-enabled item, and that is deliberate:
        // QML delivers hover to the topmost item that accepts it *and
        // nowhere else*, so every hover-enabled descendant used to switch
        // this area off, which read as "the pointer left the island" and
        // collapsed it under the pointer. Nothing inside accepts hover any
        // more (see IslandPointerTarget), so this area stays hovered for as
        // long as the pointer is anywhere on the island — collapsed or
        // expanded.
        MouseArea {
            id: pointerArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton

            onEntered: {
                // The pointer arrived without a move event: seed the position
                // before anything reads it, or the first hover highlight is
                // drawn where the pointer was last seen.
                IslandService.setHovered(true)
                IslandService.pointerMoved(pointerArea.mouseX, pointerArea.mouseY)
                content.pointerMoved(pointerArea.mouseX, pointerArea.mouseY)
            }
            onExited: IslandService.setHovered(false)

            onPositionChanged: function(mouse) {
                IslandService.pointerMoved(mouse.x, mouse.y)
                content.pointerMoved(mouse.x, mouse.y)
            }
            onPressed: function(mouse) {
                IslandService.pointerMoved(mouse.x, mouse.y)
                content.pointerPressed(mouse.x, mouse.y)
            }
            onReleased: function(mouse) { content.pointerReleased(mouse.x, mouse.y) }
            // A press that lands on the island and is then cancelled (the
            // compositor took the grab, another surface took focus) must not
            // leave a card stuck in mid-drag.
            onCanceled: content.pointerCancelled()

            // The widget column scrolls with the wheel. A Flickable would
            // have swallowed the press that starts a card drag, and a
            // WheelHandler inside the column would sit in the hover chain;
            // the surface owns the handler and routes the wheel to content.
            WheelHandler {
                onWheel: function(event) {
                    content.handleWheel(event.x, event.y, event.angleDelta.y)
                    event.accepted = true
                }
            }

            IslandContent {
                id: content
                anchors.fill: parent
                reveal: IslandService.reveal
                // Every internal metric is a fraction of this, so the port
                // keeps the reference's proportions at any screen size
                // instead of only at the size it was tuned for.
                unit: window.expandedHeight
                onWantsKeyboardChanged: window.pickerOpen = wantsKeyboard
            }
        }

        // File drop — the port of the original's GlobalFileDropDelegate.
        // Dropping runs the configured action through the platform
        // contract; the window's input mask already restricts this area to
        // the island itself, so only the island accepts the drop.
        DropArea {
            anchors.fill: parent
            enabled: IslandConfigService.dropFilesEnabled
            // A drag arriving at the collapsed pill has to open the panel:
            // the pill is 44px tall, and the whole point of the gesture is to
            // choose where the thing lands. The drag keeps it open through
            // heldByOverlay, so the panel does not collapse under the cursor.
            onEntered: {
                IslandService.setDropTargeted(true)
                IslandService.expand()
            }
            onExited: IslandService.setDropTargeted(false)
            onDropped: function(drop) {
                IslandService.setDropTargeted(false)
                IslandService.handleFileDrop(drop.urls)
            }
        }

        // The body region is registered in the surface's own coordinates, so
        // the shape test compares like with like. The kind follows the
        // configured outline: the capsule needs the refined test, because a
        // rounded rectangle's corner is not part of the island.
        function _registerBody() {
            IslandService.registerRegion("island-body", {
                x: 0,
                y: 0,
                width: surface.width,
                height: surface.height,
                kind: IslandConfigService.shapeMode === "capsule"
                    ? IslandService.regionKinds.capsule
                    : IslandService.regionKinds.rect,
                enabled: true
            })
        }

        Component.onCompleted: _registerBody()
        onWidthChanged: _registerBody()
        onHeightChanged: _registerBody()
        Component.onDestruction: IslandService.unregisterRegion("island-body")

        // A different outline means a different shape test.
        Connections {
            target: IslandConfigService
            function onShapeModeChanged() { surface._registerBody() }
        }
    }
}
