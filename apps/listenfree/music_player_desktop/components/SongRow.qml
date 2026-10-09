import QtQuick
import QtQuick.Controls as Basic

Rectangle {
    id: row
    objectName: "songRow"
    property var track: ({})
    property url resolvedArtwork: ""
    property url artworkSource: track.artwork || resolvedArtwork
    property url fallbackArtwork: ""
    function requestArtwork() {
        if (!track.artwork && (track.source === "kw" || track.source === "wy") && playerController)
            playerController.requestTrackArtwork(track)
    }
    Component.onCompleted: requestArtwork()
    onTrackChanged: { resolvedArtwork = ""; requestArtwork() }
    property int rowIndex: 0
    property var playerController: typeof backendPlayerController !== "undefined" ? backendPlayerController : null
    Connections {
        target: row.playerController
        function onTrackArtworkResolved(source, rid, artwork) {
            if (row.track.source === source && String(row.track.rid) === rid)
                row.resolvedArtwork = artwork
        }
    }
    property bool current: {
        if (!playerController) return false
        const playingTrack = playerController.currentTrack // subscribe to track changes, including paused playback
        return playerController.isCurrentTrack(track)
    }
    property bool compact: width < 620
    property bool canvasText: false
    property bool lightText: false
    readonly property color primaryText: canvasText ? AppTheme.canvasText : lightText ? "#f0f4f6" : AppTheme.textPrimary
    readonly property color secondaryText: canvasText ? AppTheme.canvasSecondary : lightText ? "#c2cbd1" : AppTheme.textSecondary
    readonly property color mutedText: canvasText ? AppTheme.canvasSecondary : lightText ? "#aab8c4" : AppTheme.textMuted
    property bool showRemove: false
    property bool showDownload: true
    property string removeObjectName: "songRowRemove"
    property var favorites: typeof backendPlaylistController !== "undefined" ? backendPlaylistController : null
    readonly property bool liked: {
        if (track.radioId && typeof backendRadioController !== "undefined") {
            const radioRevision = backendRadioController.favoritesRevision
            return backendRadioController.isFavorite(track)
        }
        if (!favorites) return false
        const revision = favorites.likedTracksRevision
        return favorites.isTrackLiked(track)
    }
    readonly property bool local: String(track.localPath || "").length > 0 || String(track.source || "").toLowerCase() === "local"
    readonly property bool hovered: hover.hovered
    readonly property real numberWidth: compact ? 28 : 38
    readonly property real coverSize: compact ? 34 : 40
    readonly property real titleX: numberWidth + coverSize + 16
    readonly property real timeWidth: compact ? 38 : 58
    readonly property real removeWidth: showRemove ? 30 : 0
    readonly property real albumWidth: compact ? 0 : Math.max(115, width * .23)
    readonly property real actionsWidth: compact ? 84 : 102
    readonly property real titleWidth: Math.max(36, width - titleX - actionsWidth - albumWidth - timeWidth - removeWidth - 16)
    signal selectedRequested()
    signal activated()
    signal commandRequested(string command)
    signal contextRequested(real mouseX, real mouseY)

    height: compact ? 60 : 62
    radius: 10
    color: current ? (canvasText ? AppTheme.canvasSelected : lightText ? "#456b747d" : AppTheme.selected)
                   : hovered ? (canvasText ? AppTheme.canvasHover : lightText ? "#16ffffff" : AppTheme.controlHover) : "transparent"
    HoverHandler { id: hover }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) row.contextRequested(mouse.x, mouse.y)
            else row.selectedRequested()
        }
        onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) row.activated() }
    }
    Text {
        objectName: "songRowNumber"
        x: 2; width: row.numberWidth - 2; height: parent.height
        text: row.rowIndex + 1; visible: !row.hovered
        color: row.current ? AppTheme.accent : row.mutedText
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        font.family: AppTheme.fontFamily; font.pixelSize: 12
    }
    Item {
        objectName: "songRowPlay"
        x: 0; width: row.numberWidth; height: parent.height
        visible: row.hovered
        IconGlyph { anchors.centerIn: parent; width: 16; height: 16; kind: "play"; glyphColor: row.primaryText }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.activated() }
        Basic.ToolTip.visible: playHover.hovered
        Basic.ToolTip.text: qsTr("立即播放")
        HoverHandler { id: playHover }
    }
    CoverArt {
        objectName: "songRowCover"
        x: row.numberWidth + 6; width: row.coverSize; height: width
        anchors.verticalCenter: parent.verticalCenter
        source: row.artworkSource; artworkTier: "Thumbnail"; cornerRadius: 7; showShadow: false
        fallbackSource: row.fallbackArtwork
    }
    Column {
        objectName: "songRowTitle"
        x: row.titleX; width: row.titleWidth; anchors.verticalCenter: parent.verticalCenter; spacing: 4
        Text { width: parent.width; text: row.track.title || qsTr("未知歌曲"); color: row.primaryText; font.family: AppTheme.fontFamily; font.pixelSize: row.compact ? 12 : 14; font.weight: Font.Medium; elide: Text.ElideRight }
        Text { width: parent.width; text: (row.track.artist || qsTr("未知艺术家")) + (row.compact && row.track.album ? " · " + row.track.album : ""); color: row.secondaryText; font.family: AppTheme.fontFamily; font.pixelSize: 11; elide: Text.ElideRight }
    }
    Row {
        id: actions
        objectName: "songRowActions"
        x: row.titleX + row.titleWidth; width: row.actionsWidth; anchors.verticalCenter: parent.verticalCenter
        opacity: row.hovered ? 1 : 0
        visible: opacity > 0
        // Geometry is reserved even when hidden; nested clicks are exclusive.
        Action { objectName: "songRowDownload"; visible: row.showDownload; kind: "download"; tip: row.local ? qsTr("本地歌曲无需下载") : qsTr("下载"); enabled: !row.local; onTriggered: row.commandRequested("download") }
        Action { objectName: "songRowFavorite"; kind: row.liked ? "heartFilled" : "heart"; tip: row.liked ? qsTr("取消收藏") : qsTr("收藏"); highlighted: row.liked; onTriggered: row.commandRequested("favorite") }
        Action { objectName: "songRowNext"; kind: "playNext"; tip: qsTr("下一首播放"); onTriggered: row.commandRequested("play_next") }
    }
    Text {
        objectName: "songRowAlbum"
        x: actions.x + row.actionsWidth + 8; width: row.albumWidth - (row.compact ? 0 : 16)
        anchors.verticalCenter: parent.verticalCenter; visible: !row.compact
        text: row.track.album || qsTr("未知专辑"); color: row.secondaryText
        font.family: AppTheme.fontFamily; font.pixelSize: 12; elide: Text.ElideRight
    }
    Text {
        x: parent.width - row.timeWidth - row.removeWidth - 8; width: row.timeWidth
        anchors.verticalCenter: parent.verticalCenter
        text: typeof row.track.duration === "string" ? row.track.duration : row.formatTime(row.track.durationMs || row.track.duration || 0)
        color: row.mutedText; horizontalAlignment: Text.AlignRight; font.family: AppTheme.fontFamily; font.pixelSize: 11
    }
    Action { objectName: row.removeObjectName; x: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; width: 30; visible: row.showRemove; kind: "close"; tip: qsTr("从队列移除"); onTriggered: row.commandRequested("remove_queue") }
    function formatTime(ms) { const s=Math.max(0, Math.floor(ms / 1000)); return Math.floor(s/60) + ":" + String(s%60).padStart(2,"0") }
    component Action: Item {
        property string kind
        property string tip
        property bool highlighted: false
        signal triggered()
        width: row.actionsWidth / 3; height: 34
        opacity: enabled ? 1 : .3
        Rectangle { anchors.centerIn: parent; width: 28; height: 28; radius: 8; color: pointer.pressed ? AppTheme.selected : pointer.containsMouse ? AppTheme.controlHover : "transparent" }
        IconGlyph { anchors.centerIn: parent; width: 18; height: 18; kind: parent.kind; glyphColor: parent.highlighted ? AppTheme.accent : row.secondaryText }
        MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.triggered() }
        Basic.ToolTip.visible: pointer.containsMouse
        Basic.ToolTip.delay: 500
        Basic.ToolTip.text: tip
    }
}
