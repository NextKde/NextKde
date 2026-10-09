pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../components"

Item {
    id: page
    objectName: "collectionPage"

    property string kind: "Album"
    property bool onlineCollection: false
    property bool albumGridLayout: false
    readonly property bool albumWindow: kind === "Album" && !onlineCollection && !albumGridLayout
    property string title: "Sounds of Summer"
    property string subtitle: qsTr("The Beach Boys · 13 首歌曲")
    property color tint: "#edb62d"
    property int coverIndex: 1
    property var rows: []
    property string filterText: ""
    readonly property var visibleRows: (rows || []).filter(t => !filterText.trim().length || [t.title,t.artist,t.album].join(" ").toLocaleLowerCase().indexOf(filterText.trim().toLocaleLowerCase()) >= 0)
    property bool saved: false
    property bool darkMode: Qt.application.arguments.indexOf("--dark") >= 0
    property bool reduceMotion: false

    signal backRequested
    signal downloadAllRequested
    signal shuffleAllRequested
    property bool editablePlaylist: false
    signal playAllRequested
    signal saveRequested
    signal trackActivated(var track, var playbackContext)
    signal trackCommandRequested(string command, var track, int rowIndex, var playbackContext)
    signal trackSortRequested(string column, string order)
    signal transitionGeometryChanged(rect frameRect, rect artworkRect)

    readonly property int trackCount: rows ? rows.length : 0
    readonly property bool heroCollapsed: false
    readonly property real expandedHeroHeight: 184
    readonly property real compactHeroHeight: 58
    property string playCount: ""
    property string albumYear: ""
    property var artistVisual: ({})
    property real artistImageAspect: 1.6
    property bool artistArtworkReady: false
    readonly property real artistExpandedHeight: artistArtworkReady ? width / Math.max(.1,artistImageAspect)
                                                                   : Math.min(320,Math.max(240,height * .42))
    readonly property real artistScrollOffset: artistLoader.item ? artistLoader.item.scrollOffset : 0
    readonly property real artistCollapse: artistLoader.item ? artistLoader.item.collapse : 0
    property url artworkSource: ""
    property Item backdrop: null
    property bool transitionActive: false
    // The source card's glass frame expands to the entire detail surface;
    // artwork travels independently to the hero cover slot.
    readonly property real albumWindowWidth: Math.min(1080, width - 160)
    readonly property real albumArtworkSize: Math.min(224,albumWindowHeight*.42)
    readonly property real albumWindowHeight: Math.min(600, height - 176)
    readonly property rect transitionTargetFrame: albumWindow ? Qt.rect((width-albumWindowWidth)/2, 48, albumWindowWidth, albumWindowHeight) : Qt.rect(0, 0, width, height)
    readonly property rect transitionTargetArtwork: albumWindow ? Qt.rect(transitionTargetFrame.x+24, transitionTargetFrame.y+24, albumArtworkSize, albumArtworkSize) : Qt.rect(playlistHeader.x+cover.x, playlistHeader.y+cover.y, cover.width, cover.height)

    onTransitionTargetFrameChanged: transitionGeometryChanged(transitionTargetFrame,
                                                               transitionTargetArtwork)
    onTransitionTargetArtworkChanged: transitionGeometryChanged(transitionTargetFrame,
                                                                 transitionTargetArtwork)

    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    Item {
        id: playlistPage
        objectName: "playlistDetailPage"
        anchors.fill: parent
        visible: page.kind === "Playlist" || (page.kind === "Album" && !page.albumWindow)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
        Item {
            id: playlistHeader
            x: 32; y: 20; width: parent.width-64; height: cover.height + 40
            CoverArt {
                id: cover
                objectName: "playlistDetailArtwork"
                artworkTier: "Large"
                x: 0; y: 20; width: Math.min(240, Math.max(160, Math.min(page.width * .19, page.height * .26))); height: width
                source: page.artworkSource; cornerRadius: 16; showShadow: true
                opacity: page.transitionActive ? 0 : 1
            }
            Column {
                x: cover.width + 20; y: 32; width: parent.width-x; spacing: 7
                Text { width: parent.width; text: page.title; color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 24; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { width: parent.width; text: page.subtitle; color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 12; elide: Text.ElideRight }
                Text { visible: page.playCount.length>0; text: page.playCount + qsTr(" 次播放"); color: AppTheme.canvasSecondary; font.pixelSize: 11 }
            }
            Row {
                x: cover.width + 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 32; spacing: 14
                UiButton { objectName: "playlistPlayAllButton"; label: qsTr("播放全部"); foregroundColor: AppTheme.canvasText; onClicked: page.playAllRequested() }
                UiButton { objectName: "playlistShuffleButton"; label: qsTr("随机播放"); foregroundColor: AppTheme.canvasText; onClicked: page.shuffleAllRequested() }
                RoundIconButton { diameter: 36; kind: "download"; visible: page.kind !== "Album" || page.onlineCollection; transparentSurface: true; glyphColor: AppTheme.canvasText; tooltip: page.kind === "Album" ? qsTr("下载专辑") : qsTr("下载歌单"); onClicked: page.downloadAllRequested() }
                RoundIconButton { diameter: 36; kind: page.saved ? "heartFilled" : "heart"; transparentSurface: true; glyphColor: AppTheme.canvasText; tooltip: page.kind === "Album" ? qsTr("收藏专辑") : qsTr("收藏歌单"); onClicked: page.saveRequested() }
            }
        }
        SongTable {
            objectName: "playlistDetailTracks"
            x: 24; y: playlistHeader.y + playlistHeader.height + 22; width: parent.width-48; height: parent.height-y-6
            // Tracks continue behind the glass island without a reserved tail.
            rows: page.visibleRows; fallbackArtwork: page.artworkSource
            playlistMode: page.editablePlaylist
            scrollKey: "collection." + page.kind + "." + page.title
            darkMode: page.darkMode
            onTrackActivated: (row, playbackContext) => page.trackActivated(row, playbackContext)
            onCommandRequested: (command,track,index,playbackContext) => page.trackCommandRequested(command,track,index,playbackContext)
            onSortChanged: (column,order) => page.trackSortRequested(column,order)
        }
    }

    readonly property var albumSections: {
        if (page.kind !== "Artist") return []
        const groups = {}; const order = []
        for (const track of page.visibleRows) {
            const name = track.album || qsTr("未知专辑")
            if (!groups[name]) { groups[name] = { title: name, artwork: track.artwork || "", year: track.year || "", tracks: [] }; order.push(groups[name]) }
            groups[name].tracks.push(track)
        }
        return order
    }
    component TrackCell: SongRow {
        id: cell
        property int number: 0
        rowIndex: number
        onActivated: page.trackActivated(track, page.visibleRows)
        onCommandRequested: command => page.trackCommandRequested(command,track,number,page.visibleRows)
        onContextRequested: (mx,my) => { const p = mapToItem(page,mx,my); detailMenu.openAt(p.x,p.y,{ track: track, rowIndex: page.visibleRows.indexOf(track) }) }
    }
    Loader {
        anchors.fill: parent
        active: page.albumWindow
        sourceComponent: Item {
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: page.backRequested(); onWheel: wheel => wheel.accepted = true }
        Item {
            id: albumDetail
            objectName: "albumDetailSurface"
            x: page.transitionTargetFrame.x; y: page.transitionTargetFrame.y
            width: page.transitionTargetFrame.width; height: page.transitionTargetFrame.height
            GlassSurface {
                anchors.fill: parent; visible: !page.transitionActive
                cornerRadius: 24; tint: AppTheme.albumWindowTint; edgeColor: "#cfffffff"
                backdrop: page.backdrop; backdropBlur: 36; shadowOpacity: .55
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
            Column {
                x: 24; y: 24; width: page.albumArtworkSize; spacing: 10
                CoverArt { opacity: page.transitionActive ? 0 : 1; width: page.albumArtworkSize; height: width; source: page.artworkSource; artworkTier: "Large"; cornerRadius: 18 }
                Text { width: parent.width; text: page.title; font.family: AppTheme.fontFamily; font.pixelSize: 24; font.weight: Font.DemiBold; maximumLineCount: 2; wrapMode: Text.WordWrap; elide: Text.ElideRight; color: "#f5f7fa" }
                Text { width: parent.width; text: page.subtitle; font.pixelSize: 13; color: "#d1d8df"; wrapMode: Text.WordWrap }
                Text { text: (page.albumYear.length ? page.albumYear + " · " : "") + page.trackCount + qsTr(" 首歌曲"); color: "#bec8d2"; font.pixelSize: 12 }
                Row { spacing: 10
                    UiButton { label: qsTr("播放"); foregroundColor: "#f5f7fa"; emphasized: true; onClicked: page.playAllRequested() }
                    RoundIconButton { diameter: 36; kind: "heart"; darkMode: true; prominent: page.saved; onClicked: page.saveRequested() }
                }
            }
            SongTable {
                objectName: "albumTrackList"
                x: page.albumArtworkSize+48; y: 54; width: parent.width - page.albumArtworkSize - 72; height: parent.height - 74
                canvasText: false; lightText: true
                rows: page.visibleRows
                fallbackArtwork: page.artworkSource
                onTrackActivated: (track, playbackContext) => page.trackActivated(track, playbackContext)
                onCommandRequested: (command,track,index,playbackContext) => page.trackCommandRequested(command,track,index,playbackContext)
            }
            RoundIconButton { anchors.right: parent.right; anchors.rightMargin: 14; y: 12; diameter: 32; kind: "close"; glyphColor: "#f0f4f8"; transparentSurface: true; onClicked: page.backRequested() }
        }
    }
        }
    Loader {
        id: artistLoader
        anchors.fill: parent
        active: page.kind === "Artist"
        sourceComponent: Item {
        id: artistPage
        anchors.fill: parent
        readonly property real expandedHeight: page.artistExpandedHeight
        property bool userScrolled: false
        readonly property real compactHeight: 122
        readonly property real scrollOffset: {
            const revision=artistScroll.contentY
            return artistScroll.headerItem ? Math.max(0,-artistScroll.headerItem.mapToItem(artistPage,0,0).y) : 0
        }
        readonly property real heroHeight: Math.max(compactHeight,expandedHeight-scrollOffset)
        readonly property real collapse: 1-(heroHeight-compactHeight)/(expandedHeight-compactHeight)
        ListView {
            id: artistScroll
            objectName: "artistScroll"
            anchors.fill: parent
            clip: true
            layer.enabled: true
            layer.effect: ShaderEffect {
                property var source
                property real fadeTop: artistPage.heroHeight / Math.max(1,artistScroll.height)
                property real fadeWidth: 28 / Math.max(1,artistScroll.height)
                fragmentShader: "qrc:/shaders/artist-list-mask.frag.qsb"
            }
            boundsBehavior: Flickable.StopAtBounds
            onMovementStarted: artistPage.userScrolled = true
            spacing: 26
            cacheBuffer: 220
            model: page.kind === "Artist" ? page.albumSections : []
            header: Item {
                width: artistScroll.width; height: artistPage.expandedHeight
                onHeightChanged: {
                    Qt.callLater(function() {
                        artistScroll.forceLayout()
                        if (!artistPage.userScrolled) artistScroll.positionViewAtBeginning()
                    })
                }
            }
                    delegate: Item {
                        id: section
                        required property var modelData
                        objectName: "artistAlbumSection"
                        width: artistScroll.width; height: sectionBody.implicitHeight + 40
                        Rectangle {
                            objectName: "artistAlbumSurface"
                            x: 28; width: parent.width-56; height: parent.height
                            radius: 24; color: "#22ffffff"
                        }
                        Column {
                        id: sectionBody
                        x: 48; y: 20; width: parent.width - 96; spacing: 16
                        Row { spacing: 13
                            CoverArt { source: section.modelData.artwork; width: 58; height: 58; cornerRadius: 10; artworkTier: "Small"; showShadow: false }
                            Column { spacing: 6
                                width: sectionBody.width-72
                                Text { width: parent.width; text: section.modelData.title; elide: Text.ElideRight; color: "#f5f8f6"; font.family: AppTheme.fontFamily; font.pixelSize: 21; font.weight: Font.DemiBold }
                                Text { text: section.modelData.tracks.length + qsTr(" 首歌曲"); color: "#c2cbd1"; font.pixelSize: 12 }
                            }
                        }
                        Grid {
                            id: songGrid
                            width: parent.width; columns: width >= 820 ? 3 : width >= 530 ? 2 : 1; spacing: 10
                            Repeater { model: section.modelData.tracks
                                delegate: TrackCell { required property var modelData; required property int index; width: (songGrid.width - (songGrid.columns-1)*songGrid.spacing)/songGrid.columns; track: modelData; number: index; fallbackArtwork: section.modelData.artwork; lightText: true }
                            }
                        }
                        }
                    }
            footer: Item { height: 32; width: 1 }
        }
        Item {
            id: artistHero
            objectName: "artistStickyHeader"
            width: parent.width; height: artistPage.heroHeight; clip: true
            CoverArt {
                objectName: "artistDefaultCover"
                visible: !page.artistArtworkReady && artistPage.heroHeight > 230
                anchors.horizontalCenter: parent.horizontalCenter
                y: 70; width: Math.min(108,artistPage.heroHeight-198); height: width
                source: page.artworkSource; showShadow: false; cornerRadius: 16
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons
                onWheel: wheel => {
                    artistPage.userScrolled = true
                    artistScroll.contentY=Math.max(artistScroll.originY-artistPage.expandedHeight,Math.min(artistScroll.originY+artistScroll.contentHeight-artistScroll.height,artistScroll.contentY-wheel.angleDelta.y*.65))
                    wheel.accepted=true
                }
            }
            Item {
                id: artistActionLine
                anchors.bottom: parent.bottom
                width: parent.width; height: 64+48*(1-artistPage.collapse)
                RoundIconButton {
                    objectName: "artistPlayButton"
                    x: 32; anchors.verticalCenter: parent.verticalCenter; diameter: 38+16*(1-artistPage.collapse)
                    kind: "play"; glyphColor: "#263e34"; surfaceColor: "#f1f5f1"; prominent: true
                    tooltip: qsTr("播放"); enabled: page.rows.length > 0
                    onClicked: page.playAllRequested()
                }
                Item {
                    anchors.centerIn: parent; width: Math.max(140,parent.width-220); height: parent.height-12
                    Image {
                        id: artistSignature
                        objectName: "artistSignature"
                        anchors.centerIn: parent; width: Math.min(parent.width,360); height: 38+36*(1-artistPage.collapse)
                        visible: status === Image.Ready; source: page.artistVisual.signature || ""; fillMode: Image.PreserveAspectFit
                        asynchronous: true; sourceSize: Qt.size(900,260); mipmap: true
                    }
                    Text {
                        objectName: "artistNameFallback"
                        anchors.centerIn: parent; width: parent.width; text: page.title; visible: artistSignature.status !== Image.Ready
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                        color: "white"; font.pixelSize: 21+15*(1-artistPage.collapse); font.weight: Font.DemiBold
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                    RoundIconButton { objectName: "artistFavoriteButton"; diameter: 34; kind: page.saved ? "heartFilled" : "heart"; prominent: page.saved; darkMode: true; tooltip: qsTr("收藏"); onClicked: page.saveRequested() }

                }
            }
        }
    }
    }
    SongContextMenu {
        id: detailMenu
        objectName: "artistSongContextMenu"
        anchors.fill: parent
        darkMode: page.darkMode
        onCommandTriggered: (command,context) => page.trackCommandRequested(command,context.track,context.rowIndex,page.visibleRows)
    }

    Text {
        anchors.centerIn: parent
        visible: page.filterText.trim().length > 0 && page.visibleRows.length === 0
        text: qsTr("未找到相关歌曲"); color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 14
    }

}
