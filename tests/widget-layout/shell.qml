import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter

ShellRoot {
    id: test
    DeskCenterWindow { id: desktop; TestEvent { id: events } }
    property int stage: 0
    property var card: null
    property real oldHeight: 0
    property real oldWidth: 0
    property real pointerX: 0
    property real pointerY: 0
    property int oldVisibleIndex: 0
    property var finalDimensions: null
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function click(name) {
        const item = find(desktop.contentItem, name)
        check(item && item.visible, "visible control " + name)
        check(events.mousePress(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0), "press " + name)
        check(events.mouseRelease(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0), "release " + name)
    }
    Timer {
        interval: 450; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready) return
                switch(test.stage++) {
                case 0:
                    ScreenLifecycle.activeScreen = desktop.screen
                    if (Quickshell.env("VERIFY_SAVED") === "1") {
                        check(DeskCenterConfigService.clockStyle === "digital", "saved clock style")
                        check(DeskCenterConfigService.sideFor("notifications") === "right", "saved right side")
                        check(DeskCenterConfigService.dimensionsFor("notifications").height > desktop.spanSize(2) + 240, "saved free height")
                        check(DeskCenterConfigService.dimensionsFor("notifications").width > desktop.spanSize(2) + 70, "saved free width")
                        check(DeskCenterConfigService.topOffsetFor("notifications") === 250, "saved lower position")
                        console.log("WIDGET_LAYOUT_SAVED_PASS")
                        Qt.quit()
                        return
                    }
                    for (const id of AppearanceConfigService.deskCenterWidgetIds)
                        AppearanceConfigService.setDeskCenterWidgetVisible(id, ["clock", "weather", "notifications"].includes(id))
                    DeskCenterConfigService.setClockStyle("digital")
                    DeskCenterConfigService.setSize("notifications", "medium")
                    DeskCenterConfigService.setSide("notifications", "left")
                    break
                case 1:
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(test.card && test.card.visible, "notification card shown")
                    check(/^\d{2}:\d{2}:\d{2}$/.test(find(desktop.contentItem, "desktop-clock-time").text), "digital clock time")
                    check(/^\d{4}-\d{2}-\d{2} 星期/.test(find(desktop.contentItem, "desktop-clock-date").text), "digital clock date")
                    check(events.mousePress(test.card, 65, 65, Qt.RightButton, Qt.NoModifier, 0), "right click")
                    events.mouseRelease(test.card, 65, 65, Qt.RightButton, Qt.NoModifier, 0)
                    break
                case 2:
                    check(desktop.editMode, "right click enters editing")
                    click("widget-size-notifications-large")
                    break
                case 3:
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(Math.abs(test.card.width - desktop.spanSize(3)) < 1, "large renders three columns")
                    check(Math.abs(test.card.height - desktop.spanSize(2)) < 1, "large renders two rows")
                    click("widget-size-notifications-small")
                    click("widget-clock-style")
                    break
                case 4:
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(Math.abs(test.card.height - desktop.spanSize(1)) < 1, "small renders one row")
                    check(find(desktop.contentItem, "desktop-clock-analog") !== null, "analog clock selectable")
                    click("widget-clock-style")
                    click("widget-size-notifications-medium")
                    break
                case 5:
                    check(find(desktop.contentItem, "desktop-clock-time") !== null, "digital clock restored")
                    click("widget-side-notifications")
                    break
                case 6: {
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    const grid = find(desktop.contentItem, "desktop-file-grid")
                    check(DeskCenterConfigService.sideFor("notifications") === "right", "side button moves right")
                    check(test.card.x > desktop.width / 2, "right card position")
                    check(Math.abs(test.card.x + test.card.width - (desktop.width - desktop.rightInset)) < 1, "aligned to right inset")
                    check(grid.x + grid.width <= test.card.x - desktop.gap + 1, "icons do not overlap right widgets")
                    click("widget-side-notifications")
                    break
                }
                case 7:
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(DeskCenterConfigService.sideFor("notifications") === "left", "move back left")
                    events.mousePress(test.card, test.card.width / 2, test.card.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mouseMove(test.card, test.card.width / 2 + 20, test.card.height / 2, 0, Qt.LeftButton, Qt.NoModifier)
                    break
                case 8:
                    events.mouseMove(desktop.contentItem, desktop.width - 120, desktop.topInset + 120, 0, Qt.LeftButton, Qt.NoModifier)
                    events.mouseRelease(desktop.contentItem, desktop.width - 150, desktop.topInset + 120, Qt.LeftButton, Qt.NoModifier, 0)
                    break
                case 9:
                    check(DeskCenterConfigService.sideFor("notifications") === "right", "drag crosses to right side")
                    click("widget-size-notifications-large")
                    desktop.leaveWidgetEditMode()
                    console.log("WIDGET_LAYOUT_PASS: right-click edit; small/medium/large actual geometry; left/right move; icon clearance; drag across sides")
                    break
                case 10:
                    DeskCenterConfigService.setSize("notifications", "medium")
                    DeskCenterConfigService.setTopOffset("notifications", 250)
                    for (let i = 0; i < 24; i++)
                        ControlCenterService.notificationHistory.append({notifId: 1000+i, appName: "QQ", desktopEntry: "qq", appIcon: "", image: "", summary: "历史消息 " + (i+1), body: "自由调整高度测试", timestamp: Date.now(), actionLabel: "查看", hasAction: true})
                    break
                case 11: {
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(Math.abs(test.card.y - (desktop.topInset + 250)) < 1, "notification center starts below banners")
                    const list = find(test.card, "desk-notification-list")
                    oldVisibleIndex = Math.floor(list.height / list.itemAtIndex(0).height)
                    oldHeight = test.card.height
                    oldWidth = test.card.width
                    const handle = find(test.card, "widget-resize-height-notifications")
                    const pos = handle.mapToItem(desktop.contentItem, handle.width/2, handle.height/2)
                    pointerX = pos.x
                    pointerY = pos.y + 200
                    events.mousePress(handle, handle.width/2, handle.height/2, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mouseMove(desktop.contentItem, pointerX, pointerY, 0, Qt.LeftButton, Qt.NoModifier)
                    break
                }
                case 12:
                    check(Math.abs(test.card.height - oldHeight - 200) < 1, "bottom edge gives continuous 200 pixel height increase")
                    check(Math.abs(test.card.width - oldWidth) < 1, "bottom edge keeps width")
                    check(!desktop.editMode, "bottom edge works without edit mode")
                    events.mouseRelease(desktop.contentItem, pointerX, pointerY, Qt.LeftButton, Qt.NoModifier, 0)
                    break
                case 13: {
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(Math.abs(DeskCenterConfigService.dimensionsFor("notifications").height - oldHeight - 200) <= 1, "free height saved")
                    const list = find(test.card, "desk-notification-list")
                    check(Math.floor(list.height / list.itemAtIndex(0).height) > oldVisibleIndex, "taller viewport shows more history rows")
                    desktop.enterWidgetEditMode(false)
                    const handle = find(test.card, "widget-resize-corner-notifications")
                    const pos = handle.mapToItem(desktop.contentItem, handle.width/2, handle.height/2)
                    oldHeight = test.card.height
                    oldWidth = test.card.width
                    pointerX = pos.x - 80
                    pointerY = pos.y + 50
                    events.mousePress(handle, handle.width/2, handle.height/2, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mouseMove(desktop.contentItem, pointerX, pointerY, 0, Qt.LeftButton, Qt.NoModifier)
                    break
                }
                case 14:
                    check(Math.abs(test.card.width - oldWidth - 80) < 1, "right anchored corner grows 80 pixels leftward")
                    check(Math.abs(test.card.height - oldHeight - 50) < 1, "corner grows 50 pixels downward")
                    events.mouseRelease(desktop.contentItem, pointerX, pointerY, Qt.LeftButton, Qt.NoModifier, 0)
                    break
                case 15:
                    finalDimensions = DeskCenterConfigService.dimensionsFor("notifications")
                    click("widget-size-notifications-small")
                    break
                case 16:
                    test.card = find(desktop.contentItem, "desktop-widget-notifications")
                    check(Math.abs(test.card.height - desktop.spanSize(1)) < 1, "preset resets resized height")
                    check(Math.abs(test.card.width - desktop.spanSize(2)) < 1, "preset resets resized width")
                    DeskCenterConfigService.setDimensions("notifications", finalDimensions.width, finalDimensions.height)
                    break
                case 17:
                    desktop.leaveWidgetEditMode()
                    console.log("WIDGET_FREE_RESIZE_PASS: continuous bottom/corner drag; immediate larger history viewport; lower position; saved width/height")
                    Qt.quit()
                    break
                }
            } catch(error) { console.error("WIDGET_LAYOUT_FAIL: " + error); Qt.quit() }
        }
    }
    Timer { interval: 14000; running: true; onTriggered: { console.error("WIDGET_LAYOUT_FAIL: timeout"); Qt.quit() } }
}
