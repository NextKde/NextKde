import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.bar
import qs.desktop.modules.deskcenter
import qs.desktop.modules.quicksearch
import qs.desktop.modules.overview
import qs.desktop.modules.platform

ShellRoot {
    id: test
    property int stage: 0
    property var field: null
    property var sequence: []
    QtObject { id: screenGeometry; property real x: 0; property real y: 0; property real width: 1000; property real height: 800 }
    DockAutoHideController { id: boot; mode: "always"; configReady: false }
    BarAutoHideController { id: barBoot; mode: "always"; configReady: false }
    DockAutoHideController { id: dock; mode: "persistent"; configReady: true; windowDataReady: true }
    DockAutoHideController { id: sized; mode: "smart"; configReady: true; windowDataReady: true; targetScreen: screenGeometry; dockWidth: 100; dockHeight: 60 }
    KosFloatPanel { id: panel; centerOnScreen: true; animateOnShow: true; Item { width: 200; height: 90 } }
    OverviewWindow { id: overview }
    QuickSearchWindow { id: search; mode: "clipboard"; TestEvent { id: events } }
    QuickSearch { id: pasteController }
    FreeSlotDesktopDemo {
        id: files; width: 1000; height: 800
        entries: [{path:"/fixture/a", name:"a"}, {path:"/fixture/b", name:"b"}]
        savedSlots: DesktopFilesService.slotsForOutput("fixture-output")
        onLayoutCommitted: function(slots) { DesktopFilesService.saveSlots("fixture-output", slots) }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function records(active, exists) {
        const record = {windowId:"fixture-a", handleId:"{11111111-1111-1111-1111-111111111111}",
            title:"Fixture", identity:{name:"Fixture", desktopId:"fixture"}, iconSource:"",
            geometry:{x:320,y:700,width:80,height:80}, isVisible:true, onAllDesktops:true,
            toplevel:{minimized:false,fullscreen:false}}
        WindowService.records = exists === false ? [] : [record]
        WindowService._recordsById = exists === false ? ({}) : ({"fixture-a":record})
        WindowService.activeWindowId = active
    }
    function paste(active, record) {
        records(active)
        pasteController._focusReturnId = "fixture-a"
        pasteController.beginPaste({selectionRecord:record || "fixture-copy"}, false)
    }
    function checkpoint(name) { PlatformClient.request("test.checkpoint", {name:name}, function() {}) }
    Component.onCompleted: {
        // Observe startup before the deliberately bounded 450ms fallback.
        check(boot.phase === "Bootstrapping" && boot.revealProgress === 0, "Dock waits for config")
        check(barBoot.phase === "Bootstrapping" && barBoot.revealProgress === 0, "Bar waits for config")
        boot._bootTimeout.stop(); barBoot._bootTimeout.stop()
    }
    Timer {
        id: steps; interval: 220; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready) return
                if (Quickshell.env("LAYOUT_RESTART") === "1") {
                    check(DesktopFilesService.slotsForOutput("fixture-output")["/fixture/renamed"] === 7,
                        "free layout survives a new Shell process")
                    console.log("INTERACTION_RUNTIME_PASS")
                    Qt.quit()
                    return
                }
                switch (test.stage++) {
                case 0:
                    WindowService._countPoll.stop(); WindowService._updateTimer.stop()
                    boot.mode = "persistent"; boot.configReady = true
                    check(boot.phase === "Hidden" && boot.revealProgress === 0, "saved hidden mode does not flash")
                    dock._hidePendingTimer.stop(); dock._evaluateTimer.stop()
                    dock.revealProgress = 1; dock._enterHiding()
                    check(dock.phase === "Hiding", "hide animation owns its phase")
                    interval = 55
                    break
                case 1:
                    check(dock.revealProgress > 0 && dock.revealProgress < 1, "hide is in flight")
                    dock.pointerInsideDock = true; dock._doEvaluate()
                    check(dock.phase === "Showing", "returning pointer reverses animation")
                    interval = 240
                    break
                case 2:
                    check(dock.revealProgress === 1 && dock.phase === "Held", "reverse ends held, never hidden")
                    records(""); sized._recomputeConflict()
                    check(!sized.hasWindowConflict, "small dock misses window")
                    sized.dockWidth = 500
                    break
                case 3:
                    check(sized.hasWindowConflict, "dock width change recomputes collision")
                    screenGeometry.width = 1600
                    break
                case 4:
                    check(!sized.hasWindowConflict, "screen geometry change recomputes collision")
                    panel.show()
                    break
                case 5:
                    panel.hide(); interval = 40
                    break
                case 6:
                    panel.show(); interval = 240
                    break
                case 7:
                    check(panel.visible && panel.requestedOpen, "reopen survives old close animation")
                    panel.hide(); panel.toggle()
                    check(panel.requestedOpen, "toggle during close means reopen")
                    overview.open = true; search.open = true
                    break
                case 8:
                    test.field = find(search.contentItem, "quicksearch-input")
                    check(!!test.field, "real search field loaded")
                    test.field.text = "abc"; test.field.cursorPosition = 1; test.field.forceActiveFocus()
                    events.keyClick(Qt.Key_Delete, Qt.NoModifier, 0)
                    check(test.field.text === "ac", "Delete edits search text")
                    test.field.text = "hello world"; test.field.cursorPosition = 0
                    events.keyClick(Qt.Key_Delete, Qt.ControlModifier, 0)
                    check(test.field.text !== "hello world", "Ctrl+Delete retains word editing")
                    overview.open = false; search.open = false
                    check(overview.visible && search.visible, "close retains mapped surfaces")
                    check(!overview.contentItem.enabled && !search.contentItem.enabled, "closing surfaces release input")
                    interval = 25
                    break
                case 9:
                    check(search.visible && overview.visible, "exit animation remains visible")
                    search.open = true; overview.open = true; interval = 260
                    break
                case 10:
                    check(search.revealProgress === 1 && overview.revealProgress === 1, "window close reverses from current progress")
                    search.open = false; overview.open = false; panel.hide()
                    break
                case 11: {
                    check(!search.visible && !overview.visible, "surfaces unmap after exit")
                    const point = files.pointForSlot(7)
                    files.commitDrop("/fixture/a", point.x + files.cellWidth / 2, point.y + files.cellHeight / 2)
                    check(files.slots["/fixture/a"] === 7, "drop commits free slot")
                    files.entries = files.entries.concat([{path:"/fixture/c", name:"c"}])
                    check(files.slots["/fixture/a"] === 7, "snapshot keeps manual placement")
                    files.dragActive = true
                    files.entries = files.entries.concat([{path:"/fixture/d", name:"d"}])
                    files.finishDrag()
                    check(files.slots["/fixture/a"] === 7 && files.slots["/fixture/d"] !== undefined, "snapshot during drag reconciles on finish")
                    DesktopFilesService.migrateLayoutPath("/fixture/a", "/fixture/renamed")
                    files.entries = files.entries.map(entry => entry.path === "/fixture/a" ? {path:"/fixture/renamed", name:"renamed"} : entry)
                    check(files.slots["/fixture/renamed"] === 7, "rename moves persistent key")
                    ClipboardService.pasteEnabled = true
                    paste("fixture-b")
                    break
                }
                case 12:
                    checkpoint("different-window")
                    paste(""); interval = 1400
                    break
                case 13:
                    check(!pasteController._pastePending, "paste timeout cancels")
                    checkpoint("timeout")
                    paste(""); records("", false); interval = 200
                    break
                case 14:
                    checkpoint("closed-target")
                    pasteController._focusReturnId = ""
                    pasteController.beginPaste({selectionRecord:"fixture-copy"}, false)
                    break
                case 15:
                    checkpoint("missing-target")
                    paste("fixture-a")
                    break
                case 16:
                    checkpoint("matched-target")
                    // The first copy's delayed failure must not cancel a newer
                    // request. The fixture returns it after the second copy.
                    paste("", "delayed-copy")
                    paste("", "new-copy"); interval = 400
                    break
                case 17:
                    check(pasteController._pastePending, "stale callback cannot cancel newer paste")
                    pasteController.cancelPaste()
                    checkpoint("stale-copy")
                    PlatformClient.request("test.finish", {}, function() {})
                    console.log("INTERACTION_RUNTIME_PASS")
                    Qt.quit()
                }
            } catch (error) { console.error("INTERACTION_RUNTIME_FAIL: " + error); Qt.quit() }
        }
    }
    Timer { interval: 20000; running: true; onTriggered: { console.error("INTERACTION_RUNTIME_FAIL: timeout"); Qt.quit() } }
}
