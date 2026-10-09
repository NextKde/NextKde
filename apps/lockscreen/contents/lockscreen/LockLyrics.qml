import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Reads NextKDE music players' MPRIS metadata directly from the session bus.
// It is loaded independently by LockScreen.qml, so media integration can fail
// without ever taking the authentication surface down.
Item {
    id: root
    objectName: "lockLyrics"

    function unwrap(value) {
        let result = value
        for (let depth = 0; depth < 5 && result !== null
                && typeof result === "object"; depth++) {
            if (result.value !== undefined)
                result = result.value
            else if (Number(result.length) === 1 && result[0] !== undefined)
                result = result[0]
            else
                break
        }
        return result
    }

    // Select by playback state, then keep a paused session available. Both
    // properties maps must stay alive so a newly playing app wins immediately.
    readonly property var activeSource: listenfree.playing ? listenfree
        : kosmusic.playing ? kosmusic
        : listenfree.available && listenfree.hasTrack ? listenfree : kosmusic
    function metadataText(key) { return activeSource ? activeSource.metadataText(key) : "" }
    readonly property bool lyricsAllowed: metadataText("kos:lockscreenLyricsEnabled") !== "false"
    readonly property string currentLine: lyricsAllowed ? metadataText("kos:currentLyric") || metadataText("xesam:asText") : ""
    readonly property string nextLine: lyricsAllowed ? metadataText("kos:nextLyric") : ""
    readonly property string trackTitle: metadataText("xesam:title")
    readonly property string trackArtist: metadataText("xesam:artist")
    readonly property bool playing: !!activeSource && activeSource.playing
    readonly property string statusText: {
        const state = metadataText("kos:playbackState")
        return state === "Loading" || state === "Buffering" ? qsTr("正在加载…")
            : state === "Error" ? qsTr("播放失败")
            : playing ? qsTr("正在播放") : state === "Stopped" || state === "Idle" ? qsTr("已停止") : qsTr("已暂停")
    }
    function control(method) {
        if (!activeSource || !activeSource.available || ["Previous", "PlayPause", "Next"].indexOf(method) < 0) return
        DBus.SessionBus.asyncCall({ service: activeSource.serviceName, path: "/org/mpris/MediaPlayer2",
            iface: "org.mpris.MediaPlayer2.Player", member: method, arguments: [] }, function() {}, function() {})
    }
    implicitWidth: 820
    implicitHeight: trackTitle.length > 0 ? 64 + (currentLine.length > 0 ? (nextLine.length > 0 ? 72 : 48) : 0) : 0
    visible: !!activeSource && activeSource.available && trackTitle.length > 0

    component LyricSource: Item {
        id: source
        required property string serviceName
        property int revision: 0
        readonly property bool available: watcher.registered
        readonly property bool playing: {
            const current = revision
            return available && !!properties.properties && root.unwrap(properties.properties["PlaybackStatus"]) === "Playing"
        }
        readonly property bool hasTrack: metadataText("xesam:title").length > 0
        function metadataText(key) {
            const current = revision
            if (!available || !properties.properties) return ""
            const metadata = root.unwrap(properties.properties["Metadata"])
            const value = metadata ? root.unwrap(metadata[key]) : null
            return value === null || value === undefined ? "" : String(value)
        }
        DBus.DBusServiceWatcher {
            id: watcher
            busType: DBus.BusType.Session
            watchedService: source.serviceName
            onRegisteredChanged: source.revision++
        }
        DBus.Properties {
            id: properties
            busType: DBus.BusType.Session
            service: watcher.registered ? watcher.watchedService : ""
            path: "/org/mpris/MediaPlayer2"
            iface: "org.mpris.MediaPlayer2.Player"
            onPropertiesChanged: function(interfaceName, changedProperties, invalidatedProperties) {
                if (changedProperties && changedProperties["Metadata"] !== undefined) update("Metadata")
                if (changedProperties && changedProperties["PlaybackStatus"] !== undefined) update("PlaybackStatus")
                refreshTimer.restart()
            }
            onRefreshed: source.revision++
        }
        Timer { id: refreshTimer; interval: 80; onTriggered: source.revision++ }
    }
    LyricSource { id: listenfree; serviceName: "org.mpris.MediaPlayer2.listenfree" }
    LyricSource { id: kosmusic; serviceName: "org.mpris.MediaPlayer2.kosmusic" }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(0.04, 0.04, 0.06, 0.42)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)

        Image {
            id: cover
            x: 16; y: 12; width: 40; height: 40
            source: root.metadataText("mpris:artUrl")
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
        }
        Text {
            objectName: "lockTrackTitle"
            x: cover.visible ? 68 : 24; y: 12
            width: parent.width - x - mediaControls.width - 32
            text: root.trackTitle + (root.trackArtist.length ? " · " + root.trackArtist : "")
            textFormat: Text.PlainText
            color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            x: cover.visible ? 68 : 24; y: 34
            text: root.statusText
            color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 12
        }
        Row {
            id: mediaControls
            anchors { right: parent.right; rightMargin: 18; top: parent.top; topMargin: 14 }
            spacing: 8
            Repeater {
                model: ["Previous", "PlayPause", "Next"]
                delegate: Rectangle {
                    required property string modelData
                    width: 36; height: 36; radius: 18
                    color: mediaHover.hovered ? "#35ffffff" : "#16ffffff"
                    Canvas {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        property string method: parent.modelData
                        property bool paused: !root.playing
                        onPausedChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset(); ctx.fillStyle = "white"
                            if (method === "PlayPause" && !paused) {
                                ctx.fillRect(4, 3, 3, 12); ctx.fillRect(11, 3, 3, 12)
                            } else {
                                const backwards = method === "Previous"
                                ctx.save()
                                if (backwards) { ctx.translate(18, 0); ctx.scale(-1, 1) }
                                ctx.beginPath(); ctx.moveTo(4, 3); ctx.lineTo(14, 9); ctx.lineTo(4, 15); ctx.closePath(); ctx.fill()
                                if (method !== "PlayPause") ctx.fillRect(14, 3, 2, 12)
                                ctx.restore()
                            }
                        }
                    }
                    HoverHandler { id: mediaHover }
                    TapHandler { onTapped: root.control(parent.modelData) }
                }
            }
        }

        Text {
            id: currentText
            objectName: "lockCurrentLyric"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 68
            visible: text.length > 0
            text: root.currentLine
            textFormat: Text.PlainText
            color: Qt.rgba(1, 1, 1, 0.96)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font { pixelSize: 20; weight: Font.DemiBold }
        }

        Text {
            anchors { left: parent.left; right: parent.right; top: currentText.bottom }
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 6
            visible: text.length > 0
            text: root.nextLine
            textFormat: Text.PlainText
            color: Qt.rgba(1, 1, 1, 0.58)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: 13
        }
    }
}
