import QtQuick
import QtTest
import "../headless" as Stubs
import "../../contents/lockscreen" as Lock

Item {
    id: host
    width: 1600; height: 900
    property Stubs.AuthenticatorStub authenticator: Stubs.AuthenticatorStub { graceLocked: false }
    property QtObject config: QtObject {
        property bool showMediaControls: true
        property bool kosShowNotifications: true
    }
    property var wallpaper: null
    property string kscreenlocker_userName: "Preview"
    property string kscreenlocker_userImage: ""
    Loader { id: screen; anchors.fill: parent; active: false; source: "../../contents/lockscreen/LockScreen.qml" }
    QtObject {
        id: player
        property string serviceName: "org.mpris.MediaPlayer2.test"
        property bool available: true
        property bool canControl: true
        property string playbackStatus: "Playing"
        property bool playing: true
        property real positionSeconds: 10
        function metadataText(key) { return key === "xesam:title" ? "Test track" : key === "mpris:length" ? "100000000" : "" }
    }
    Component { id: animatedWallpaper; Rectangle { color: "steelblue" } }
    Lock.LockNotifications { id: notificationView; visible: false }
    Lock.MacLockClock { id: sampleClock; now: new Date(2026, 9, 16, 8, 37); visible: false }
    TestCase {
        name: "LockScreenLayout"
        when: windowShown
        function init() {
            failOnWarning(/ReferenceError|TypeError|Unable to assign|Binding loop|Cannot assign|Required property|Failed to find/)
            host.width = 1600; host.height = 900
            config.showMediaControls = true; config.kosShowNotifications = true
            player.available = true
            screen.active = true
            tryCompare(screen, "status", Loader.Ready)
            tryCompare(screen.item, "reveal", 1)
        }
        function cleanup() { host.wallpaper = null; screen.active = false; wait(0) }
        function inBounds(item) {
            const point = item.mapToItem(screen.item, 0, 0)
            verify(point.x >= -1 && point.y >= -1, "top/left in bounds")
            verify(point.x + item.width <= host.width + 1, "right in bounds")
            verify(point.y + item.height <= host.height + 1, "bottom in bounds")
        }
        function test_layout_data() {
            return [{tag: "desktop", w: 1600, h: 900}, {tag: "small", w: 800, h: 600},
                {tag: "portrait", w: 768, h: 1024}, {tag: "narrow", w: 360, h: 640}]
        }
        function test_layout(data) {
            host.width = data.w; host.height = data.h
            const media = findChild(screen.item, "lockLyricsLoader")
            tryCompare(media, "status", Loader.Ready)
            media.item.playerSources = [player]
            tryVerify(() => media.height > 0)
            wait(20)
            const clock = findChild(screen.item, "lockClock")
            const account = findChild(screen.item, "lockAccount")
            const field = findChild(screen.item, "passwordField")
            for (const item of [clock, account, field, media]) inBounds(item)
            verify(clock.y + clock.height < media.y)
            verify(media.y + media.height < account.y)
            verify(field.width < host.width * 0.6)
            player.available = false
            tryCompare(media, "height", 0)
        }
        function test_wallpaperLateReparent() {
            screen.active = false
            wait(0)
            host.wallpaper = createTemporaryObject(animatedWallpaper, host)
            verify(host.wallpaper !== null)
            screen.active = true
            compare(screen.status, Loader.Ready)
            compare(screen.item.wallpaperSource.toString(), "")
            compare(screen.item.hasWallpaper, true)
            const backdrop = findChild(screen.item, "lockWallpaperBackdrop")
            compare(host.wallpaper.parent, backdrop)
            // Mirror createViewForScreen() synchronously after setSource(). The
            // queued production callback, not a manual sync, must re-adopt it.
            host.wallpaper.parent = screen.item
            host.wallpaper.anchors.fill = screen.item
            host.wallpaper.z = -1000
            tryCompare(host.wallpaper, "parent", backdrop, 1000)
            compare(host.wallpaper.width, backdrop.width)
            compare(host.wallpaper.height, backdrop.height)
            compare(host.wallpaper.z, -1)
        }
        function test_preferences() {
            const media = findChild(screen.item, "lockLyricsLoader")
            const notifications = findChild(screen.item, "lockNotificationsLoader")
            tryCompare(notifications, "status", Loader.Ready)
            config.showMediaControls = false; config.kosShowNotifications = false
            tryCompare(media, "active", false)
            tryCompare(notifications, "active", false)
            const field = findChild(screen.item, "passwordField")
            verify(field.visible)
            field.forceActiveFocus()
            keyClick(Qt.Key_A)
            compare(screen.item.entry, "a")
        }
        function test_notificationMalformedData() {
            notificationView.applyPayload("not json")
            compare(notificationView.notifications.length, 0)
            notificationView.applyPayload('{"appName":"invalid"}')
            compare(notificationView.notifications.length, 0)
            notificationView.applyPayload(JSON.stringify([{appName: "Sample", appIcon: "", createdAt: Date.now()}]))
            compare(notificationView.notifications.length, 1)
            notificationView.applyPayload("[]")
            compare(notificationView.notifications.length, 0)
        }
        function test_clockFormat() {
            verify(!/^0\d:/.test(sampleClock.timeString))
            verify(sampleClock.timeString.indexOf("8:37") >= 0)
        }
    }
}
