import QtQuick
import Quickshell
import qs.desktop.modules.bar
import qs.desktop.modules.notifications
Scope {
    id: test
    property int stage: 0
    property var survivingCard: null
    function assert(value, message) { if (!value) throw new Error(message) }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    function push(id) {
        NotificationHistoryService.push({notifId:id, appName:"邮件", desktopEntry:"org.test.mail", appIcon:"",
            summary:"消息 " + id, body:id >= 49 && id < 100 ? "这是一条较长的消息，用于检查卡片内展开时的文本裁切和玻璃边界。".repeat(12) : "用于检查通知列表滚动和删除时的新消息。", timestamp:Date.now(), urgency:1})
    }
    FloatingWindow {
        visible:true; implicitWidth:336; implicitHeight:340
        NotificationHistoryPane { id:pane; x:20; y:20; width:296; height:300 }
    }
    Timer {
        running:true; repeat:true; interval:340
        onTriggered: {
            const list = test.find(pane, "notification-history-list")
            if (test.stage === 0) {
                for (let i=0; i<50; i++) test.push(i+1)
            } else if (test.stage === 1) {
                test.assert(!pane.expanded && list.count === 3 && pane.displayedMessageCount === 3, "preview has exactly three independent rows, without hidden blank history")
                test.assert(list.itemAtIndex(0).cardItem && list.itemAtIndex(1).cardItem && list.itemAtIndex(2).cardItem,
                    "same-app messages remain three actual cards")
                test.assert(list.itemAtIndex(0).cardItem.historyKey !== list.itemAtIndex(1).cardItem.historyKey, "cards have separate identities")
                test.survivingCard = list.itemAtIndex(1).cardItem
                test.find(list.itemAtIndex(0).cardItem, "notification-remove-button").clicked()
                test.assert(NotificationHistoryService.count === 49, "dismiss button removes one message")
                pane.requestExpanded(true)
            } else if (test.stage === 2) {
                test.assert(list.contentHeight > list.height, "expanded deck is scrollable")
                test.assert(list.itemAtIndex(0).cardItem === test.survivingCard, "expansion preserves the surviving card instance")
                test.assert(list.itemAtIndex(0).cardItem.canExpand, "long message can expand inside its card")
                list.itemAtIndex(0).cardItem.detailsRequested(true)
            } else if (test.stage === 3) {
                test.assert(list.itemAtIndex(0).cardItem.height > 112 && list.itemAtIndex(0).cardItem.clip, "expanded text remains clipped by its animated card")
                list.flick(0, -1200)
                pane.height = 220
            } else if (test.stage === 4) {
                test.assert(list.contentY > list.originY, "kinetic flick moves the list")
                test.assert(list.height > 0 && list.y + list.height <= pane.height - 38, "small viewport clips before footer")
                pane.clearHistory()
                test.push(100)
            } else if (test.stage === 5) {
                test.assert(NotificationHistoryService.count === 1, "arrival survives clear")
                // Exits begin on a rendered frame, so a fixed wall-clock delay
                // can expire first on a busy VM. The outer timeout bounds this wait.
                if (pane.historyExitCount !== 0) return
                pane.expanded = false
            } else if (test.stage === 6) {
                test.assert(list.count === 1 && list.itemAtIndex(0).cardItem.enabled, "collapse restores interactive preview")
                test.assert(list.contentY <= list.originY + Math.max(0, list.contentHeight - list.height) + 1, "shrinking history clamps scroll position")
                NotificationPolicyService.showPreview = false
                test.assert(!list.itemAtIndex(0).cardItem.showPreview && !list.itemAtIndex(0).cardItem.canExpand,
                    "hidden previews cannot expose content through expansion")
                NotificationPolicyService.showPreview = true
                console.log("HISTORY_PANE_PASS")
                Qt.quit()
            }
            test.stage++
        }
    }
    Timer {
        running:true; interval:6000
        onTriggered: {
            console.error("pane test timeout at stage " + test.stage + ", pending exits=" + pane.historyExitCount)
            Qt.quit()
        }
    }
}
