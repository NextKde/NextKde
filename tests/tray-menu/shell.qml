import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.bar

ShellRoot {
    id: test
    PanelWindow {
        id: bar
        anchors { top: true; left: true }
        implicitWidth: 600
        implicitHeight: 50
        color: "#303030"
        Item { id: toggleHost; x: 300; width: 30; height: 30 }
        SysTray { id: tray; x: 20; y: 10; collectionToggleHost: toggleHost }
        TestEvent { id: events }
    }
    property int stage: 0
    property int ticks: 0
    property int started: 0
    property var menu: null
    property var collection: null
    function check(ok, text) { if (!ok) throw new Error(text) }
    function icon(name) {
        return collection.grid.children.find(item => item.trayKey === "tray:qa-" + name)
    }
    function open(name) {
        const item = icon(name)
        check(item !== undefined, "missing tray delegate " + name)
        events.mouseClick(item, item.width / 2, item.height / 2, Qt.RightButton, Qt.NoModifier, 5)
    }
    function label() { return menu.page.items[0]?.entry?.text ?? "" }
    function loading() {
        check(menu.page.items.length === 1 && !menu.page.items[0].entry
            && menu.page.items[0].enabled === false, "pending menu must show an inert placeholder")
        check(menu.displayedPage.items.every(item => !item.entry), "old DBus entries survived the page reset")
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            try {
                if (++test.ticks > 180) throw new Error("tray menu fixture timed out at " + test.stage)
                if (test.stage === 0) {
                    if (tray.allKeys.length < 4 || !SysTrayOrderService.ready) return
                    for (const key of tray.allKeys) SysTrayOrderService.setCollected(key, true)
                    test.menu = tray.data.find(item => item.objectName === "status-tray-context-menu")
                    test.collection = tray.data.find(item => item.objectName === "status-collection-popup")
                    tray.collectionExpanded = true
                    test.stage = 1
                } else if (test.stage === 1) {
                    if (!test.collection.visible) return
                    test.open("fast"); test.stage = 2
                } else if (test.stage === 2) {
                    if (!test.menu.visible || test.label() !== "fast") return
                    test.check(tray.collectionExpanded, "first menu collapsed its collection")
                    test.open("slow"); test.loading()
                    test.check(test.menu.anchorItem === test.icon("slow"), "menu did not re-anchor")
                    test.started = test.ticks; test.stage = 3
                } else if (test.stage === 3) {
                    if (test.ticks - test.started < 5) {
                        test.loading(); test.check(test.menu.visible, "pending switch hid the popup"); return
                    }
                    if (test.label() !== "slow") return
                    test.check(tray.collectionExpanded, "switch collapsed collection")
                    test.menu.action("", test.menu.page.items[0])
                    test.open("late"); test.loading()
                    test.stage = 4
                } else if (test.stage === 4) {
                    // Real press on the background of the collection surface.
                    events.mouseClick(test.collection.contentItem, 2, 2, Qt.LeftButton, Qt.NoModifier, 5)
                    test.started = test.ticks; test.stage = 5
                } else if (test.stage === 5) {
                    if (test.ticks - test.started < 22) return
                    test.check(!test.menu.visible, "a dismissed late response reopened the menu")
                    test.check(tray.collectionExpanded, "background dismissal closed the collection")
                    test.open("empty"); test.stage = 6
                } else if (test.stage === 6) {
                    if (!test.menu.visible) return
                    test.loading()
                    test.check(test.menu.page.items[0].label !== "Loading…", "loaded empty menu remains loading")
                    test.open("fast"); test.stage = 7
                } else if (test.stage === 7) {
                    if (test.label() !== "fast") return
                    test.check(tray.collectionExpanded, "reopening failed")
                    console.log("TRAY_MENU_PASS")
                    Qt.quit()
                }
            } catch (error) {
                console.error("TRAY_MENU_FAIL", error)
                Qt.exit(1)
            }
        }
    }
}
