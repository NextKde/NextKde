import QtQuick
import Quickshell
import qs.desktop.modules.deskcenter

ShellRoot {
    Item {
        width: 1707; height: 1067
        FreeSlotDesktopDemo {
            id: surface
            width: parent.width; height: parent.height
            validX: 700.4; validY: 24
            validWidth: 986.6; validHeight: 947
            baseCellWidth: 123.325; baseCellHeight: 98
            iconVisualSize: 52
            entries: Array.from({length: 90}, (_, i) => ({path: "/density-fixture/" + i, name: "较长的两行文件名称" + i, kind: "folder"}))
        }
    }
    property int stage: 0
    property int oldCapacity: 0
    property int compactCapacity: 0
    function check(ok, message) { if (!ok) throw new Error(message) }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (stage === 0) {
                    oldCapacity = surface.capacity
                    check(Object.keys(surface.slots).length === oldCapacity, "initial entries fill available slots")
                    surface.density = "compact"
                    stage++
                    return
                }
                if (stage === 1 || stage === 2) {
                    check(surface.capacity > oldCapacity, "compact mode increases real QML capacity")
                    check(Object.keys(surface.slots).length === surface.capacity, "density change reveals additional entries")
                    check(surface.labelTop + 32 <= surface.cellHeight, "two-line label fits")
                    check(surface.contentWidth < surface.cellWidth && surface.contentHeight < surface.cellHeight, "hit boxes stay inside cells")
                    const p = surface.pointForSlot(0)
                    // A selection strictly inside the horizontal gutter must select nothing.
                    surface.selectionBase = []
                    surface.selectionStart = Qt.point(p.x - surface.cellGap + 1, p.y + 4)
                    surface.selectionEnd = Qt.point(p.x - 1, p.y + surface.cellHeight - 4)
                    surface.updateBoxSelection()
                    check(surface.selectedIds.length === 0, "gutter does not select either neighbour")
                    surface.selectionStart = Qt.point(p.x + surface.cellWidth/2 - 1, p.y + 10)
                    surface.selectionEnd = Qt.point(p.x + surface.cellWidth/2 + 1, p.y + 20)
                    surface.updateBoxSelection()
                    check(surface.selectedIds.length === 1, "icon selection targets one file")
                    if (stage === 1) {
                        compactCapacity = surface.capacity
                        console.log("DENSITY_COMPACT", surface.columnCount, surface.rowCount, surface.cellWidth, surface.cellHeight)
                        surface.density = "dense"
                    } else {
                        check(surface.capacity > compactCapacity, "dense mode adds capacity beyond compact mode")
                        console.log("DENSITY_DENSE", surface.columnCount, surface.rowCount, surface.cellWidth, surface.cellHeight)
                        const moved = Object.assign({}, surface.slots)
                        moved["/density-fixture/0"] = 4
                        moved["/density-fixture/4"] = 0
                        surface.slots = moved
                        surface.dragActive = true
                        surface.density = "comfortable"
                    }
                    stage++
                    return
                }
                if (stage === 3) {
                    check(surface.layoutReflowPending, "geometry changes wait for an active drag")
                    surface.finishDrag()
                    check(surface.slots["/density-fixture/0"] === 4, "ending a drag preserves valid manual positions")
                    stage++
                    return
                }
                check(surface.capacity === oldCapacity, "old spacing is restorable")
                check(Object.keys(surface.slots).length === surface.capacity, "shrinking density keeps entries in bounds")
                check(Object.values(surface.slots).every(s => s < surface.capacity), "no icons spill into widgets")
                console.log("DESKTOP_DENSITY_PASS")
                Qt.quit()
            } catch (error) { console.log("FAIL " + error); Qt.quit() }
        }
    }
}
