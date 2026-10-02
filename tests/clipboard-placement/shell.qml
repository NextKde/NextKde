import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import qs.desktop.modules.quicksearch

ShellRoot {
    id: test
    property int stage: 0
    property var card: null
    property int waits: 0
    property int pasteCount: -1
    PanelWindow {
        visible: true
        anchors { top: true; left: true; right: true }
        implicitHeight: 40
        exclusiveZone: 40
        color: "transparent"
    }
    QuickSearch { id: controller }
    QuickSearchWindow {
        id: window
        mode: "clipboard"
        open: true
        clipboardAnchor: test.anchor(100, 100)
    }
    function anchor(x, y) {
        return {available: true, source: "caret", x: x, y: y, width: 0, height: 20}
    }
    function configure(value, delay) {
        PlatformClient.request("test.configure-anchor", {anchor: value, delay: delay || 0}, function() {})
    }
    function focusTarget(active) {
        const record = {windowId: "fixture", handleId: "{11111111-1111-1111-1111-111111111111}",
            title: "Fixture", identity: {name: "Fixture"}, iconSource: "", isVisible: true,
            geometry: {x: 0, y: 0, width: 400, height: 300}, toplevel: {}}
        WindowService.records = [record]
        WindowService._recordsById = ({fixture: record})
        WindowService.activeWindowId = active
    }
    function readPasteCount() {
        PlatformClient.request("test.paste-count", {}, function(reply) {
            test.pasteCount = reply.result.count
        })
    }
    function check(value, label) {
        if (!value) throw new Error("stage " + stage + ": " + label
            + " open=" + controller.open + " pending=" + controller._opening
            + " anchor=" + JSON.stringify(controller.clipboardAnchor))
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const match = find(child, name)
            if (match) return match
        }
        return null
    }
    Timer {
        id: steps
        interval: 400
        repeat: true
        running: true
        onTriggered: {
            try {
                if (!ScreenLifecycle.outputAvailable || !PlatformClient.connected) {
                    if (++test.waits > 30) throw new Error("test services not ready")
                    return
                }
                switch (test.stage++) {
                case 0:
                    WindowService._countPoll.stop()
                    WindowService._updateTimer.stop()
                    test.card = find(window.contentItem, "quicksearch-dialog")
                    check(!!test.card, "shipping dialog instantiated")
                    check(window.width === 800 && window.height === 600,
                        "clipboard surface stays output-local around reserved bars")
                    check(card.x === 100 && card.y === 128, "caret placement in real QML")
                    window.clipboardAnchor = anchor(790, 590)
                    break
                case 1:
                    check(card.x >= 12 && card.x + card.width <= window.width - 12, "right-edge clamp")
                    check(card.y + card.height <= 590 - 8, "bottom flips above caret")
                    window.mode = "window"
                    configure(anchor(160, 180), 60)
                    focusTarget("fixture")
                    controller.show("clipboard")
                    check(!controller.open && controller._opening, "waits before focus transfer")
                    break
                case 2:
                    check(card.x === (window.width - card.width) / 2 && card.y === Math.round(window.height * 0.16), "window search remains centered")
                    check(controller.open && controller.clipboardAnchor.x === 160, "reply opens clipboard")
                    configure(anchor(200, 200))
                    WindowService.activeWindowId = ""
                    controller.show("clipboard")
                    check(controller.clipboardAnchor.x === 160, "show does not chase its own search field")
                    check(controller._focusReturnId === "fixture", "repeated show preserves paste target")
                    controller.hide()
                    controller.toggle("clipboard")
                    break
                case 3:
                    check(controller.open && controller.clipboardAnchor.x === 200, "next opening refreshes position")
                    controller.hide()
                    configure(anchor(210, 210), 80)
                    controller.toggle("clipboard")
                    controller.toggle("clipboard")
                    check(!controller.open && !controller._opening, "second toggle cancels pending opening")
                    break
                case 4:
                    check(!controller.open, "late reply does not reopen after hide")
                    configure(anchor(220, 220), 80)
                    controller.show("clipboard")
                    controller.show("app")
                    break
                case 5:
                    check(controller.open && controller.mode === "app" && controller.clipboardAnchor === null, "mode change cancels old request")
                    controller.hide()
                    configure(anchor(230, 230), 1800)
                    controller.show("clipboard")
                    break
                case 6:
                    check(controller.open && controller.clipboardAnchor === null, "bounded fallback opens without bridge")
                    controller.hide()
                    break
                case 7:
                    check(!controller.open, "timeout cannot reopen after hide")
                    interval = 2000
                    break
                case 8:
                    check(!controller.open, "late timed-out reply ignored")
                    interval = 400
                    configure({available: false})
                    controller.show("clipboard")
                    break
                case 9:
                    check(controller.open && controller.clipboardAnchor === null, "older plugin preserves centered fallback")
                    ScreenLifecycle.outputAvailable = false
                    check(!controller.open && !controller._opening, "output loss cancels opening")
                    ScreenLifecycle.outputAvailable = true
                    focusTarget("other-window")
                    controller._focusReturnId = "fixture"
                    controller.beginPaste({selectionRecord: "1\tfixture"}, false)
                    break
                case 10:
                    readPasteCount()
                    break
                case 11:
                    check(pasteCount === 0, "changed focus never receives automatic paste")
                    focusTarget("fixture")
                    controller.beginPaste({selectionRecord: "1\tfixture"}, false)
                    break
                case 12:
                    readPasteCount()
                    break
                case 13:
                    check(pasteCount === 1, "original target still receives guarded paste")
                    console.log("CLIPBOARD_PLACEMENT_PASS")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("CLIPBOARD_PLACEMENT_FAIL", error)
                Qt.quit()
            }
        }
    }
}
