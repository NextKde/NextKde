import QtQuick
import QtTest
import "../.." as Settings
Item {
    width: 700; height: 950
    QtObject {
        id: testTheme
        property color primaryText: "#111111"
        property color secondaryText: "#777777"
        property color card: "white"
        property color accent: "#0a84ff"
        property color divider: "#cccccc"
        property color separator: "#eeeeee"
    }
    QtObject {
        id: fakeBridge
        property string lastError: ""
        property string request: ""
        signal notificationSnapshotChanged(var snapshot)
        function notificationSnapshot() { request = "snapshot" }
        function setNotificationPreference(key, value) { request = key + ":" + value }
        function setNotificationBlocked(key, value) { request = key + ":" + value }
    }
    Settings.NotificationsSettingsPage { id: page; width: 700; theme: testTheme; bridge: fakeBridge }
    TestCase {
        name: "NotificationsSettings"
        when: windowShown
        function test_page() {
            compare(fakeBridge.request, "snapshot")
            fakeBridge.notificationSnapshotChanged({ready: true, bannersEnabled: true, showNotificationBadges: true,
                sources: [{key: "desktop:mail", appName: "邮件"}], blockedKeys: []})
            verify(page.ready)
            compare(page.applications.length, 1)
            page.setPreference("showNotificationBadges", false)
            compare(fakeBridge.request, "showNotificationBadges:false")
            verify(page.pending)
            fakeBridge.lastError = "断开连接"
            fakeBridge.notificationSnapshotChanged({})
            verify(!page.pending)
            compare(page.errorText, "断开连接")
            fakeBridge.lastError = ""
            fakeBridge.notificationSnapshotChanged({ready:true, sources:[], blockedKeys:[], saveError:"保存失败"})
            compare(page.errorText, "保存失败")
            fakeBridge.notificationSnapshotChanged({ready:true, sources:[], blockedKeys:[], hideControlCenterNotifications:false})
            const toggle = findChild(page, "notification-hideControlCenterNotifications-switch")
            verify(toggle !== null)
            compare(toggle.checked, false)
            toggle.toggled(true)
            compare(fakeBridge.request, "hideControlCenterNotifications:true")
            fakeBridge.notificationSnapshotChanged({ready:true, sources:[], blockedKeys:[], hideControlCenterNotifications:true})
            compare(toggle.checked, true)
            page.appFilter = "邮件"
            compare(page.applications.length, 0)
        }
    }
}
