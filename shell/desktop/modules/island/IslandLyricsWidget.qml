import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.dock

// IslandLyricsWidget — the now-playing lyrics card.
//
// The shell already speaks to MPRIS and parses timed lyrics
// (DockMprisService + TimedLyrics.mjs); the desktop overlay draws them. This
// card draws the same thing inside the island, with the karaoke fill: the
// current line is drawn twice, and the bright copy is clipped to how far
// into the line the playback position is.
//
// The idea and the sweep are imported from Islet (Claritys11/islet, MIT);
// see THIRD_PARTY.md.
Rectangle {
    id: root

    required property string widgetId

    readonly property var player: DockMprisService.player
    readonly property bool hasTrack: DockMprisService.hasPlayer
    readonly property var lines: DockMprisService._lyricLines || []
    readonly property int lineIndex: DockMprisService._lyricIndex
    readonly property string currentLine: DockMprisService.currentLyric || ""
    readonly property string nextLine: DockMprisService.nextLyric || ""

    readonly property string title: {
        const metadata = player && player.metadata ? player.metadata : {}
        return String(metadata["xesam:title"] || "")
    }
    readonly property string artist: {
        const metadata = player && player.metadata ? player.metadata : {}
        const raw = metadata["xesam:artist"] || ""
        return Array.isArray(raw) ? String(raw[0] || "") : String(raw)
    }

    // How far through the current line the playback is. The fill is measured
    // against the line's own timestamps, so a slow ballad and a fast rap both
    // fill at a rate that matches the song.
    readonly property real lineProgress: {
        if (lineIndex < 0 || lineIndex >= lines.length)
            return 0
        const start = lines[lineIndex].time
        const end = (lineIndex + 1 < lines.length)
            ? lines[lineIndex + 1].time : start + 4
        if (end <= start)
            return 0
        const position = root.position
        if (!Number.isFinite(position))
            return 0
        return Math.max(0, Math.min(1, (position - start) / (end - start)))
    }

    // MPRIS position is lazy: the shell only polls it while the desktop
    // lyrics are on. The card needs it for the fill, so it polls its own.
    property real position: 0
    readonly property bool positionSupported:
        player ? Boolean(player.positionSupported) : false

    Timer {
        interval: 500
        repeat: true
        running: root.hasTrack && root.positionSupported
        onTriggered: {
            const value = root.player ? root.player.position : 0
            if (Number.isFinite(value))
                root.position = value
        }
    }

    color: "transparent"

    Column {
        anchors { fill: parent }
        spacing: 2

        Text {
            width: parent.width
            text: root.title.length > 0 ? root.title : I18n.tr("Nothing playing")
            color: Qt.rgba(1, 1, 1, 0.9)
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.artist
            color: Qt.rgba(1, 1, 1, 0.4)
            font.pixelSize: 9
            elide: Text.ElideRight
        }

        // The current line, drawn twice: the dim copy underneath, the bright
        // copy clipped to the progress.
        Item {
            width: parent.width
            height: lineText.implicitHeight
            visible: root.currentLine.length > 0

            Text {
                id: lineText
                width: parent.width
                text: root.currentLine
                color: Qt.rgba(1, 1, 1, 0.34)
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            Item {
                width: Math.round(lineText.width * root.lineProgress)
                height: parent.height
                clip: true

                Text {
                    width: lineText.width
                    text: lineText.text
                    color: "white"
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            width: parent.width
            visible: root.nextLine.length > 0
            text: root.nextLine
            color: Qt.rgba(1, 1, 1, 0.22)
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
