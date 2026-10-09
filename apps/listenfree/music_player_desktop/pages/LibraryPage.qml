pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import ListenFree.Native 1.0
import "../components"

Item {
    id: page

    objectName: "libraryPage"
    property string filterText: ""
    property var catalog
    property bool albumGridLayout: false
    readonly property bool gridLayout: section === "artists" || (section === "albums" && albumGridLayout)
    property var tracksModel
    property string section: "albums"
    // The proxy owns only source row indexes. Keep it detached when this
    // cached page is showing another section or an unfiltered song list.
    FilteredTrackModel {
        id: filteredTracks
        sourceTracks: page.section === "songs" && page.filterText.trim().length > 0
                      ? page.tracksModel : null
        filterText: page.filterText
    }
    property int selectedAlbumIndex: 1
    property bool albumPositionRestored: false
    function restoreAlbumPosition() {
        if(!albums.length)return
        if(!albumPositionRestored && typeof backendSettingsController!=="undefined" && backendSettingsController.value("list.rememberScrollPosition",true))
            selectedAlbumIndex=Number(backendSettingsController.value("scroll.library.albumIndex",1))
        selectedAlbumIndex=Math.max(0,Math.min(selectedAlbumIndex,albums.length-1))
        albumPositionRestored=true
    }
    function saveAlbumPosition() {
        if(albumPositionRestored && section==="albums" && typeof backendSettingsController!=="undefined" && backendSettingsController.value("list.rememberScrollPosition",true))
            backendSettingsController.setValue("scroll.library.albumIndex",selectedAlbumIndex)
    }
    // A layout setting can clamp the restored index while its binding evaluates.
    // Persist afterwards so the settings revision cannot re-enter that binding.
    onSelectedAlbumIndexChanged: { Qt.callLater(saveAlbumPosition); Qt.callLater(syncAlbumWindow) }
    readonly property bool albumFlowEnabled: section === "albums" && !albumGridLayout
    readonly property int loadedAlbumCount: albumWindow.count
    readonly property int albumCoverPixels: AppTheme.artworkPixels("Large", Screen.devicePixelRatio)
    onAlbumFlowEnabledChanged: Qt.callLater(syncAlbumWindow)
    // Match the bounded ListModel used by ImmersiveDiscQueue. Keep overlapping
    // delegates alive so a wheel step retargets their existing animations.
    ListModel { id: albumWindow }
    function syncAlbumWindow() {
        if (!albumFlowEnabled || !albums.length) { albumWindow.clear(); return }
        const first = Math.max(0, selectedAlbumIndex - 4)
        const last = Math.min(albums.length - 1, selectedAlbumIndex + 4)
        while (albumWindow.count && albumWindow.get(0).albumIndex < first) albumWindow.remove(0)
        while (albumWindow.count && albumWindow.get(albumWindow.count - 1).albumIndex > last)
            albumWindow.remove(albumWindow.count - 1)
        const before = albumWindow.count ? albumWindow.get(0).albumIndex - 1 : last
        for (let i = before; i >= first; --i) albumWindow.insert(0, { albumIndex: i })
        const after = albumWindow.count ? albumWindow.get(albumWindow.count - 1).albumIndex + 1 : first
        for (let i = after; i <= last; ++i) albumWindow.append({ albumIndex: i })
    }
    Component.onCompleted: syncAlbumWindow()
    Connections {
        target: typeof backendSettingsController!=="undefined" ? backendSettingsController : null
        function onValueChanged(key,value){if(key==="list.rememberScrollPosition" && !value)page.selectedAlbumIndex=0}
    }
    ScrollPosition { id: gridPosition; view: artistGrid; key: "library.grid."+page.section }
    function saveNavigationState() {
        return { albumIndex: selectedAlbumIndex, gridY: gridPosition.saveNavigationState(),
            songs: songLoader.item ? songLoader.item.saveNavigationState() : null }
    }
    function restoreNavigationState(state) {
        selectedAlbumIndex = Math.max(0, Math.min(state.albumIndex, albums.length - 1))
        albumPositionRestored = true
        gridPosition.restoreNavigationState(state.gridY)
        if (songLoader.item && state.songs) songLoader.item.restoreNavigationState(state.songs)
    }
    property bool darkMode: Qt.application.arguments.indexOf("--dark") >= 0
    property bool reduceMotion: false
    property bool deferCollectionOpen: false
    property bool collectionTransitionPrepared: false
    property rect transitionSourceFrame: Qt.rect(0, 0, 0, 0)
    property rect transitionSourceArtwork: Qt.rect(0, 0, 0, 0)
    property url transitionArtworkSource: ""
    property string transitionCollectionKind: ""
    property string transitionCollectionTitle: ""
    property color transitionCollectionTint: AppTheme.accent

    signal openCollection(string kind, string title, color tint)
    signal trackActivated(var track, var playbackContext)
    signal trackCommandRequested(string command, var track, int rowIndex, var playbackContext)
    signal trackSortRequested(string column, string order)
    signal collectionTransitionRequested(string kind, string title, color tint,
                                         rect frameRect, rect artworkRect, url artworkSource, var artworkItem)

    function matching(rows, fields) {
        const term = filterText.trim().toLocaleLowerCase()
        if (!term.length) return rows
        return rows.filter(row => fields.some(field => String(row[field] || "").toLocaleLowerCase().indexOf(term) >= 0))
    }
    readonly property var albums: page.visible && section === "albums"
                                  ? matching(catalog && catalog.albums ? catalog.albums : [], ["title"]) : []
    readonly property var artists: page.visible && section === "artists"
                                   ? matching(catalog && catalog.artists ? catalog.artists : [], ["name"]) : []
    readonly property bool usingTracksModel: section === "songs"
                                             && tracksModel !== null && tracksModel !== undefined
    readonly property var displayTracksModel: !usingTracksModel ? null
                                                : filterText.trim().length > 0 ? filteredTracks : tracksModel
    readonly property var songs: section !== "songs" || usingTracksModel ? []
                                                                       : matching(catalog && catalog.songs ? catalog.songs : [], ["title", "artist", "album"])
    onAlbumsChanged: { restoreAlbumPosition(); Qt.callLater(syncAlbumWindow) }
    readonly property string sectionTitle: section === "songs" ? qsTr("歌曲")
                                                   : section === "artists" ? qsTr("艺术家") : qsTr("专辑")
    readonly property string sectionCount: section === "songs" ? (usingTracksModel ? displayTracksModel.count : songs.length) + qsTr(" 首歌曲")
                                                   : section === "artists" ? artists.length + qsTr(" 位艺术家")
                                                   : albums.length + qsTr(" 张专辑")

    function albumOffset(relativeIndex) {
        const distance = Math.abs(relativeIndex)
        if (distance === 0)
            return 0
        const magnitude = distance === 1 ? 182
                          : distance === 2 ? 328 : 450 + (distance - 3) * 110
        return (relativeIndex < 0 ? -1 : 1) * magnitude * albumFlow.layoutScale
    }

    function albumRelative(index) {
        // The Figma cover flow is finite. Avoiding modulo wrap also prevents
        // the outside card from flying through the centre at either end.
        return index - selectedAlbumIndex
    }

    function mappedRect(item) {
        const topLeft = item.mapToItem(page, 0, 0)
        const bottomRight = item.mapToItem(page, item.width, item.height)
        return Qt.rect(Math.min(topLeft.x, bottomRight.x), Math.min(topLeft.y, bottomRight.y),
                       Math.abs(bottomRight.x - topLeft.x), Math.abs(bottomRight.y - topLeft.y))
    }

    function prepareCollectionTransition(kind, title, tint, frameItem, artworkItem, artworkSource) {
        transitionCollectionKind = kind
        transitionCollectionTitle = title
        transitionCollectionTint = tint
        transitionSourceFrame = mappedRect(frameItem)
        transitionSourceArtwork = mappedRect(artworkItem)
        transitionArtworkSource = artworkSource
        collectionTransitionPrepared = true
        collectionTransitionRequested(kind, title, tint, transitionSourceFrame,
                                      transitionSourceArtwork, artworkSource, artworkItem)
        if (!deferCollectionOpen)
            commitPreparedCollection()
    }

    function commitPreparedCollection() {
        if (!collectionTransitionPrepared)
            return
        collectionTransitionPrepared = false
        openCollection(transitionCollectionKind, transitionCollectionTitle,
                       transitionCollectionTint)
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    Text {
        id: titleLabel
        x: 38
        y: 18
        text: page.sectionTitle
        color: AppTheme.canvasText
        font.family: AppTheme.fontFamily
        font.pixelSize: 24
        font.weight: Font.DemiBold
    }

    Text {
        x: page.gridLayout ? titleLabel.x : titleLabel.x + titleLabel.width + 10
        y: page.gridLayout ? titleLabel.y + titleLabel.height + 6 : titleLabel.y + 9
        text: page.sectionCount
        color: AppTheme.canvasSecondary
        font.family: AppTheme.fontFamily
        font.pixelSize: 12
    }

    // Backend-capable four-column table. Library navigation stays in the
    // sidebar, so there are deliberately no duplicate page tabs here.
    Loader {
        id: songLoader
        active: page.section === "songs"
        x: 28
        y: 84
        width: page.width - 56
        height: page.height - y - 18
        sourceComponent: SongTable {
        anchors.fill: parent
        rows: page.usingTracksModel ? [] : page.songs
        sourceModel: page.displayTracksModel
        scrollKey: "library.songs." + page.filterText
        darkMode: page.darkMode
        onTrackActivated: function(row, playbackContext) { page.trackActivated(row, playbackContext) }
        onCommandRequested: function(command, track, rowIndex, playbackContext) {
            page.trackCommandRequested(command, track, rowIndex, playbackContext)
        }
        onSortChanged: function(column, order) {
            page.trackSortRequested(column, order)
        }
        }
    }

    Item {
        id: albumFlow
        objectName: page.section === "albums" ? "libraryAlbumFlow" : ""
        visible: page.section === "albums" && !page.albumGridLayout
        y: 82
        width: parent.width
        height: parent.height - y
        clip: true
        readonly property real layoutScale: Math.max(.85, Math.min(1, width / 833, (height - 134) / 365))
        readonly property real cardTop: Math.max(24, (height - 96 - 365 * layoutScale) / 2 + 16)

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                if (!page.albums.length)
                    return
                const direction = event.angleDelta.y < 0 ? 1 : -1
                page.selectedAlbumIndex = Math.max(0, Math.min(page.albums.length - 1,
                                                               page.selectedAlbumIndex + direction))
            }
        }

        Repeater {
            model: albumWindow

            delegate: Item {
                id: albumCard
                objectName: "albumCard" + albumIndex
                required property int albumIndex
                readonly property var album: page.albums[albumIndex] || ({})

                readonly property int relativeIndex: page.albumRelative(albumIndex)
                readonly property int distance: Math.abs(relativeIndex)
                readonly property bool active: distance === 0
                readonly property real spatialScale: distance === 0 ? 1
                                                     : distance === 1 ? .88
                                                     : distance === 2 ? .76 : .68
                readonly property real spatialOpacity: distance === 0 ? 1
                                                       : distance === 1 ? .86
                                                       : distance === 2 ? .50 : 0
                readonly property url artworkSource: album.artwork || Qt.resolvedUrl("../assets/album_Cover_"
                                                                    + ((albumIndex % 7) + 1) + ".png")

                z: 30 - distance
                width: 290 * albumFlow.layoutScale
                height: 365 * albumFlow.layoutScale
                x: albumFlow.width / 2 - width / 2
                y: albumFlow.cardTop
                scale: spatialScale
                opacity: spatialOpacity
                enabled: distance <= 2

                transform: [Rotation { origin.x: albumCard.width/2; origin.y: albumCard.height/2; axis.y: 1; axis.x: 0; axis.z: 0; angle: albumCard.relativeIndex === 0 ? 0 : albumCard.relativeIndex < 0 ? 28 : -28; Behavior on angle { NumberAnimation { duration: AppTheme.duration(240) } } }, Translate {
                    id: albumMotion
                    x: page.albumOffset(albumCard.relativeIndex)
                    y: albumCard.distance * 16 * albumFlow.layoutScale
                    Behavior on x {
                        NumberAnimation {
                            duration: page.reduceMotion ? 0 : AppTheme.duration(240)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                        }
                    }
                    Behavior on y {
                        NumberAnimation {
                            duration: page.reduceMotion ? 0 : AppTheme.duration(240)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                        }
                    }
                }]
                Behavior on scale {
                    NumberAnimation {
                        duration: page.reduceMotion ? 0 : AppTheme.duration(240)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                    }
                }
                Behavior on opacity { NumberAnimation { duration: page.reduceMotion ? 0 : AppTheme.duration(150) } }

                Loader {
                    anchors.fill: parent
                    active: page.section === "albums" && albumCard.distance <= 3
                    sourceComponent: Item {
                    id: cardVisual
                    anchors.fill: parent
                    scale: cardHover.hovered ? 1.016 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: page.reduceMotion ? 0 : AppTheme.duration(120)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1]
                        }
                    }

                    GlassSurface {
                        anchors.fill: parent
                        cornerRadius: 24
                        tint: albumCard.active ? AppTheme.albumShellTint : page.darkMode ? "#8c313a42" : "#647f878c"
                        edgeColor: albumCard.active ? "#d9ffffff" : "#aaffffff"
                        shadowOpacity: albumCard.active ? .22 : .13
                    }

                    CoverArt {
                        id: albumCover
                        artworkTier: "Large"
                        sourcePixelSize: page.albumCoverPixels
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8 * albumFlow.layoutScale
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 16 * albumFlow.layoutScale
                        height: width
                        cornerRadius: 18
                        showShadow: false
                        source: albumCard.artworkSource
                    }

                    Text {
                        anchors.top: parent.top
                        anchors.topMargin: 12 * albumFlow.layoutScale
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 24
                        text: albumCard.album.title || ""
                        color: "#f8f8f8"
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 22 * Math.min(albumFlow.layoutScale, 1.25)
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.top: parent.top
                        anchors.topMargin: 45 * albumFlow.layoutScale
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 24
                        text: albumCard.album.artist || ""
                        color: albumCard.active ? "#e4e7e9" : "#c8cbd0"
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 13 * Math.min(albumFlow.layoutScale, 1.25)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    HoverHandler { id: cardHover }
                    TapHandler {
                        onTapped: {
                            if (!albumCard.active) {
                                page.selectedAlbumIndex = albumCard.albumIndex
                            } else {
                                page.prepareCollectionTransition("Album",
                                                                 albumCard.album.title,
                                                                 albumCard.album.color || "#efb52c",
                                                                 cardVisual, albumCover,
                                                                 albumCard.artworkSource)
                            }
                        }
                    }
                }
                }
            }
        }

        // Only the artwork is reflected; metadata is intentionally excluded.
        Item {
            id: reflectionClip
            // Follow the resized card's lower edge, never the old design y.
            y: albumFlow.cardTop + 362 * albumFlow.layoutScale
            width: parent.width
            height: Math.max(0, parent.height - y)
            clip: true
            opacity: .18

            Repeater {
                model: albumWindow
                delegate: Image {
                    required property int albumIndex
                    id: reflectionImage
                    objectName: "albumReflection" + albumIndex
                    readonly property int relativeIndex: page.albumRelative(albumIndex)
                    readonly property int distance: Math.abs(relativeIndex)
                    width: 274 * albumFlow.layoutScale
                    height: width
                    x: reflectionClip.width / 2 - width / 2
                    y: 0
                    scale: distance === 0 ? 1 : distance === 1 ? .88 : distance === 2 ? .76 : .68
                    opacity: distance === 0 ? 1 : distance === 1 ? .82 : distance === 2 ? .42 : 0
                    // Share the primary cover's decoded pixmap and CDN variant.
                    source: distance <= 3 && page.albums[albumIndex]
                        ? AppTheme.artworkUrl(page.albums[albumIndex].artwork || "", page.albumCoverPixels) : ""
                    sourceSize: Qt.size(page.albumCoverPixels, page.albumCoverPixels)
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    transform: [
                        Translate {
                            id: reflectionMotion
                            x: page.albumOffset(reflectionImage.relativeIndex)
                            Behavior on x {
                                NumberAnimation {
                                    duration: page.reduceMotion ? 0 : AppTheme.duration(240)
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                                }
                            }
                        },
                        Scale {
                            origin.x: reflectionImage.width / 2
                            origin.y: reflectionImage.height / 2
                            yScale: -1
                        }
                    ]
                    Behavior on scale {
                        NumberAnimation {
                            duration: page.reduceMotion ? 0 : AppTheme.duration(240)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
                        }
                    }
                    Behavior on opacity { NumberAnimation { duration: page.reduceMotion ? 0 : AppTheme.duration(150) } }
                }
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: page.darkMode ? "#16151b21" : "#16d7d9db" }
                    GradientStop { position: 0.48; color: page.darkMode ? "#b8151b21" : "#b8d7d9db" }
                    GradientStop { position: 1.0; color: page.darkMode ? "#ff151b21" : "#ffd8dadc" }
                }
            }
        }
    }

    GridView {
        id: artistGrid
        objectName: page.section === "albums" ? "libraryAlbumGrid" : "libraryArtistGrid"
        visible: page.gridLayout
        x: 24; y: 100; width: parent.width-48; height: parent.height-y
        bottomMargin: 96
        // Keep artwork at its normal-window size; a wider window shows more columns.
        cellWidth: width / Math.max(1, Math.floor(width / 157))
        cellHeight: tileSize + 46
        readonly property real tileSize: 132
        // Decode the adjacent viewport before it enters the clipped grid.
        // This also retains recently painted delegates during scroll reversals.
        cacheBuffer: Math.max(0, height)
        // Buffered delegates are not painted. Prepare one row's scene-graph
        // textures before it crosses the viewport; clip still hides the row.
        displayMarginBeginning: cellHeight
        displayMarginEnd: cellHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        model: page.gridLayout ? (page.section === "artists" ? page.artists : page.albums) : []
        delegate: Item {
            id: artistCard
            required property int index
            required property var modelData
            width: artistGrid.cellWidth; height: artistGrid.cellHeight
            ArtworkTile {
                id: artistPortrait
                objectName: (page.section === "artists" ? "libraryArtistCard" : "libraryAlbumCard") + artistCard.index
                anchors.horizontalCenter: parent.horizontalCenter
                size: artistGrid.tileSize
                portrait: false
                title: (page.section === "artists" ? artistCard.modelData.name : artistCard.modelData.title) || ""
                subtitle: artistCard.modelData.subtitle || ""
                artworkSource: artistCard.modelData.artwork || ""
                onActivated: page.prepareCollectionTransition(page.section === "artists" ? "Artist" : "Album",title,
                    AppTheme.accent,artistPortrait,artistPortrait.artworkItem,artistPortrait.artworkSource)
            }
        }
    }
    Text {
        objectName: "localSearchEmpty"
        anchors.centerIn: parent
        visible: page.filterText.trim().length > 0 && (page.section === "songs" ? (page.usingTracksModel ? page.displayTracksModel.count === 0 : !page.songs.length) : page.section === "artists" ? !page.artists.length : !page.albums.length)
        text: qsTr("没有找到“") + page.filterText + "”"
        color: AppTheme.textSecondary; font.family: AppTheme.fontFamily; font.pixelSize: 16
    }

}
