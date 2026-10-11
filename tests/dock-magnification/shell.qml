import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Exercise the shipping delegate, including the side Dock's rotated parent.
// Real frame updates drive the animation; the timer only samples its output.
ShellRoot {
FloatingWindow {
    visible: true
    implicitWidth: 640
    implicitHeight: 640
Item {
    id: root
    width: 640
    height: 640
    property point ptr: Qt.point(-10000, -10000)
    property string edge: "bottom"
    property bool interactive: true
    property var target: null
    property int edgeIndex: 0
    property int phase: 0
    property int ticks: 0
    property int failures: 0
    property real previousScale: 1
    property real maxPhaseError: 0
    property real startedAt: 0
    property real t90: -1

    Row {
        id: row
        anchors.centerIn: parent
        rotation: root.edge === "bottom" ? 0 : 90
        spacing: 8
        Repeater {
            id: rep
            model: 3
            DockIcon {
                iconSize: 44
                appId: "magnification-probe-" + modelData
                interactive: root.interactive
                isActivated: modelData === 0
                isRunning: modelData === 0
                vertical: root.edge !== "bottom"
                dockEdge: root.edge
                magnificationRoot: root
                magnificationPointer: root.ptr
            }
        }
    }

    function check(ok, message) {
        if (!ok) {
            failures++
            console.log("FAIL " + edge + ": " + message)
        }
    }
    function centre(item) {
        return item.parent.mapToItem(root,
            item.x + item.width / 2, item.y + item.height / 2)
    }
    function pointAt(item, along, across) {
        const c = centre(item)
        return edge === "bottom" ? Qt.point(c.x + along, c.y + across)
                                 : Qt.point(c.x + across, c.y + along)
    }
    function totalLift(item) {
        return item._hoverLift + item._magnificationLift
    }
    function childNamed(item, name) {
        for (let i = 0; i < item.children.length; ++i) {
            if (item.children[i].objectName === name)
                return item.children[i]
        }
        throw new Error("Missing child: " + name)
    }
    function checkSelectionStates() {
        const item = rep.itemAt(0)
        const glass = childNamed(item, "dock-selection-highlight")
        const legacy = childNamed(item, "dock-legacy-active-background")
        const legacyHover = childNamed(item, "dock-legacy-hover-highlight")
        interactive = true
        ptr = pointAt(item, 0, 0)
        check(glass.enabled && glass.hovered && glass.selected,
            "macOS selection/hover must reach the glass plate")
        check(!legacy.visible && !legacyHover.visible, "legacy plates must not stack with glass")
        check(glass.rotation === (edge === "bottom" ? 0 : -90), "side lighting must stay upright")
        item.editMode = true
        check(!glass.enabled, "edit mode must suppress selection lighting")
        item.editMode = false
        item.isDragging = true
        check(!glass.enabled, "dragging must suppress selection lighting")
        item.isDragging = false
        item.isActivated = false
        item.isUrgent = true
        check(!glass.enabled && legacy.visible, "urgency must keep its orange background")
        item.isUrgent = false
        item.isActivated = true
        item.useSharedActiveBackground = true
        check(!glass.selected, "shared selection must not get a duplicate local plate")
        item.useSharedActiveBackground = false
        for (const style of ["material", "windows12"]) {
            AppearanceConfigService.shellStyle = style
            check(glass.enabled && glass.selected && glass.hovered,
                style + " must use the shared glass selection and hover")
            check(!legacy.visible && !legacyHover.visible,
                style + " must not stack legacy plates with glass")
        }
        AppearanceConfigService.shellStyle = "macos"
        console.log("REPORT " + edge + " selection/hover, urgency, edit and style compatibility passed")
    }
    function checkBoundary() {
        interactive = true
        let maxJump = 0
        for (let i = 0; i < rep.count; ++i) {
            const item = rep.itemAt(i)
            // No binary hover lift may be added at either slot boundary.
            for (const sign of [-1, 1]) {
                const boundary = sign * item.width / 2
                ptr = pointAt(item, boundary - 0.001, 0)
                const before = totalLift(item)
                ptr = pointAt(item, boundary + 0.001, 0)
                maxJump = Math.max(maxJump, Math.abs(totalLift(item) - before))
            }
            ptr = pointAt(item, 0, 0)
            check(item._hovering, "static slot centre must be hovered")
            check(Math.abs(item._magnificationInfluence - 1) < 1e-9,
                "centre must reach full influence")
            const original = item._slotCentreInRoot()
            item._attentionScale = 1.18
            item._attentionLift = -6
            const transformed = item._slotCentreInRoot()
            check(Math.abs(original.x - transformed.x) < 1e-9
                && Math.abs(original.y - transformed.y) < 1e-9,
                "attention animation must not move the hit-test slot")
            item._attentionScale = 1
            item._attentionLift = 0
        }
        console.log("REPORT " + edge + " boundaryJump=" + maxJump.toFixed(6) + "px")
        check(maxJump < 0.01, "binary hover lift interrupts the fisheye curve")
        interactive = false // Do not open real tooltip/preview surfaces in this probe.
        ptr = Qt.point(-10000, -10000)
    }
    function beginPhase(next) {
        phase = next
        ticks = 0
        startedAt = Date.now()
    }
    function samplePhase() {
        const scaleProgress = (target.scale - 1)
            / (AppearanceTokens.dock.magnificationMaxScale - 1)
        const liftProgress = -target.transform[0].y
            / (target.iconSize * AppearanceTokens.dock.magnificationLiftRatio)
        maxPhaseError = Math.max(maxPhaseError, Math.abs(scaleProgress - liftProgress))
        check(target.width === target.iconSlotSize && target.height === target.iconSlotSize,
            "animation changed layout geometry")
        return scaleProgress
    }

    Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: {
            root.ticks++
            if (root.phase === 0 && root.ticks === 15) {
                root.target = rep.itemAt(1)
                root.checkSelectionStates()
                root.checkBoundary()
                root.beginPhase(1)
            } else if (root.phase === 1 && root.ticks === 35) {
                root.maxPhaseError = 0
                root.t90 = -1
                root.previousScale = 1
                root.ptr = root.pointAt(root.target, 0, 0)
                root.beginPhase(2)
            } else if (root.phase === 2) {
                const progress = root.samplePhase()
                if (progress >= 0.9 && root.t90 < 0)
                    root.t90 = Date.now() - root.startedAt
                root.check(root.target.scale >= root.previousScale - 0.00001, "entry overshot/reversed")
                root.previousScale = root.target.scale
                if (root.ticks === 35) {
                    console.log("REPORT " + root.edge + " t90=" + root.t90
                        + "ms maxScaleLiftPhaseError=" + root.maxPhaseError.toFixed(6))
                    root.check(root.t90 >= 0 && root.t90 < 220, "entry is too slow")
                    root.check(root.maxPhaseError < 0.00001, "scale and lift run out of phase")
                    root.check(Math.abs(progress - 1) < 0.001, "entry did not settle")
                    root.ptr = root.pointAt(root.target, 100, 0)
                    root.beginPhase(3)
                }
            } else if (root.phase === 3) {
                // Continuous motion, then an abrupt reversal. No queued easing
                // or spring velocity should keep moving away from the root.target.
                root.ptr = root.pointAt(root.target, root.ticks < 20 ? 100 - root.ticks * 4 : (root.ticks - 20) * 4, 0)
                root.samplePhase()
                if (root.ticks === 40) {
                    root.check(root.maxPhaseError < 0.00001, "tracking lost scale/lift synchrony")
                    root.ptr = Qt.point(-10000, -10000)
                    root.beginPhase(4)
                }
            } else if (root.phase === 4) {
                root.samplePhase()
                if (root.ticks === 35) {
                    root.check(Math.abs(root.target.scale - 1) < 0.00001, "exit did not settle")
                    root.check(Math.abs(root.target.transform[0].y) < 0.00001, "exit left a lift")
                    root.check(root.target._magnificationAnimating === false, "idle still schedules frames")
                    root.edgeIndex++
                    if (root.edgeIndex === 3) {
                        if (!root.failures) console.log("DOCK_MAGNIFICATION_PASS")
                        Qt.quit()
                    } else {
                        root.edge = ["bottom", "left", "right"][root.edgeIndex]
                        root.beginPhase(0)
                    }
                }
            }
        }
    }
    Timer {
        interval: 12000
        running: true
        onTriggered: { console.log("FAIL timeout"); Qt.quit() }
    }
}

}
}
