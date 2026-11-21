import QtQuick
import QtQuick.Window
import Quickshell
import "./lockscreen" as Lock

// A real production consumer on CTest's private bus, never a session lock.
Scope {
    Window {
        width: 320
        height: 300
        visible: true
        Lock.LockNotifications {
            id: view
            width: parent.width
            onNotificationsChanged: Qt.callLater(reportState)
            function reportState() {
                const cards = view.children.filter(child => child.objectName === "lockNotificationCard")
                const appNames = cards.map(card => card.children.find(child =>
                    child.objectName === "lockNotificationAppName").text)
                console.log("LOCKSCREEN_UI_STATE " + JSON.stringify({
                    notifications: view.notifications, appNames: appNames
                }))
            }
            Component.onCompleted: {
                console.log("LOCKSCREEN_UI_CONSUMER_READY")
                Qt.callLater(reportState)
            }
        }
    }
}
