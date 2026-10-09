pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import ListenFree.Native 1.0
import "../components"

Item {
    id: page
    objectName: "albumMosaicPage"
    property var catalog: null
    property string filterText: ""
    property real sidebarWidth: 212
    property bool darkMode: false
    property real panX: 0
    property real panY: 0
    property var selectedAlbum: null
    property string selectedKey: ""
    property rect selectedRect: Qt.rect(0,0,0,0)
    property real expansion: 0
    property Item selectedTile: null
    property var pendingAlbum: null
    readonly property int visibleTileCount: tiles.count
    readonly property var albums: {
        const all = catalog ? catalog.albums || [] : []
        const query = filterText.trim().toLocaleLowerCase()
        return query.length ? all.filter(a => [a.title,a.artist].join(" ").toLocaleLowerCase().indexOf(query)>=0) : all
    }
    readonly property var selectedTracks: !selectedAlbum || !catalog ? [] : (catalog.songs || []).filter(
        song => (song.album || qsTr("未知专辑")) === selectedAlbum.title && (song.artist || "") === (selectedAlbum.artist || ""))
    signal trackActivated(var track, var playbackContext)
    signal trackCommandRequested(string command, var track, int rowIndex, var playbackContext)
    signal playAllRequested(var tracks)

    onFilterTextChanged: { closeAlbum(); panX=0; panY=0 }
    function closeAlbum() {
        pendingAlbum=null; camera.stop(); expandAnimation.stop(); expandAnimation.to=0
        if(expansion>0)expandAnimation.start()
        else { selectedAlbum=null; selectedKey=""; selectedTile=null }
    }
    // A separable monotone map preserves every shared boundary in the chunk.
    // Only the target rectangles are calculated here; animation interpolates
    // the same split lines for all eight tiles, so they can never overlap.
    function stretch(value, start, end) {
        const targetStart=start/(4-(end-start))
        if(value<=start)return start>0 ? value*targetStart/start : 0
        if(value>=end)return end<4 ? targetStart+3+(value-end)*(1-targetStart)/(4-end) : 4
        return targetStart+(value-start)*3/(end-start)
    }
    function layoutRect(rect) {
        if(!selectedAlbum)return rect
        const cx=Math.floor(selectedRect.x/576)*576, cy=Math.floor(selectedRect.y/576)*576
        if(Math.floor(rect.x/576)*576!==cx || Math.floor(rect.y/576)*576!==cy)return rect
        const sx=(selectedRect.x-cx)/144, ex=(selectedRect.x+selectedRect.width+3-cx)/144
        const sy=(selectedRect.y-cy)/144, ey=(selectedRect.y+selectedRect.height+3-cy)/144
        const x=cx+stretch((rect.x-cx)/144,sx,ex)*144, y=cy+stretch((rect.y-cy)/144,sy,ey)*144
        const right=cx+stretch((rect.x+rect.width+3-cx)/144,sx,ex)*144
        const bottom=cy+stretch((rect.y+rect.height+3-cy)/144,sy,ey)*144
        return Qt.rect(x,y,right-x-3,bottom-y-3)
    }
    function openAlbum(album, key, rect, tileItem) {
        if(selectedKey && selectedKey!==key && expansion>0){
            pendingAlbum={album:album,key:key,rect:rect,tile:tileItem}
            expandAnimation.stop();expandAnimation.to=0;expandAnimation.start();return
        }
        activateAlbum(album,key,rect,tileItem)
    }
    function activateAlbum(album,key,rect,tileItem) {
        camera.stop()
        selectedAlbum=album; selectedKey=key; selectedRect=rect; selectedTile=tileItem; expansion=0
        tracks.positionViewAtBeginning()
        const target=layoutRect(rect)
        cameraX.to=target.x+target.width/2-(sidebarWidth+(width-sidebarWidth)/2)
        cameraY.to=target.y+target.height/2-(58+(height-58-104)/2)
        camera.start(); expandAnimation.stop();expandAnimation.to=1;expandAnimation.start()
        forceActiveFocus()
    }
    Keys.onEscapePressed: closeAlbum()
    ParallelAnimation {
        id: camera
        NumberAnimation { id: cameraX; target: page; property: "panX"; duration: AppTheme.duration(420); easing.type: Easing.OutCubic }
        NumberAnimation { id: cameraY; target: page; property: "panY"; duration: AppTheme.duration(420); easing.type: Easing.OutCubic }
    }
    NumberAnimation {
        id: expandAnimation; target: page; property: "expansion"; to: 1
        duration: AppTheme.duration(420); easing.type: Easing.OutCubic
        onFinished: if(page.expansion===0){
            const next=page.pendingAlbum;page.pendingAlbum=null
            page.selectedAlbum=null;page.selectedKey="";page.selectedTile=null
            if(next && next.tile)page.activateAlbum(next.album,next.key,next.rect,next.tile)
        }
    }

    Rectangle { anchors.fill: parent; color: "#20232b" }
    AlbumMosaicModel {
        id: tiles
        objectName: "albumMosaicModel"
        albumCount: page.visible ? page.albums.length : 0
        viewport: Qt.rect(page.panX,page.panY,page.width,page.height)
        expandedTile: page.selectedAlbum ? page.selectedRect : Qt.rect(0,0,0,0)
    }
    // Positions are world coordinates minus the camera, not a huge texture/item.
    Repeater {
        model: tiles
        delegate: Rectangle {
            id: tile
            objectName: "albumMosaicTile"
            required property string tileKey
            required property real tileX
            required property real tileY
            required property real tileWidth
            required property real tileHeight
            required property int albumIndex
            readonly property var album: page.albums[albumIndex] || ({})
            readonly property rect targetRect: page.layoutRect(Qt.rect(tileX,tileY,tileWidth,tileHeight))
            x: tileX+(targetRect.x-tileX)*page.expansion-page.panX
            y: tileY+(targetRect.y-tileY)*page.expansion-page.panY
            width: tileWidth+(targetRect.width-tileWidth)*page.expansion
            height: tileHeight+(targetRect.height-tileHeight)*page.expansion
            Component.onDestruction: if(page.selectedTile===tile){page.selectedTile=null;Qt.callLater(page.closeAlbum)}
            color: "#343a43"; clip: true
            Image {
                objectName: "mosaicCoverImage"
                anchors.fill: parent
                source: AppTheme.artworkUrl(tile.album.artwork || "",320)
                sourceSize: Qt.size(320,320)
                asynchronous: true; cache: false
                fillMode: Image.PreserveAspectCrop
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: "#12131b27" }
                    GradientStop { position: .45; color: "#27131b27" }
                    GradientStop { position: 1; color: "#d5101520" }
                }
            }
            Column {
                x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 12; width: parent.width-24; spacing: 4
                opacity: page.selectedKey===tile.tileKey ? 1-page.expansion : 1
                visible: tile.width>78 && tile.height>70
                Text { width: parent.width; text: tile.album.title || qsTr("未知专辑"); color: "#f6f5fa"; font.family: AppTheme.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold; maximumLineCount: 2; wrapMode: Text.Wrap; elide: Text.ElideRight }
                Text { width: parent.width; text: tile.album.artist || ""; color: "#c4cad2"; font.family: AppTheme.fontFamily; font.pixelSize: 10; elide: Text.ElideRight }
            }
            Rectangle { anchors.fill: parent; color: hover.hovered ? "#13ffffff" : "transparent"; border.width: hover.hovered ? 1 : 0; border.color: "#98ffffff" }
            HoverHandler { id: hover; cursorShape: wallDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            TapHandler { enabled: page.selectedKey!==tile.tileKey; onTapped: page.openAlbum(tile.album,tile.tileKey,Qt.rect(tile.tileX,tile.tileY,tile.tileWidth,tile.tileHeight),tile) }
        }
    }
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 88
        gradient: Gradient {
            GradientStop { position: 0; color: "#b8101722" }
            GradientStop { position: .65; color: "#82101722" }
            GradientStop { position: 1; color: "#00101722" }
        }
    }
    // Pointer handlers let a drag cancel tile taps using Qt's drag threshold.
    DragHandler {
        id: wallDrag
        target: null
        enabled: !detailsHover.hovered && !songMenu.opened
        property real startX: 0
        property real startY: 0
        onActiveChanged: if (active) { camera.stop(); startX=page.panX; startY=page.panY }
        onActiveTranslationChanged: if (active) { page.panX=startX-activeTranslation.x; page.panY=startY-activeTranslation.y }
    }
    WheelHandler {
        target: null
        enabled: !detailsHover.hovered && !songMenu.opened
        onWheel: event => {
            camera.stop()
            if (event.pixelDelta.x || event.pixelDelta.y) { page.panX-=event.pixelDelta.x; page.panY-=event.pixelDelta.y }
            else { page.panX-=event.angleDelta.x*.6; page.panY-=event.angleDelta.y*.6 }
            event.accepted=true
        }
    }
    Rectangle {
        id: details
        objectName: "mosaicAlbumDetail"
        parent: page.selectedTile || page
        anchors.fill: parent
        visible: !!page.selectedTile && !!page.selectedAlbum
        color: "transparent"; clip: true; z: 3
        opacity: page.expansion
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "#9c111721" }
                GradientStop { position: .35; color: "#d9111721" }
                GradientStop { position: 1; color: "#ee111721" }
            }
        }
        HoverHandler { id: detailsHover }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted=true }
        Item {
            anchors.fill: parent; opacity: Math.max(0,(page.expansion-.35)/.65)
            Text { x: 20; y: 20; width: parent.width-106; text: page.selectedAlbum ? page.selectedAlbum.title : ""; color: "#f7f8fb"; font.family: AppTheme.fontFamily; font.pixelSize: 23; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Text { x: 20; y: 54; width: parent.width-40; text: (page.selectedAlbum ? page.selectedAlbum.artist || "" : "") + " · " + page.selectedTracks.length + qsTr(" 首歌曲"); color: "#c7cdd6"; font.family: AppTheme.fontFamily; font.pixelSize: 12; elide: Text.ElideRight }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12; y: 17; spacing: 2
                RoundIconButton { objectName: "mosaicPlayAll"; diameter: 32; kind: "play"; transparentSurface: true; glyphColor: "#f4f6f9"; tooltip: qsTr("播放全部"); onClicked: page.playAllRequested(page.selectedTracks) }
                RoundIconButton { objectName: "mosaicClose"; diameter: 32; kind: "close"; transparentSurface: true; glyphColor: "#f4f6f9"; onClicked: page.closeAlbum() }
            }
            ListView {
                id: tracks
                objectName: "mosaicAlbumTracks"
                x: 10; y: 86; width: parent.width-20; height: parent.height-y-10
                model: page.selectedTracks
                clip: true; reuseItems: true; cacheBuffer: 60
                boundsBehavior: Flickable.StopAtBounds
                Basic.ScrollBar.vertical: Basic.ScrollBar {
                    objectName: "mosaicTracksScrollbar"
                    width: 0; visible: false; policy: Basic.ScrollBar.AlwaysOff
                }
                delegate: SongRow {
                    required property var modelData
                    required property int index
                    width: tracks.width; track: modelData; rowIndex: index; lightText: true
                    // All rows in this window share the album thumbnail/cache.
                    artworkSource: page.selectedAlbum ? page.selectedAlbum.artwork || "" : ""
                    fallbackArtwork: page.selectedAlbum ? page.selectedAlbum.artwork || "" : ""
                    onActivated: page.trackActivated(track, page.selectedTracks)
                    onCommandRequested: command => page.trackCommandRequested(command,track,index,page.selectedTracks)
                    onContextRequested: (mx,my) => { const p=mapToItem(page,mx,my); songMenu.openAt(p.x,p.y,{track:track,rowIndex:index}) }
                }
                WheelHandler {
                    target: null
                    onWheel: event => {
                        const delta=event.pixelDelta.y || event.angleDelta.y*.5
                        tracks.contentY=Math.max(0,Math.min(Math.max(0,tracks.contentHeight-tracks.height),tracks.contentY-delta))
                        event.accepted=true
                    }
                }
            }
        }
        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: "#aac2cedc" }
    }
    SongContextMenu {
        id: songMenu
        objectName: "mosaicSongContextMenu"
        anchors.fill: parent; z: 5
        onCommandTriggered: (command,data) => page.trackCommandRequested(command,data.track,data.rowIndex,page.selectedTracks)
    }
    Column {
        visible: page.albums.length===0
        x: page.sidebarWidth+32; y: 106; width: page.width-x-32; spacing: 10
        Text { text: qsTr("专辑"); color: "#f1f3f7"; font.pixelSize: 26; font.family: AppTheme.fontFamily }
        Text { text: page.filterText.length ? qsTr("没有匹配的专辑") : qsTr("将音乐加入资料库后，专辑将在这里铺开"); color: "#bdc6d2"; font.pixelSize: 13; font.family: AppTheme.fontFamily }
    }
}
