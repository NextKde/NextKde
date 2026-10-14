import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Offscreen fixture for the Dock icon hover hit test.
//
// It loads the shipping DockIcon (through the `desktop` symlink, exactly like
// tests/liquid-glass-panel) and drives `magnificationPointer` by hand, because a
// pointer never really enters an offscreen window.
//
// The regression it pins: `_hovering` used to be `_mouseArea.containsMouse`.
// That MouseArea is anchored to the icon, so it moves with the very hover
// lift/scale it drives. With the cursor parked on the slot's bottom edge the
// icon lifts out from under the cursor, the hover clears, the icon drops back
// and the cycle repeats -- an endless jitter. `_hovering` must therefore be a
// pure function of the pointer against the *untransformed* slot, which is what
// the sweep checks on both axes.
//
// QML re-evaluates bindings synchronously when a dependency changes, so each
// sweep is one pass: assign `ptr`, read `_hovering`, compare.
Item {
    id: root

    width: 420
    height: 240

    property point ptr: Qt.point(-10000, -10000)
    property var target: null
    property bool verticalDock: false

    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: 8

        Repeater {
            id: rep
            model: 3

            DockIcon {
                iconSize: 44
                appId: "probe" + modelData
                vertical: root.verticalDock
                magnificationRoot: root
                magnificationPointer: root.ptr
            }
        }
    }

    function slotCentre() {
        return target.parent.mapToItem(root,
            target.x + target.width / 2, target.y + target.height / 2)
    }

    // The rect the MouseArea covered: the slot scaled about its centre, then
    // translated by the hover lift. This is what the old `containsMouse` test
    // was effectively testing.
    function transformedRect() {
        const c = slotCentre()
        const s = target._hoverScale * target._magnificationScale
            * target._attentionScale
        const ty = target._hoverLift + target._magnificationLift
            + target._attentionLift
        const halfW = target.width / 2 * s
        const halfH = target.height / 2 * s
        return { l: c.x - halfW, r: c.x + halfW,
                 t: c.y - halfH + ty, b: c.y + halfH + ty }
    }

    function sweep(kind, axis) {
        verticalDock = (kind === "v")
        target = rep.itemAt(1)

        // The hover lift moves the icon along y, so the band the old hit test
        // lost is a horizontal strip at the slot's bottom edge whichever way the
        // Dock runs; the y pass is what finds it. The x pass keeps y on the slot
        // centre and sweeps sideways, so a mistake in the half-width cannot hide
        // behind a passing y sweep. `kind` selects which axis the magnification
        // influence is computed on -- it does not rotate the row, so this does
        // not reproduce a side Dock's rotated mapping, only its influence axis.
        const c = slotCentre()
        const halfSpan = (axis === "x" ? target.width : target.height) / 2
        const centre = (axis === "x" ? c.x : c.y)

        const step = 0.25
        let inside = 0, outside = 0
        // `lost`: the pointer is inside the slot but the transformed-rect test
        // says no -- exactly where the old code dropped the hover it had just
        // caused. `gained`: the zoomed rect claimed the pointer beyond the slot.
        let lost = 0, lostLo = 0, lostHi = 0, gained = 0

        for (let off = -4.0; off <= halfSpan + 4.0 + 1e-9; off += step) {
            const v = centre + off
            root.ptr = (axis === "x") ? Qt.point(v, c.y) : Qt.point(c.x, v)

            const hovered = target._hovering
            const inSlot = off >= -halfSpan - 1e-6 && off <= halfSpan + 1e-6
            if (inSlot) {
                if (hovered) {
                    inside++
                } else {
                    console.log("FAIL " + kind + "/" + axis
                        + ": inside the slot but not hovered at off=" + off.toFixed(2))
                }
            } else if (hovered) {
                console.log("FAIL " + kind + "/" + axis
                    + ": outside the slot but hovered at off=" + off.toFixed(2))
            } else {
                outside++
            }

            const r = transformedRect()
            const oldHit = (root.ptr.x >= r.l && root.ptr.x <= r.r
                && root.ptr.y >= r.t && root.ptr.y <= r.b)
            if (hovered && !oldHit) {
                lost++
                if (lost === 1)
                    lostLo = off
                lostHi = off
            } else if (!hovered && oldHit) {
                gained++
            }
        }

        console.log("REPORT " + kind + "/" + axis
            + " slotSpan=" + (halfSpan * 2).toFixed(2) + "px"
            + " insideHovered=" + inside
            + " outsideClear=" + outside
            + " oldDroppedHoverBand="
            + (lost ? (lostHi - lostLo + step).toFixed(2) : "0.00") + "px"
            + " oldOverCaptured=" + gained)
    }

    // Run after the first event-loop pass so the Row has laid the icons out.
    // Quitting from Component.onCompleted does not terminate Quickshell, which
    // is why every offscreen fixture here quits from a Timer.
    Timer {
        interval: 200
        running: true
        onTriggered: {
            try {
                sweep("h", "y")
                sweep("h", "x")
                sweep("v", "y")
                sweep("v", "x")
                console.log("DOCK_HOVER_HIT_PASS")
            } catch (e) {
                console.log("FAIL exception: " + e)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.log("FAIL timeout")
            Qt.quit()
        }
    }
}
