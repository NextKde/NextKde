pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform

// IslandService — public control and state contract for the top-edge island.
//
// Ported from the NookX Dynamic Island. The original is an AppDelegate with
// island methods (handleDynamicIslandToggle:, selectIslandExpandMode:,
// selectIslandShapeMode:, selectIslandBackgroundMode:) plus a NSPanel window
// per screen. This service is the equivalent surface: it holds the
// expanded/collapsed state, drives the reveal animation, owns the hit-region
// geometry that the original computed with SwiftUI Path + CGPath.contains,
// and executes the drop action the original ran in GlobalFileDropDelegate.
//
// Nothing here imports a visual module, so the Settings process and other
// surfaces can drive the island without a circular dependency.
QtObject {
    id: service

    // --- State ------------------------------------------------------------
    // `expanded` is the target state; `reveal` is the animated 0..1 value the
    // visuals bind to. The original drove the same split through a
    // membership observer and an expiration timer.
    property bool expanded: false
    property real reveal: 0

    // --- Pointer ----------------------------------------------------------
    // The island has exactly ONE pointer source: the surface-level MouseArea
    // in IslandWindow, which is the ancestor of every item the island draws.
    //
    // That is not a stylistic choice. QML hover is exclusive -- it is
    // delivered to the topmost item that accepts it, and only that item. An
    // ancestor MouseArea therefore loses hover the moment the pointer moves
    // onto any descendant with hoverEnabled or a HoverHandler, which is what
    // every card, button and list row used to have. The island read that
    // exit as "the pointer left" and collapsed, the content disappeared, the
    // pointer fell back inside the (now childless) bar, the island expanded
    // again -- a collapse/expand loop the user saw as the island bouncing
    // back and the icons jittering.
    //
    // Nothing inside the island accepts hover any more. This area keeps
    // hover for as long as the pointer is anywhere on the island, collapsed
    // or expanded.
    property bool hovered: false
    // Pointer position in the island surface's own coordinates, refreshed on
    // every move while the pointer is inside. Content derives its hover
    // highlights and drag offsets from this instead of from per-item hover
    // events, so there is one source of truth and no coordinate feedback.
    property real pointerX: 0
    property real pointerY: 0

    // A pointer that leaves is given a moment to come back before the island
    // closes: crossing the edge of a shape that is itself still animating
    // must not cost the user the panel.
    property int hoverCollapseDelay: 280

    // Set while a surface inside the island (the app picker, the widget
    // editor, a drag in progress) owns the interaction. Nothing inside may
    // take hover away any more, but an open picker still must not be closed
    // by a pointer that wanders onto another monitor mid-task.
    property bool heldByOverlay: false

    // An external drag is not hover: the compositor does not send pointer
    // motion to us while a drag is in flight, so `hovered` stays false and the
    // grace timer would collapse the panel out from under the cursor. The drop
    // target holds it open instead.
    readonly property bool heldOpen: heldByOverlay || dropTargeted

    // True while a file drag hovers the island (the original's
    // _isGlobalFileDropTargeted); the window uses it to highlight the
    // surface as a drop target.
    property bool dropTargeted: false

    // The screen the island is currently presented on. Null means "follow the
    // pointer output", which is what a top-edge island does on multi-monitor
    // setups.
    property var triggerScreen: null

    // --- Hit regions ------------------------------------------------------
    // The original keeps an array of IslandHitRegionView, each with a
    // `kind` (0 = vector path, 1 = rect, 2 = ellipse), a `pose`, a
    // `visualScale` and an `isRegionEnabled` flag, and it walks that array to
    // decide whether a click belongs to the island.
    //
    // Here the same three shapes are supported, and the test is performed
    // against the island's own geometry rather than an arbitrary path: the
    // collapsed bar is a capsule, the expanded panel is a rounded rectangle.
    readonly property var regionKinds: ({ capsule: 0, rect: 1, ellipse: 2 })

    // Regions currently registered, in the original's spirit. Kept as a plain
    // list so a surface (the quick-launch strip, a widget) can add its own
    // hit area without the island knowing about it.
    property var regions: []

    // --- Animation --------------------------------------------------------
    // The original animates the island with a SwiftUI spring
    // (interpolatingSpring(stiffness:damping:) — the binary carries the
    // stiffness/damping metadata plus AnimationSpeed / bounceIntensity
    // settings). The port integrates a damped spring here: the expand runs
    // slightly under-damped for the original's bounce, the collapse is
    // critically damped so it never overshoots shut.
    //
    // `animating` is public: a surface that wants to avoid reacting while
    // the island is still moving can read it.
    property bool animating: false
    property real _animTarget: 0
    property real _springOmega: 30     // angular frequency (rad/s)
    property real _springZeta: 1.0     // damping ratio
    property real _springValue: 0
    property real _springVelocity: 0

    function _config() { return IslandConfigService }

    // The effective reveal duration follows the configured mode: a click
    // island animates on demand, a hover island has a short reveal, an
    // always-on island is already open.
    function effectiveExpandDuration() {
        const c = _config()
        if (c.expandMode === "always")
            return 0
        return c.expandDurationMs
    }

    function effectiveCollapseDuration() {
        const c = _config()
        if (c.expandMode === "always")
            return 0
        return c.collapseDurationMs
    }

    // --- Transitions ------------------------------------------------------
    function expand(screen) {
        if (screen && !screen.isPlaceholder)
            triggerScreen = screen
        _collapseTimer.stop()
        if (expanded)
            return
        expanded = true
        _animateTo(1, effectiveExpandDuration())
    }

    function collapse() {
        // "always" keeps the island expanded; a pointer leaving the bar must
        // not collapse what the user explicitly asked to stay open. Without
        // this guard the mode was selectable in Settings but did nothing,
        // because nothing else ever re-expanded the island.
        if (_config().expandMode === "always")
            return
        _collapseTimer.stop()
        if (!expanded) {
            reveal = 0
            return
        }
        expanded = false
        _animateTo(0, effectiveCollapseDuration())
    }

    function toggle(screen) {
        if (expanded)
            collapse()
        else
            expand(screen)
    }

    // A stepped timer rather than a JS animation loop: the island must keep
    // animating while the shell is busy, and a QML NumberAnimation would be
    // interrupted by unrelated bindings. The step integrates a damped
    // spring toward the target with a fixed 8 ms step; the settle check
    // ends the animation once the value and velocity are both negligible.
    function _animateTo(target, duration) {
        animating = true
        _animTarget = target
        const seconds = Math.max(0.05, duration / 1000)
        // Settle in roughly `duration`: t_settle ≈ 4 / (zeta * omega).
        _springZeta = (target > 0.5) ? 0.72 : 1.0
        _springOmega = 4 / (_springZeta * seconds)
        _springValue = reveal
        _springVelocity = 0
        _stepTimer.interval = 8
        _stepTimer.restart()
    }

    // QtObject has no default property, so the timer is wrapped in a
    // property — the same pattern the platform singletons use.
    property Timer _stepTimer: Timer {
        repeat: true
        onTriggered: {
            const dt = 0.008
            const x = service._springValue - service._animTarget
            const accel = -2 * service._springZeta * service._springOmega * service._springVelocity
                          - service._springOmega * service._springOmega * x
            service._springVelocity += accel * dt
            service._springValue += service._springVelocity * dt
            service.reveal = service._springValue
            if (Math.abs(service._springValue - service._animTarget) < 0.002
                    && Math.abs(service._springVelocity) < 0.02) {
                service.reveal = service._animTarget
                service.animating = false
                // The timer is a property of this service; there is no `timer`
                // id to resolve. Stopping it by the wrong name threw a
                // ReferenceError on every tick and left a 125 Hz timer
                // running for the rest of the session.
                service._stepTimer.stop()
            }
        }
    }

    // --- Hover ------------------------------------------------------------
    function pointerMoved(x, y) {
        pointerX = x
        pointerY = y
    }

    function setHovered(on) {
        on = !!on
        const c = _config()
        if (on) {
            _collapseTimer.stop()
            if (hovered)
                return
            hovered = true
            if (c.expandMode === "hover")
                expand(triggerScreen)
            return
        }
        if (!hovered) {
            _collapseTimer.stop()
            return
        }
        hovered = false
        if (c.expandMode !== "hover" || !expanded || heldOpen) {
            _collapseTimer.stop()
            return
        }
        // Restart rather than schedule: every exit starts the full grace
        // period, so a pointer that grazes the edge and comes back never
        // accumulates toward a collapse.
        _collapseTimer.restart()
    }

    // The collapse grace timer. Wrapped in a property because QtObject has no
    // default property -- a bare child Timer fails to load.
    property Timer _collapseTimer: Timer {
        repeat: false
        interval: service.hoverCollapseDelay
        onTriggered: {
            if (service.hovered || service.heldOpen)
                return
            service.collapse()
        }
    }

    onHeldByOverlayChanged: {
        if (heldOpen)
            _collapseTimer.stop()
        else if (!hovered && expanded && _config().expandMode === "hover")
            _collapseTimer.restart()
    }

    // --- Hit testing ------------------------------------------------------
    // Mirrors the original's region walk. The original converts the click
    // point into each region's coordinate space, checks the region's enabled
    // flag and hidden state, then performs a shape test.
    //
    // Here the regions are plain rectangles in island-local coordinates, so
    // the equivalent test is a rectangle containment; the capsule and
    // ellipse kinds additionally require the point to be inside the rounded
    // shape, not merely the bounding box.
    function hitTest(x, y) {
        for (let i = 0; i < regions.length; i++) {
            const r = regions[i]
            if (!r || r.enabled === false)
                continue
            if (!_rectContains(r, x, y))
                continue
            const kind = r.kind === undefined ? 1 : r.kind
            if (kind === 0 && !_capsuleContains(r, x, y))
                continue
            if (kind === 2 && !_ellipseContains(r, x, y))
                continue
            return r
        }
        return null
    }

    function _rectContains(r, x, y) {
        return x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height
    }

    // A capsule is a rectangle whose straight section runs between two
    // circles of radius height/2. Points inside the bounding box but in a
    // corner cap fall outside the shape.
    function _capsuleContains(r, x, y) {
        const radius = r.height / 2
        const cy = r.y + radius
        const leftCx = r.x + radius
        const rightCx = r.x + r.width - radius
        const dx = x < leftCx ? (x - leftCx) : (x > rightCx ? (x - rightCx) : 0)
        const dy = y - cy
        return dx * dx + dy * dy <= radius * radius
    }

    function _ellipseContains(r, x, y) {
        const rx = r.width / 2
        const ry = r.height / 2
        if (rx <= 0 || ry <= 0)
            return false
        const dx = (x - (r.x + rx)) / rx
        const dy = (y - (r.y + ry)) / ry
        return dx * dx + dy * dy <= 1
    }

    // --- Region registration ----------------------------------------------
    function registerRegion(id, region) {
        const next = regions.filter(function(r) { return r.id !== id })
        next.push(Object.assign({ id: id }, region))
        regions = next
    }

    function unregisterRegion(id) {
        regions = regions.filter(function(r) { return r.id !== id })
    }

    // --- File drop ---------------------------------------------------------
    // The original's GlobalFileDropDelegate parks dropped files on the
    // island ("拖入文件，稍后取用"). The Linux port runs the configured
    // action through the versioned platform contract instead: open hands
    // the file to xdg-open, copyPath puts the file on the KDE clipboard,
    // reveal opens the containing folder. No shell, no direct file IO.
    function setDropTargeted(on) {
        dropTargeted = !!on
    }

    function handleFileDrop(urls) {
        if (!urls || urls.length === 0)
            return
        const action = _config().dropAction
        for (let i = 0; i < urls.length; i++) {
            let path = String(urls[i]).replace(/^file:\/\//, "")
            try {
                path = decodeURIComponent(path)
            } catch (error) {
                // A malformed escape is used as-is; the daemon validates.
            }
            if (!path)
                continue
            // A desktop entry dropped on the island is an application the
            // user wants on the deck, not a file to open: pin it. This is the
            // Linux equivalent of the original's "drop anything on the
            // island" affordance, and it is the only route by which an
            // application can arrive from outside the island -- QML drag and
            // drop does not cross a window boundary, so the island cannot
            // receive an in-flight drag from a file manager as a drag.
            if (/\.desktop$/i.test(path)) {
                const id = path.replace(/^.*\//, "")
                if (id)
                    _config().pinApp(id)
                continue
            }
            // Everything that is not an application is kept as a shortcut:
            // the island holds the path, never the file. This is the drop
            // semantic the island is for -- drag something to the top edge and
            // it is one click away from then on.
            if (action === "shortcut") {
                _config().pinPath(path)
                continue
            }
            if (action === "copyPath") {
                PlatformClient.request("clipboard.set", { mode: "copy", paths: [path] },
                    function(response) {
                        if (!response || !response.ok)
                            console.warn("[IslandService] clipboard.set failed for " + path)
                    })
            } else if (action === "reveal") {
                const parent = path.replace(/\/[^\/]*$/, "")
                if (!parent)
                    continue
                PlatformClient.request("file.open", { path: parent }, _dropAck)
            } else {
                PlatformClient.request("file.open", { path: path }, _dropAck)
            }
        }
    }

    function _dropAck(response) {
        if (!response || !response.ok)
            console.warn("[IslandService] file drop action failed")
    }

    Component.onCompleted: console.log("[IslandService] instantiated")
}
