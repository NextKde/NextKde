import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.deskcenter

ShellRoot {
    id: test
    property int stage: 0
    property bool restore: Quickshell.env("VERIFY_SAVED") === "1"
    property var lastSaved: ({})
    Settings {
        id: saved
        location: "file://" + Quickshell.stateDir + "/icons.ini"
        category: "Icons"
        property string slotsJson: "{}"
    }
    Item {
        width: 1200; height: 800
        FreeSlotDesktopDemo {
            id: surface
            anchors.fill: parent
            validX: test.restore ? 20 : 500
            validY: 24
            validWidth: test.restore ? 1080 : 600
            validHeight: 680
            baseCellWidth: {
                const cols = Math.max(1, Math.floor((validWidth + 16) / 144))
                return (validWidth - (cols - 1) * 16) / cols
            }
            baseCellHeight: 112
            iconVisualSize: 68
            entries: [
                {path:"/fixture/a.desktop",name:"快捷方式 A",kind:"file"},
                {path:"/fixture/b.desktop",name:"快捷方式 B",kind:"file"},
                {path:"/fixture/c.desktop",name:"快捷方式 C",kind:"file"}
            ]
            blockedRects: test.restore ? [{x:20,y:24,width:350,height:330}] : []
            savedSlots: JSON.parse(saved.slotsJson)
            onLayoutCommitted: slots => { test.lastSaved = slots; saved.slotsJson = JSON.stringify(slots); saved.sync() }
        }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            try {
                if (test.restore) {
                    const point = surface.pointForSlot(surface.slots["/fixture/a.desktop"])
                    check(Math.abs(point.x - 20) < 1, "leftmost placement restored after restarting QML")
                    check(point.y > 354, "restored icon remains outside widget")
                    console.log("ICON_PLACEMENT_SAVED_PASS")
                    Qt.quit(); return
                }
                if (stage === 0) {
                    const previous = surface.slots["/fixture/a.desktop"]
                    surface.commitDrop("/fixture/a.desktop", 22, 600)
                    check(surface.slots["/fixture/a.desktop"] === previous, "reproduce old narrow-field bounce")
                    surface.validX = 20
                    surface.validWidth = 1080
                    surface.blockedRects = [{x:20,y:24,width:350,height:330}]
                    stage++; return
                }
                if (stage === 1) {
                    check(surface.slotAt(22,600) >= 0, "left edge outside widgets accepts drop")
                    check(surface.slotAt(22,100) === -1, "actual widget rectangle remains protected")
                    surface.beginDrag("/fixture/a.desktop")
                    surface.dragCenter = Qt.point(22,600)
                    surface.completeActiveDesktopDrag("/fixture/a.desktop")
                    stage++; return
                }
                if (stage === 2) {
                    const expected = surface.slotAt(22,600)
                    check(surface.slots["/fixture/a.desktop"] === expected, "release commits the leftmost slot")
                    check(surface.lastDropId === "/fixture/a.desktop", "ordinary drag commit path used")
                    check(test.lastSaved["/fixture/a.desktop"] === expected, "committed position persisted")
                    check(Math.abs(surface.pointForSlot(expected).x - 20) < 1, "shortcut renders on far left")
                    check(Object.values(surface.slots).every(s => surface.slotAvailable(s)), "reflow avoids only actual widgets")
                    const point = surface.pointForSlot(expected)
                    const inserted = surface.layoutAfterDrop(surface.slots, "/fixture/c.desktop", point.x + 40, point.y + 40, false)
                    check(Object.values(inserted).every(s => surface.slotAvailable(s)), "occupied-drop insertion skips widget slots")
                    check(new Set(Object.values(inserted)).size === 3, "insertion retains unique positions")
                    // The desktop snapshot arriving after a drop must not undo it.
                    surface.entries = surface.entries.slice()
                    stage++; return
                }
                check(surface.slots["/fixture/a.desktop"] === surface.slotAt(22,600), "snapshot refresh does not bounce icon back")
                console.log("ICON_PLACEMENT_PASS: left edge drop; actual-widget exclusion; insertion; snapshot stability; saved layout")
                Qt.quit()
            } catch (error) { console.error("ICON_PLACEMENT_FAIL " + error); Qt.quit() }
        }
    }
}
