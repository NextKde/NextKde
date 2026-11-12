// Safe visual host: there is no real authenticator, session lock or network.
// qml6 Preview.qml -- --wallpaper /path/to/image --output /path/to/preview.png
import QtQuick
import QtQuick.Window
import "../headless" as Stubs

Window {
    id: host
    title: "KOS 锁屏预览 — 不会锁定会话"
    width: Number(argument("--width", "1600"))
    height: Number(argument("--height", "900"))
    visible: true
    color: "#17232e"
    property Stubs.AuthenticatorStub authenticator: Stubs.AuthenticatorStub { graceLocked: false }
    property QtObject config: QtObject { property bool showMediaControls: true; property bool kosShowNotifications: true }
    property string kscreenlocker_userName: "KOS"
    property string kscreenlocker_userImage: ""
    property var wallpaper: wallpaperStub
    property Item wallpaperStub: Item {
        Image {
            source: host.argument("--wallpaper", "") ? "file://" + host.argument("--wallpaper", "") : Qt.resolvedUrl("../headless/wallpaper-sample.png")
            fillMode: Image.PreserveAspectCrop
        }
    }
    function argument(name, fallback) {
        const args = Qt.application.arguments
        const index = args.indexOf(name)
        return index >= 0 && index + 1 < args.length ? args[index + 1] : fallback
    }
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const child of item.children || []) { const found = find(child, name); if (found) return found }
        return null
    }
    QtObject {
        id: player
        property string serviceName: "org.mpris.MediaPlayer2.preview"
        property bool available: true
        property bool canControl: true
        property string playbackStatus: "Paused"
        property bool playing: false
        property real positionSeconds: 27
        function metadataText(key) {
            return ({"xesam:title": "I Don't Know — Radio Mix", "xesam:artist": "Erika", "mpris:length": "201000000"})[key] || ""
        }
    }
    Loader {
        id: screen
        anchors.fill: parent
        source: "../../contents/lockscreen/LockScreen.qml"
        onStatusChanged: if (status === Loader.Error) Qt.exit(1)
        onLoaded: item.debug = host.argument("--debug", "false") === "true"
    }
    Timer {
        interval: 1200; running: true
        onTriggered: {
            const clock = host.find(screen.item, "lockClock")
            clock.now = new Date(2026, 9, 16, 8, 37)
            const media = host.find(screen.item, "lockLyricsLoader")
            if (media.item) media.item.playerSources = [player]
            const notifications = host.find(screen.item, "lockNotificationsLoader")
            if (notifications.item) notifications.item.applyPayload(JSON.stringify([
                {id: "preview-1", appName: "文件管理器", appIcon: "system-file-manager", createdAt: Date.now() - 420000},
                {id: "preview-2", appName: "日历", appIcon: "view-calendar", createdAt: Date.now() - 1440000},
                {id: "preview-3", appName: "KOS 音乐", appIcon: "multimedia-player", createdAt: Date.now() - 2340000}
            ]))
        }
    }
    Timer {
        interval: 2300; running: true
        onTriggered: {
            console.log("KOS_PREVIEW", host.width, host.height, "graphics", screen.item.softwareRendering ? "software" : "GPU")
            const icon = host.find(screen.item, "lockNotificationIcon")
            if (icon) console.log("KOS_ICON", icon.source, icon.valid, icon.status, icon.width, icon.height, icon.visible, icon.color)
            const clock = host.find(screen.item, "lockClock")
            console.log("KOS_CLOCK", clock.timeString, clock.locale.timeFormat(Locale.ShortFormat))
            screen.item.grabToImage(result => {
                const path = host.argument("--output", "/tmp/kos-lockscreen-preview.png")
                const ok = result.saveToFile(path)
                console.log("KOS_PREVIEW_SAVED", path, ok)
                Qt.exit(ok ? 0 : 2)
            })
        }
    }
}
