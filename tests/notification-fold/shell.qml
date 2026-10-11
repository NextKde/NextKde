import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter

ShellRoot {
    id: test
    property int stage: 0
    property int openedId: -1
    property int previousPreviewCount: 0
    property real previewHeight: 1000
    FloatingWindow {
        id: window
        visible: true; width: 390; height: 1000; color: "white"
        DeskWidgetCard {
            width: parent.width
            height: test.previewHeight
            startColor: "#434b58"; endColor: "#2a313d"
            DeskNotificationWidget { id: widget }
        }
        TestEvent { id: events }
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
    function count(key) {
        let count = 0
        for (let i = 0; i < widget.filteredHistory.count; i++) {
            const row = widget.filteredHistory.get(i)
            if (row.rowKind === "message" && row.groupKey === key) count++
        }
        return count
    }
    function rowIndex(key, kind) {
        for (let i = 0; i < widget.filteredHistory.count; i++) {
            const row = widget.filteredHistory.get(i)
            if (row.groupKey === key && row.rowKind === kind) return i
        }
        return -1
    }
    function add(app, entry, id, newest) {
        const row = {notifId:id, appName:app, desktopEntry:entry, appIcon:"", image:"",
            summary:"消息 " + id, body:"来自 " + app, timestamp:Date.now(), actionLabel:"查看", hasAction:true}
        if (newest) ControlCenterService.notificationHistory.insert(0, row)
        else ControlCenterService.notificationHistory.append(row)
        ControlCenterService.registerLiveNotification({id:id, tracked:true,
            actions:[{identifier:"default", invoke:() => test.openedId = id}]})
    }
    function click(name) {
        const item = find(widget, name)
        check(item !== null, "missing rendered control " + name)
        check(events.mousePress(item, item.width/2, item.height/2, Qt.LeftButton, Qt.NoModifier, 0)
            && events.mouseRelease(item, item.width/2, item.height/2, Qt.LeftButton, Qt.NoModifier, 0), "mouse click " + name)
    }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready) return
                const list = find(widget, "desk-notification-list")
                switch (test.stage++) {
                case 0:
                    AppearanceConfigService.widgetStyle = "color"
                    AppearanceConfigService.themeMode = "light"
                    for (let i = 3; i > 0; i--) add("QQ", "qq", i, false)
                    break
                case 1:
                    check(count("QQ") === 3 && rowIndex("QQ", "more") === -1, "few single-app messages show in full")
                    for (let i = 4; i <= 30; i++) add("QQ", "qq", i, true)
                    break
                case 2:
                    check(count("QQ") > 3 && count("QQ") < 30, "overflow automatically folds single-app history")
                    check(rowIndex("QQ", "more") >= 0, "overflow exposes more control")
                    check(list.contentHeight <= list.height, "collapsed preview and more fit inside widget: content=" + list.contentHeight + " viewport=" + list.height + " rows=" + count("QQ") + " row=" + find(widget,"message-QQ-30").height)
                    test.previousPreviewCount = count("QQ")
                    add("QQ", "qq", 31, true)
                    break
                case 3:
                    check(count("QQ") === test.previousPreviewCount, "continued QQ arrivals do not grow the preview")
                    check(widget.filteredHistory.get(1).notifId === 31, "latest incoming QQ message stays visible")
                    click("more-QQ")
                    break
                case 4:
                    check(count("QQ") === 31, "more still allows all history")
                    list.positionViewAtIndex(rowIndex("QQ", "more"), ListView.Contain)
                    break
                case 5:
                    click("more-QQ")
                    break
                case 6:
                    check(count("QQ") === test.previousPreviewCount, "collapse restores bounded preview")
                    add("WeChat", "wechat", 106, true)
                    break
                case 7:
                    check(count("QQ") <= 5 && count("微信") === 1, "another app gets its own visible space")
                    add("Telegram Desktop", "org.telegram.desktop", 204, true)
                    test.previewHeight = 420
                    break
                case 8:
                    check(count("QQ") === 1 && count("微信") === 1 && count("Telegram") === 1, "short widget reserves each app a message")
                    test.previewHeight = 1000
                    break
                case 9:
                    check(count("QQ") > 1, "resize increases preview capacity")
                    widget.selectedCategory = "QQ"
                    break
                case 10:
                    check(count("QQ") > 5 && count("QQ") < 31 && count("微信") === 0, "category tab also folds overflow")
                    widget.selectedCategory = "微信"
                    break
                case 11:
                    check(count("微信") === 1 && rowIndex("微信", "more") === -1, "small category needs no fold")
                    click("message-微信-106")
                    break
                case 12:
                    check(test.openedId === 106, "exact message callback survives folding")
                    ControlCenterService.removeHistoryById(106)
                    ControlCenterService.removeHistoryById(204)
                    widget.selectedCategory = "全部"
                    break
                case 13:
                    check(count("QQ") === test.previousPreviewCount, "sole QQ remains bounded after other apps disappear")
                    for (let i = 1; i < 29; i++) ControlCenterService.removeHistoryById(i)
                    break
                case 14:
                    check(count("QQ") === 3 && rowIndex("QQ", "more") === -1, "reduced history automatically unfolds once it fits")
                    ControlCenterService.notificationHistory.clear()
                    break
                case 15:
                    check(widget.filteredHistory.count === 0, "clear removes all presentation rows")
                    console.log("NOTIFICATION_FOLD_PASS small histories, single-app overflow, continued arrivals, real more/collapse clicks, resize, multi-app allocation, exact actions and removal")
                    Qt.quit()
                }
            } catch (error) { console.error("NOTIFICATION_FOLD_FAIL " + error); Qt.quit() }
        }
    }
    Timer { interval:12000; running:true; onTriggered:{console.error("NOTIFICATION_FOLD_FAIL timeout"); Qt.quit()} }
}
