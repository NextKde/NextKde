import QtQuick
import Quickshell
import qs.desktop.modules.notifications
import qs.desktop.modules.platform

Scope {
    id: root
    property int step: 0
    property int writesBeforeDisconnect: 0
    QtObject {
        id: policy
        property bool ready: true
        property bool historyEnabled: true
        property bool doNotDisturbEnabled: false
        property var blockedKeys: []
        function isKeyBlocked(key) { return blockedKeys.indexOf(key) >= 0 }
    }
    NotificationLockScreenBridge {
        historyService: NotificationHistoryService
        policyService: policy
    }
    function check(ok, message) {
        if (!ok) throw new Error(message)
    }
    function latest() { return PlatformClient.writes[PlatformClient.writes.length - 1] }
    function push(id, name) {
        NotificationHistoryService.push({notifId: id, appName: name,
            desktopEntry: "mail", appIcon: "org.kde.kmail", summary: "PRIVATE SUMMARY",
            body: "PRIVATE BODY", urgency: 1, timestamp: 1700000000000 + step})
    }
    Timer {
        interval: 30
        repeat: true
        running: true
        onTriggered: {
            try {
                switch (root.step++) {
                case 0:
                    root.check(JSON.stringify(root.latest()) === "[]", "startup empty")
                    root.push(1, "First")
                    break
                case 1:
                    root.check(root.latest()[0].appName === "First", "arrival")
                    root.check(root.latest()[0].summary === "" && root.latest()[0].body === "", "privacy")
                    root.push(1, "Replacement")
                    break
                case 2:
                    root.check(root.latest().length === 1 && root.latest()[0].appName === "Replacement", "replacement")
                    root.check(root.latest()[0].id === "1", "stable history identity")
                    NotificationHistoryService.remove(1)
                    break
                case 3:
                    root.check(root.latest().length === 0, "removal")
                    root.push(2, "Second")
                    break
                case 4:
                    root.check(root.latest().length === 1, "second arrival")
                    policy.doNotDisturbEnabled = true
                    break
                case 5:
                    root.check(root.latest().length === 0, "DND")
                    policy.doNotDisturbEnabled = false
                    policy.blockedKeys = ["desktop:mail"]
                    break
                case 6:
                    root.check(root.latest().length === 0, "blocked history")
                    policy.blockedKeys = []
                    break
                case 7:
                    root.check(root.latest().length === 1, "unblock")
                    policy.historyEnabled = false
                    break
                case 8:
                    root.check(root.latest().length === 0, "history disabled")
                    policy.historyEnabled = true
                    policy.ready = false
                    break
                case 9:
                    root.check(root.latest().length === 0, "policy startup gate")
                    PlatformClient.connected = false
                    root.writesBeforeDisconnect = PlatformClient.writes.length
                    policy.ready = true
                    root.push(2, "Offline replacement")
                    break
                case 10:
                    root.check(PlatformClient.writes.length === root.writesBeforeDisconnect, "no disconnected writes")
                    NotificationHistoryService.clear()
                    PlatformClient.connected = true
                    break
                case 11:
                    root.check(root.latest().length === 0, "reconnect uses fresh state")
                    console.log("LOCKSCREEN_PUBLISHER_PASS")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("LOCKSCREEN_PUBLISHER_FAIL " + error)
                Qt.quit()
            }
        }
    }
}
