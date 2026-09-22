import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Reads KOS Music's standard MPRIS metadata directly from the session bus.
// It is loaded independently by LockScreen.qml, so media integration can fail
// without ever taking the authentication surface down.
Item {
    id: root
    objectName: "lockLyrics"
    // DBusPropertyMap mutates nested values without replacing its map object.
    // Depend on an explicit revision so currentLine/nextLine re-evaluate after
    // the asynchronous GetAll/update("Metadata") response completes.
    property int metadataRevision: 0

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

    function metadataText(key) {
        const revision = metadataRevision
        if (!serviceWatcher.registered || !mpris.properties)
            return ""
        const metadata = root.unwrap(mpris.properties["Metadata"])
        if (!metadata)
            return ""
        const value = root.unwrap(metadata[key])
        return value === null || value === undefined ? "" : String(value)
    }

    readonly property string currentLine:
        metadataText("kos:currentLyric") || metadataText("xesam:asText")
    readonly property string nextLine: metadataText("kos:nextLyric")

    implicitWidth: 820
    implicitHeight: currentLine.length > 0 ? (nextLine.length > 0 ? 84 : 58) : 0
    visible: serviceWatcher.registered && currentLine.length > 0

    DBus.DBusServiceWatcher {
        id: serviceWatcher
        busType: DBus.BusType.Session
        watchedService: "org.mpris.MediaPlayer2.kosmusic"
    }

    DBus.Properties {
        id: mpris
        busType: DBus.BusType.Session
        service: serviceWatcher.registered ? serviceWatcher.watchedService : ""
        path: "/org/mpris/MediaPlayer2"
        iface: "org.mpris.MediaPlayer2.Player"

        onPropertiesChanged: function(interfaceName, changedProperties, invalidatedProperties) {
            // Force recursive decoding of the nested a{sv} map on dynamic lyric
            // updates. The completed refresh advances metadataRevision below.
            if (changedProperties && changedProperties["Metadata"] !== undefined) {
                update("Metadata")
                metadataRefreshTimer.restart()
            }
        }
        onRefreshed: root.metadataRevision++
    }

    Timer {
        id: metadataRefreshTimer
        interval: 80
        repeat: false
        onTriggered: root.metadataRevision++
    }

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: Qt.rgba(0.04, 0.04, 0.06, 0.42)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.18)

        Text {
            id: currentText
            objectName: "lockCurrentLyric"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: root.nextLine.length > 0 ? 13 : 15
            text: root.currentLine
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
            color: Qt.rgba(1, 1, 1, 0.58)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.pixelSize: 13
        }
    }
}
