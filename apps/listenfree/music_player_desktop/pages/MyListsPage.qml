pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as Basic
import "../components"

Item {
    id: page
    objectName: "myListsPage"
    property bool darkMode: false
    property var catalog
    property var playlistController
    property var radioController
    property Item backdrop: null
    property int collectionTab: 0
    function saveNavigationState() { return { tab: collectionTab, y: gridPosition.saveNavigationState() } }
    function restoreNavigationState(state) {
        collectionTab = state.tab
        gridPosition.restoreNavigationState(state.y)
    }
    readonly property bool radioCollection: collectionTab === 1
    property string filterText: ""
    property var contextPlaylist: null
    property var contextCard: null
    property string renamingId: ""
    readonly property var allPlaylists: playlistController ? playlistController.playlists : []
    readonly property var visiblePlaylists: allPlaylists.filter(p => !filterText.trim().length ||
        [p.title, p.subtitle].join(" ").toLocaleLowerCase().indexOf(filterText.trim().toLocaleLowerCase()) >= 0 ||
        (p.tracks || []).some(t => [t.title,t.artist,t.album].join(" ").toLocaleLowerCase().indexOf(filterText.trim().toLocaleLowerCase()) >= 0))
    readonly property var visibleRadioFavorites: (radioController ? radioController.favorites : []).filter(r =>
        !filterText.trim().length || [r.title,r.artist,radioSource(r)].join(" ").toLocaleLowerCase().indexOf(filterText.trim().toLocaleLowerCase()) >= 0)
    function radioSource(row) {
        return row.radioProvider === "icecast" ? "Icecast" : row.radioProvider === "radiobrowser" ? "Radio Browser" : qsTr("网易云")
    }
    function radioSubtitle(row) {
        const kind = row.kind === "podcast" ? qsTr("播客") : row.isLive ? qsTr("直播") : qsTr("节目")
        return radioSource(row) + " · " + kind
    }
    function activateRadio(row) {
        if (row.kind === "podcast") podcastRequested(row)
        else trackActivated(row, visibleRadioFavorites)
    }
    onCollectionTabChanged: grid.contentY = 0
    signal openCollection(string kind, string title, color tint)
    signal collectionTransitionRequested(string kind, string title, color tint, rect frameRect, rect artworkRect, url artworkSource, var artworkItem)
    signal trackActivated(var track, var playbackContext)
    signal trackCommandRequested(string command, var track, int rowIndex, var playbackContext)
    signal trackSortRequested(string column, string order)
    signal createRequested(string name)
    signal updateRequested
    signal refreshPlaylistRequested(var playlist)
    signal renamePlaylistRequested(var playlist)
    signal removePlaylistRequested(var playlist)
    signal podcastRequested(var podcast)
    function openCard(data, card) {
        const frame = card.mapToItem(page,0,0)
        const art = card.artworkItem.mapToItem(page,0,0)
        collectionTransitionRequested("Playlist",data.title,AppTheme.accent,
            Qt.rect(frame.x,frame.y,card.width,card.height),Qt.rect(art.x,art.y,card.size,card.size),card.artworkSource,card.artworkItem)
    }
    function beginCreate(data) {
        renamingId = data ? data.id : ""
        nameField.text = data ? data.title : ""
        namePopup.open()
        Qt.callLater(() => { nameField.forceActiveFocus(); nameField.selectAll() })
    }
    Column {
        x: 32; y: 24; spacing: 6
        Text { objectName: "myFavoritesTitle"; text: qsTr("我的收藏"); color: AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 25; font.weight: Font.DemiBold }
        Text { text: page.radioCollection ? qsTr("%1 个电台、播客与节目").arg(page.visibleRadioFavorites.length) : qsTr("%1 个歌单").arg(page.visiblePlaylists.length); color: AppTheme.canvasSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 11 }
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 32; y: 29; spacing: 10
        visible: !page.radioCollection
        UiButton { objectName: "createPlaylistButton"; label: qsTr("新建歌单"); iconText: "plus"; foregroundColor: AppTheme.canvasText; onClicked: page.beginCreate(null) }
        RoundIconButton { kind: "repeat"; transparentSurface: true; glyphColor: AppTheme.canvasText; tooltip: qsTr("刷新网络歌单"); onClicked: page.updateRequested() }
    }
    GlassSurface {
        x: 32; y: 82; width: 168; height: 38; cornerRadius: 19
        backdrop: page.backdrop; opaqueBackdropBase: false; frosted: true; backdropBlur: 20
        tintStrength: AppTheme.canvasDark ? .12 : .16; shadowOpacity: 0
    }
    SegmentedTabBar {
        objectName: "myFavoritesTabs"
        x: 32; y: 82; cellWidth: 82; cellHeight: 34
        model: [qsTr("歌单"),qsTr("电台")]
        currentIndex: page.collectionTab; controlled: true
        textColor: AppTheme.canvasText
        border.width: 0
        color: "transparent"
        onSelected: (index, value) => page.collectionTab=index
    }
    GridView {
        id: grid
        ScrollPosition { id: gridPosition; view: grid; key: "my-lists" }
        objectName: "myPlaylistGrid"
        x: 24; y: 132; width: parent.width-48; height: parent.height-y
        bottomMargin: 96
        cellWidth: width/5
        cellHeight: tileSize + 43 + Math.max(0, Math.max(120,(height-bottomMargin)/3.5) - previousTileSize - 43)/3
        readonly property real previousTileSize: Math.min(cellWidth-32, Math.max(120,(height-bottomMargin)/3.5)-48)
        readonly property real tileSize: cellWidth - (cellWidth-previousTileSize)/3
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: page.radioCollection ? page.visibleRadioFavorites : page.visiblePlaylists
        Basic.ScrollBar.vertical: Basic.ScrollBar {
            policy: Basic.ScrollBar.AlwaysOff
            width: 0; visible: false
        }
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            width: grid.cellWidth; height: grid.cellHeight
            ArtworkTile {
                id: card
                objectName: (page.radioCollection ? "myRadioFavoriteCard" : "myPlaylistCard") + cell.index
                anchors.horizontalCenter: parent.horizontalCenter
                size: grid.tileSize
                title: cell.modelData.title || (page.radioCollection ? qsTr("未命名电台") : qsTr("未命名歌单"))
                subtitle: page.radioCollection ? page.radioSubtitle(cell.modelData) : cell.modelData.subtitle || ((cell.modelData.tracks || []).length + qsTr(" 首歌曲"))
                artworkSource: cell.modelData.artwork || ((cell.modelData.tracks || [])[0] || {}).artwork || ""
                onActivated: page.radioCollection ? page.activateRadio(cell.modelData) : page.openCard(cell.modelData,card)
                onContextRequested: (mx,my) => {
                    page.contextPlaylist=cell.modelData;page.contextCard=card
                    const point=card.mapToItem(contextMenu.parent,mx,my)
                    contextMenu.x=Math.min(point.x,contextMenu.parent.width-contextMenu.width-12)
                    contextMenu.y=Math.min(point.y,contextMenu.parent.height-contextMenu.height-12)
                    contextMenu.open()
                }
            }
        }
    }
    Text { anchors.centerIn: grid; visible: !grid.count; text: page.filterText.length ? qsTr("没有匹配的收藏") : page.radioCollection ? qsTr("在电台页面点击爱心，收藏喜欢的电台与节目") : qsTr("创建歌单，收藏喜欢的音乐"); color: AppTheme.canvasSecondary; font.pixelSize: 14 }
    Basic.Popup {
        id: contextMenu
        objectName: "myFavoritesContextMenu"
        readonly property bool radio: !!page.contextPlaylist && !!page.contextPlaylist.radioId
        parent: Basic.Overlay.overlay
        width: 190; height: menuColumn.implicitHeight+12
        modal: true; dim: false; padding: 6; focus: true
        onOpened: AppTheme.presentPopup(contextMenu)
        background: Rectangle { radius: 12; color: AppTheme.floatingSurface; border.color: AppTheme.border }
        Column {
            id: menuColumn; width: parent.width; spacing: 3
            UiButton { objectName: "myFavoriteOpen"; width: parent.width; label: contextMenu.radio ? (page.contextPlaylist.kind === "podcast" ? qsTr("打开播客") : qsTr("立即播放")) : qsTr("进入歌单"); onClicked: { contextMenu.close(); if(contextMenu.radio)page.activateRadio(page.contextPlaylist);else if(page.contextCard)page.openCard(page.contextPlaylist,page.contextCard) } }
            UiButton { width: parent.width; label: qsTr("更新网络歌单"); visible: !!page.contextPlaylist && !!page.contextPlaylist.reference; onClicked: { contextMenu.close();page.refreshPlaylistRequested(page.contextPlaylist) } }
            UiButton { width: parent.width; visible: !contextMenu.radio; label: qsTr("重命名"); onClicked: { contextMenu.close();page.beginCreate(page.contextPlaylist) } }
            UiButton { objectName: "myFavoriteRemove"; width: parent.width; label: contextMenu.radio ? qsTr("取消收藏") : qsTr("从我的收藏移除"); onClicked: { contextMenu.close();if(contextMenu.radio)page.radioController.toggleFavorite(page.contextPlaylist);else page.removePlaylistRequested(page.contextPlaylist) } }
        }
    }
    Basic.Popup {
        id: namePopup
        parent: Basic.Overlay.overlay
        anchors.centerIn: parent; width: 350; height: 160
        modal: true; focus: true; padding: 20
        onOpened: AppTheme.presentPopup(namePopup)
        background: Rectangle { radius: 16; color: AppTheme.floatingSurface; border.color: AppTheme.border }
        Column {
            width: parent.width; spacing: 14
            Text { text: page.renamingId.length ? qsTr("重命名歌单") : qsTr("新建歌单"); color: AppTheme.textPrimary; font.pixelSize: 18 }
            Basic.TextField { id: nameField; objectName: "playlistNameField"; width: parent.width; placeholderText: qsTr("歌单名称"); placeholderTextColor: AppTheme.textSecondary; color: AppTheme.textPrimary; background: Rectangle { radius: 8; color: AppTheme.field } onAccepted: saveName.clicked() }
            UiButton { id: saveName; label: qsTr("保存"); enabled: nameField.text.trim().length>0; onClicked: { if(page.renamingId.length)page.playlistController.rename(page.renamingId,nameField.text.trim());else page.createRequested(nameField.text.trim());namePopup.close() } }
        }
    }
}
