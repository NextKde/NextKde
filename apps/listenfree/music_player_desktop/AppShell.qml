pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Controls as Basic
import "components"
import "pages"

Item {
    id: shell

    TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        onPressedChanged: if (pressed && searchInput.activeFocus) {
            const local = searchField.mapFromItem(shell, point.position.x, point.position.y)
            if (local.x < 0 || local.y < 0 || local.x > searchField.width || local.y > searchCapsule.height)
                searchInput.focus = false
        }
    }

    property var catalog: null
    property var facade: null
    property var hostWindow: null
    property var appController: null
    property var playerController: null
    property var libraryController: null
    property var downloadController: null
    property var radioController: typeof backendRadioController !== "undefined" ? backendRadioController : null
    property bool radioReturnToFavorites: false
    property bool downloadsOpen: false
    property var pendingDownloadTracks: []
    property var downloadSpecifications: []
    function chooseDownload(tracks) {
        pendingDownloadTracks = tracks
        downloadSpecifications = downloadController ? downloadController.specifications(tracks) : []
        downloadPicker.open()
    }
    Basic.Popup {
        id: downloadPicker
        onOpened: AppTheme.presentPopup(downloadPicker)
        objectName: "downloadSpecificationDialog"
        parent: Basic.Overlay.overlay
        anchors.centerIn: parent
        width: 390
        height: downloadOptions.implicitHeight + 40
        padding: 20
        modal: true
        focus: true
        closePolicy: Basic.Popup.CloseOnEscape | Basic.Popup.CloseOnPressOutside
        background: Rectangle { radius: 20; color: AppTheme.cardStrong; border.color: AppTheme.border }
        contentItem: Column {
            id: downloadOptions
            objectName: "downloadSpecificationOptions"
            spacing: 12
            Text { text: qsTr("选择下载规格"); font.pixelSize: 22; font.weight: Font.DemiBold; color: AppTheme.textPrimary }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: AppTheme.textSecondary; font.pixelSize: 12
                text: shell.downloadSpecifications.length ? qsTr("按当前音源声明的能力提供选项，具体歌曲以解析结果为准。") : qsTr("当前音源未提供这些歌曲的可用下载规格。请在设置中选择支持对应平台的音源。") }
            Repeater {
                model: shell.downloadSpecifications
                delegate: UiButton {
                    required property var modelData
                    width: downloadOptions.width
                    label: modelData.label
                    onClicked: {
                        shell.downloadController.add(shell.pendingDownloadTracks, modelData.value)
                        downloadPicker.close()
                    }
                }
            }
            UiButton { label: qsTr("取消"); onClicked: downloadPicker.close() }
        }
    }
    property var playlistController: null
    property var pendingPlaylistTracks: []
    readonly property var editablePlaylists: playlistController ? playlistController.playlists.filter(function(p) { return !p.reference }) : []
    property bool addPlaylistOpen: false
    property bool addPlaylistCreateOnly: false
    property var onlineController: null
    property var settingsController: null
    EqualizerPopup { id: equalizerPopup; controller: shell.playerController }
    MetadataMatchPopup {
        id: metadataMatchPopup
        controller: shell.playerController
        onAcceptedValues: values => musicEditor.fillMetadata(values)
    }
    LyricsMatchPopup {
        id: lyricsMatchPopup
        controller: shell.playerController
        onAcceptedLyrics: (text, intoEditor) => {
            if(intoEditor)musicEditor.setLyrics(text)
            else if(shell.playerController)shell.playerController.applyLyricMatch(track,text)
        }
    }
    property var sourceController: null
    property string currentRoute: "library/songs"
    property bool settingsOpen: false
    property bool nowPlayingOpen: false
    property bool queueOpen: false
    property bool queueFromNowPlaying: false
    property bool queueFromOverflow: false
    property bool queueFromImmersive: false
    property real queueProgress: queueOpen ? 1 : 0
    property bool playerCollapsed: false
    property bool playing: playerController ? playerController.state === "Playing" : false
    property bool darkMode: false
    property string uiLanguage: "zh-CN"
    property bool desktopTransparencyActive: false
    property string uiFontFamily: "SystemDefault"
    property bool animationsEnabled: true
    property string animationStyle: "Elegant"
    property bool sidebarCollapsed: false
    property bool useBackendModels: appController ? appController.mockMode === false : false
    property var queueSongs: appController && appController.mockMode === true
                             && !useBackendModels && playerController ? playerController.queueSongs : []
    property int refreshRateLimit: 60
    property real morphProgress: 0
    property real coverMorphProgress: 0
    property bool morphAnimating: false
    property bool morphClosing: false
    property bool collectionMorphActive: false
    property bool collectionMorphClosing: false
    property bool collectionMorphAvailable: false
    property real collectionMorphProgress: 0
    property rect collectionMorphSourceFrame: Qt.rect(0, 0, 0, 0)
    property rect collectionMorphSourceArtwork: Qt.rect(0, 0, 0, 0)
    property url collectionMorphArtworkSource: ""
    property Item collectionMorphSourceItem: null
    property string collectionMorphKind: "Album"
    property string albumLayoutMode: "Flow"
    function refreshAlbumLayout() {
        albumLayoutMode=settingsController ? String(settingsController.value("appearance.albumLayout","Flow")) : "Flow"
    }
    onSettingsControllerChanged: refreshAlbumLayout()
    readonly property bool albumGridLayout: albumLayoutMode === "Grid"
    readonly property bool collectionMorphUsesGrid: collectionMorphKind === "Playlist"
                                                   || (collectionMorphKind === "Album" && albumGridLayout)
    property color collectionMorphTint: AppTheme.accent
    property color accentColor: AppTheme.accent
    readonly property bool artistCanvasActive: currentRoute === "detail/artist" && !settingsOpen
    readonly property bool albumMosaicLayout: albumLayoutMode === "Mosaic"
    Connections {
        target: shell.settingsController
        function onValueChanged(key,value) { if(key === "appearance.albumLayout")shell.albumLayoutMode=String(value) }
    }
    readonly property bool mosaicCanvasActive: albumMosaicLayout && currentRoute === "library/albums" && !settingsOpen
    readonly property bool artworkCanvasActive: artistCanvasActive || mosaicCanvasActive
    property point mosaicPosition: Qt.point(0,0)
    Binding { target: AppTheme; property: "darkArtworkCanvas"; value: shell.mosaicCanvasActive && !shell.nowPlayingOpen }
    readonly property url artistHeroSource: {
        const visual = playerController ? playerController.artistVisual || ({}) : ({})
        return (visual.requestedName || visual.name) === selectedCollectionTitle ? visual.hero || "" : ""
    }
    readonly property url artistFallbackArtwork: {
        const first = selectedCollectionRows[0] || ({})
        return first.artwork || (first.localPath ? "image://covers/" + encodeURIComponent(first.localPath) : selectedCollectionArtwork) || ""
    }
    readonly property url backgroundArtwork: {
        const flowAlbumWindow = currentRoute === "detail/album" && !albumGridLayout && !selectedOnlineCollection
        if (currentRoute.indexOf("detail/") === 0 && !flowAlbumWindow) {
            if (currentRoute === "detail/artist" && playerController) {
                const visual = playerController.artistVisual || ({})
                if ((visual.requestedName || visual.name) === selectedCollectionTitle && visual.hero) return visual.hero
            }
            return selectedCollectionArtwork || collectionMorphArtworkSource || ""
        }
        return playerController ? playerController.currentTrack.artwork || "" : displayedTrack.artwork || ""
    }
    property string searchQuery: ""
    property string settingsSearchQuery: ""
    property string musicSearchDraft: ""
    property string pageSearchQuery: ""
    readonly property bool onlineSearchScope: currentRoute === "discover" || currentRoute === "search"
    onCurrentRouteChanged: {
        AppTheme.closePopup()
        suggestionDelay.stop()
        searchField.suggestionIndex = -1
        searchInput.focus = false
        const filters=Object.assign({},navigationFilters)
        filters[lastNavigationRoute]=pageSearchQuery
        navigationFilters=filters
        lastNavigationRoute=currentRoute
        pageSearchQuery=filters[currentRoute] || ""
        if(currentRoute.indexOf("detail/")!==0)baseRoute=currentRoute
        releaseInactiveCollectionRows()
        if (!settingsOpen) searchInput.text = currentRoute === "search" ? searchQuery : pageSearchQuery
    }
    onSettingsOpenChanged: {
        AppTheme.closePopup()
        if (settingsOpen) {
            musicSearchDraft = searchInput.text
            searchInput.text = settingsSearchQuery
        } else {
            searchInput.text = musicSearchDraft
        }
    }
    property string baseRoute: "library/songs"
    property string lastNavigationRoute: "library/songs"
    property var navigationFilters: ({})
    function filterForRoute(route) { return currentRoute===route?pageSearchQuery:navigationFilters[route] || "" }
    property string routeBeforeSearch: "library/albums"
    property string selectedCollectionTitle: "world étude"
    property string selectedCollectionSubtitle: qsTr("豊崎愛生 · 12 首歌曲")
    property color selectedCollectionTint: AppTheme.accent
    property int selectedCollectionCover: 1
    property url selectedCollectionArtwork: ""
    property var selectedCollectionRows: []
    function releaseInactiveCollectionRows() {
        if (collectionMorphClosing) return
        if (currentRoute.indexOf("detail/") !== 0 && selectedCollectionRows && selectedCollectionRows.length)
            selectedCollectionRows = []
        const usesDetail = currentRoute === "detail/playlist"
            || (currentRoute === "detail/album" && selectedOnlineCollection)
        if (!usesDetail && playlistController && typeof playlistController.releaseDetail === "function")
            playlistController.releaseDetail()
    }
    property string previousRoute: "library/albums"
    property bool selectedOnlineCollection: false
    property bool globalAlertOpen: false
    property string globalAlertTitle: qsTr("提示")
    property string globalAlertMessage: ""
    property var globalAlertOptions: []
    property string globalAlertCommand: ""
    property var globalAlertContext: ({})
    property bool musicEditorOpen: false
    property var musicEditorTrack: ({})
    property int currentQueueIndex: playerController ? playerController.currentQueueIndex : -1
    property string captureView: ""
    property string neteaseAccountName: ""
    property string bilibiliAccountName: ""
    readonly property var displayedTrack: playerController && playerController.currentTrack && playerController.currentTrack.title
                                          ? playerController.currentTrack
                                          : (catalog && catalog.songs && catalog.songs.length ? catalog.songs[0] : {})

    signal routeChanged(string route)

    readonly property int sidebarWidth: sidebarCollapsed ? 76 : 216
    readonly property int sidebarContentOffset: sidebarCollapsed ? 0 : -4
    readonly property bool canNavigateBack: settingsOpen
                                                 || currentRoute.indexOf("detail/") === 0
                                                 || currentRoute === "search"

    Behavior on queueProgress {
        enabled: shell.captureView.length === 0
        NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic }
    }

    Component.onCompleted: {
        AppTheme.darkMode = darkMode
        AppTheme.fontFamily = resolvedFontFamily(uiFontFamily)
        AppTheme.motionEnabled = animationsEnabled
        AppTheme.motionStyle = animationStyle
    }

    onNowPlayingOpenChanged: if (nowPlayingOpen && playerController) playerController.requestArtwork()
    onDarkModeChanged: AppTheme.darkMode = darkMode
    onUiFontFamilyChanged: AppTheme.fontFamily = resolvedFontFamily(uiFontFamily)
    onAnimationsEnabledChanged: AppTheme.motionEnabled = animationsEnabled
    onAnimationStyleChanged: AppTheme.motionStyle = animationStyle

    function focusSearch() { searchInput.forceActiveFocus() }
    function resolvedFontFamily(value) {
        const requested = String(value || "SystemDefault")
        if (requested === "SystemDefault")
            return Qt.application.font.family
        return requested
    }

    readonly property var platformNames: {
        const revision = shell.settingsController ? shell.settingsController.revision : 0
        return shell.settingsController && shell.settingsController.value("source.nameStyle", "Alias") === "Original"
            ? [qsTr("酷我"), qsTr("酷狗"), "QQ", qsTr("网易云"), qsTr("咪咕")] : [qsTr("小蜗"), qsTr("小枸"), qsTr("小秋"), qsTr("小芸"), qsTr("小蜜")]
    }
    property string sourceUpdateName: ""
    property string sourceUpdateLog: ""
    property url sourceUpdateUrl: ""
    property bool sourceUpdateOpen: false
    Connections {
        target: shell.sourceController
        function onUpdateAvailable(name, log, url) {
            shell.sourceUpdateName = name; shell.sourceUpdateLog = log
            shell.sourceUpdateUrl = url; shell.sourceUpdateOpen = true
        }
    }
    AlertDialog {
        objectName: "sourceUpdateDialog"
        anchors.fill: parent; z: 200
        open: shell.sourceUpdateOpen
        title: shell.sourceUpdateName + qsTr(" · 更新提示")
        message: shell.sourceUpdateLog
        primaryLabel: String(shell.sourceUpdateUrl).length ? qsTr("查看更新") : qsTr("知道了")
        secondaryLabel: qsTr("稍后")
        onRejected: shell.sourceUpdateOpen = false
        onAccepted: {
            shell.sourceUpdateOpen = false
            if (String(shell.sourceUpdateUrl).length) Qt.openUrlExternally(shell.sourceUpdateUrl)
        }
    }
    Connections {
        target: shell.playerController
        function onCurrentTrackChanged() { if (shell.nowPlayingOpen) shell.playerController.requestArtwork() }
        function onNotice(message) { shell.globalAlertTitle = "ListenFree"; shell.globalAlertMessage = message; shell.globalAlertOptions = []; shell.globalAlertCommand = ""; shell.globalAlertOpen = true }
    }
    Connections {
        target: shell.facade
        ignoreUnknownSignals: true

        function onQueueCommandRequested(command, payload) {
            if (command === "source.remove") {
                if (shell.sourceController) shell.sourceController.removeSource(String(payload))
            } else if (command === "scanLibrary") {
                if (shell.libraryController) shell.libraryController.scanDefault()
            } else if (command === "queue.append") {
                const data = JSON.parse(payload)
                for (let track of (data.tracks || [])) shell.playerController.enqueueTrack(track)
            } else if (["queue.clear", "lyrics.seek", "trackMenu"].indexOf(command) < 0) {
                shell.showUnavailable()
            }
        }
        function onAccountCookieSaveRequested(provider, cookie) { backendAccounts.login(provider, cookie) }
        function onAccountLogoutRequested(provider) { backendAccounts.logout(provider) }

        function onAccountCookieTestResult(provider, success, accountName) {
            const result = success ? String(accountName || "") : qsTr("失败")
            if (provider === "netease")
                shell.neteaseAccountName = result
            else if (provider === "bilibili")
                shell.bilibiliAccountName = result
        }
    }

    function showUnavailable() {
        globalAlertTitle = qsTr("功能尚未接入")
        globalAlertMessage = qsTr("这一阶段支持本地资料库和自定义音源混合播放。当前操作将在后续阶段接入。")
        globalAlertOptions = []
        globalAlertCommand = ""
        globalAlertOpen = true
    }

    function toggleTheme() {
        darkMode = !darkMode
        if (facade) facade.setSetting("ui.appearance", darkMode ? "dark" : "light")
        if (settingsController) {
            settingsController.setValue("ui.appearance", darkMode ? "dark" : "light")
            settingsController.setValue("appearance.mode", darkMode ? "Dark" : "Light")
        }
    }

    function activeSearchScope() {
        const chinese = uiLanguage !== "en-US"
        if (settingsOpen) return chinese ? qsTr("设置") : "Settings"
        if (currentRoute === "discover") return chinese ? qsTr("发现") : "Discover"
        if (currentRoute === "playlists") return chinese ? qsTr("歌单") : "Playlists"
        if (currentRoute === "radio") return chinese ? qsTr("电台") : "Radio"
        if (currentRoute === "library/songs") return chinese ? qsTr("歌曲") : "Songs"
        if (currentRoute === "library/albums") return chinese ? qsTr("专辑") : "Albums"
        if (currentRoute === "library/artists") return chinese ? qsTr("艺术家") : "Artists"
        if (currentRoute === "my-lists") return chinese ? qsTr("我的收藏") : "My Favorites"
        if (currentRoute.indexOf("detail/") === 0) return selectedCollectionTitle
        if (currentRoute === "search") return chinese ? qsTr("在线歌曲") : "Online Songs"
        return chinese ? qsTr("音乐") : "Music"
    }

    function searchPlaceholder() {
        return uiLanguage === "en-US"
                ? "Search in " + activeSearchScope()
                : qsTr("在") + activeSearchScope() + qsTr("中搜索")
    }

    function navigateBack() {
        if (AppTheme.currentPopup) { AppTheme.closePopup(); return }
        if (musicEditorOpen) { musicEditorOpen = false; return }
        if (queueOpen || (immersiveQueueLoader.item && immersiveQueueLoader.item.presented)) { closeQueue(); return }
        if (nowPlayingOpen) {
            if (nowPlayingLoader.item && nowPlayingLoader.item.commentsOpen) nowPlayingLoader.item.commentsOpen = false
            else closeNowPlaying()
            return
        }
        if (settingsOpen) {
            settingsOpen = false
            return
        }
        if (currentRoute.indexOf("detail/") === 0) {
            closeCollection()
            return
        }
        if (currentRoute === "search") {
            currentRoute = routeBeforeSearch || "library/albums"
            routeChanged(currentRoute)
        }
    }

    function localSearchRows() {
        if (currentRoute === "library/albums") return catalog ? catalog.albums : []
        if (currentRoute === "library/artists") return catalog ? catalog.artists : []
        if (currentRoute === "library/songs") return catalog ? catalog.songs : []
        if (currentRoute === "my-lists") return (playlistController ? playlistController.playlists : []).concat(radioController ? radioController.favorites : [])
        if (currentRoute === "playlists") return playlistController ? playlistController.onlinePlaylists : []
        if (currentRoute.indexOf("detail/") === 0) return selectedCollectionRows
        return []
    }

    function localSuggestions(text) {
        const term = String(text || "").trim().toLocaleLowerCase()
        if (!term.length) return []
        const rows = localSearchRows() || []
        const result = []
        for (let i = 0; i < rows.length && result.length < 8; ++i) {
            const title = String(rows[i].title || rows[i].name || "")
            if (title.toLocaleLowerCase().indexOf(term) >= 0 && result.indexOf(title) < 0) result.push(title)
        }
        return result
    }

    function runSearch(query) {
        if (settingsOpen) {
            settingsSearchQuery = String(query || "")
            return
        }
        const normalized = String(query || "").trim()
        searchInput.text = normalized
        if (!onlineSearchScope) {
            pageSearchQuery = normalized
            return
        }
        searchQuery = normalized
        if (onlineController) onlineController.search(normalized)
        if (currentRoute !== "search") routeBeforeSearch = currentRoute
        currentRoute = "search"
        routeChanged(currentRoute)
    }

    function requestPlayback(command) {
        if (playerController) {
            if (command === "togglePlay") {
                if (playerController.state === "Playing") playerController.pause()
                else playerController.play()
            } else if (command === "play") playerController.play()
            else if (command === "pause") playerController.pause()
            else if (command === "next") playerController.next()
            else if (command === "previous") playerController.previous()
            else if (command === "seek") { /* position is supplied by the page signal */ }
        }
        if (facade) facade.requestPlayback(command)
    }

    function playTrack(track, playbackContext) {
        if (playerController && track) {
            const behavior = settingsController
                ? settingsController.value("playback.playActionBehavior", "AppendToQueue") : "AppendToQueue"
            if (behavior === "ReplaceCurrentList" && playbackContext) {
                const rows = typeof playbackContext.playbackRows === "function"
                    ? playbackContext.playbackRows() : playbackContext
                if (rows && rows.length && playerController.replaceQueueWithList(rows, track)) return
            }
            playerController.openTrack(track)
            return
        }
        requestPlayback("playSong")
    }

    function removeQueue(index) {
        const queueView = useBackendModels && playerController ? sidebarBackendQueue : sidebarQueue
        const sidebarPosition = queueView ? queueView.contentY : 0
        if (useBackendModels && playerController) {
            playerController.removeFromQueue(index)
            Qt.callLater(function() {
                if (!queueView) return
                queueView.forceLayout()
                queueView.contentY = Math.max(0, Math.min(sidebarPosition,
                                                         queueView.contentHeight - queueView.height))
            })
            return
        }
        if (index < 0 || index >= queueSongs.length) return
        const next = queueSongs.slice()
        next.splice(index, 1)
        queueSongs = next
        Qt.callLater(function() {
            if (!queueView) return
            queueView.forceLayout()
            queueView.contentY = Math.max(0, Math.min(sidebarPosition,
                                                     queueView.contentHeight - queueView.height))
        })
    }

    function openQueue(fromNowPlaying) {
        AppTheme.closePopup()
        queueFromNowPlaying = !!fromNowPlaying
        queueFromImmersive = !!fromNowPlaying && !!nowPlayingLoader.item && nowPlayingLoader.item.immersiveActive
        queueFromOverflow = !!fromNowPlaying && nowPlayingLoader.item && nowPlayingLoader.item.overflowStyle && !nowPlayingLoader.item.immersiveActive
        queueOpen = true
    }

    function closeQueue() {
        queueOpen = false
    }

    function clearQueue() {
        if (playerController) { playerController.clearQueue(); return }
        if (!useBackendModels)
            queueSongs = []
        if (facade)
            facade.requestQueue("queue.clear", "all")
    }

    function moveQueue(from, to) {
        if (useBackendModels && playerController) {
            playerController.moveQueue(from, to)
            return
        }
        if (from === to || from < 0 || to < 0 || from >= queueSongs.length || to >= queueSongs.length) return
        const next = queueSongs.slice()
        const item = next.splice(from, 1)[0]
        next.splice(to, 0, item)
        queueSongs = next
    }

    function activateQueue(index, track) {
        if (useBackendModels && playerController) {
            playerController.selectQueue(index, true)
            return
        }
        playTrack(track)
    }

    function openCollection(kind, title, tint) { openCollectionDetail(kind, title, tint, null) }
    function openOnlineCollection(collection) {
        openCollectionDetail(collection.kind === "album" ? "Album" : "Playlist", collection.title, collection.color || "#80868d", collection)
    }
    function openCollectionDetail(kind, title, tint, onlineCollection) {
        if (kind === "Artist" && playerController) playerController.requestArtistVisual(title)
        selectedOnlineCollection = !!onlineCollection
        if (selectedOnlineCollection && playlistController) playlistController.open(onlineCollection)
        else if (kind === "Playlist" && playlistController) playlistController.openTitle(title)
        if (!collectionMorphActive)
            collectionMorphAvailable = false
        previousRoute = currentRoute
        selectedCollectionTitle = title
        collectionMorphKind = kind
        const playlistDetail = (kind === "Playlist" || selectedOnlineCollection) && playlistController ? playlistController.detail : null
        selectedCollectionRows = playlistDetail ? (playlistDetail.tracks || []) : (catalog.songs || []).filter(function(row) {
            return kind === "Artist" ? (row.artist || qsTr("未知艺术家")) === title : (row.album || qsTr("未知专辑")) === title
        })
        const firstTrack = selectedCollectionRows.length ? selectedCollectionRows[0] : ({})
        selectedCollectionSubtitle = playlistDetail ? (playlistController.detailBusy ? qsTr("正在加载歌单…") : selectedCollectionRows.length + qsTr(" 首歌曲"))
            : (kind === "Artist" ? qsTr("艺术家") : (firstTrack.artist || qsTr("未知艺术家"))) + " · " + selectedCollectionRows.length + qsTr(" 首歌曲")
        selectedCollectionArtwork = (playlistDetail && playlistDetail.artwork) || firstTrack.artwork || (collectionMorphActive ? collectionMorphArtworkSource : "")
        selectedCollectionTint = tint
        let coverIndex = 1
        if (kind === "Album" && catalog && catalog.albums) {
            for (let i = 0; i < catalog.albums.length; ++i) {
                if (catalog.albums[i].title === title) { coverIndex = (i % 7) + 1; break }
            }
        }
        if (kind === "Playlist" && !playlistDetail && catalog && catalog.onlinePlaylists) {
            for (let j = 0; j < catalog.onlinePlaylists.length; ++j) {
                if (catalog.onlinePlaylists[j].title === title) { coverIndex = catalog.onlinePlaylists[j].cover; break }
            }
        }
        selectedCollectionCover = coverIndex
        currentRoute = "detail/" + (kind === "Artist" ? "artist" : kind === "Playlist" ? "playlist" : "album")
        routeChanged(currentRoute)
    }

    Connections {
        target: shell.playlistController
        function onDetailChanged() {
            if (shell.currentRoute !== "detail/playlist" && !(shell.currentRoute === "detail/album" && shell.selectedOnlineCollection)) return
            const d = shell.playlistController.detail
            shell.selectedCollectionRows = d.tracks || []
            shell.selectedCollectionTitle = d.title || qsTr("歌单")
            shell.selectedCollectionArtwork = d.artwork || ((d.tracks || [])[0] || {}).artwork || ""
            shell.selectedCollectionSubtitle = shell.playlistController.detailBusy ? qsTr("正在加载 · ") + shell.selectedCollectionRows.length + qsTr(" 首") : (d.error || shell.selectedCollectionRows.length + qsTr(" 首歌曲"))
        }
        function onNotice(message) { shell.globalAlertTitle = qsTr("歌单"); shell.globalAlertMessage = message; shell.globalAlertOpen = true }
    }

    function prepareCollectionMorph(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem) {
        collectionMorphKind = kind
        collectionMorphTint = tint
        collectionMorphArtworkSource = artworkSource
        collectionMorphSourceItem = collectionMorphUsesGrid ? (artworkItem || null) : null
        if (collectionMorphSourceItem) collectionMorphSnapshot.scheduleUpdate()
        collectionMorphSourceFrame = Qt.rect(contentLoader.x + frameRect.x,
                                             contentLoader.y + frameRect.y,
                                             frameRect.width, frameRect.height)
        collectionMorphSourceArtwork = Qt.rect(contentLoader.x + artworkRect.x,
                                               contentLoader.y + artworkRect.y,
                                               artworkRect.width, artworkRect.height)
        collectionMorphProgress = 0
        collectionMorphClosing = false
        collectionMorphAvailable = true
        collectionMorphActive = true
        collectionMorphAnimation.from = 0
        collectionMorphAnimation.to = 1
        Qt.callLater(startPreparedCollectionMorph)
    }

    function startPreparedCollectionMorph() {
        if (!collectionMorphActive || collectionMorphClosing || collectionMorphAnimation.running) return
        if (collectionMorphProgress >= 1) {
            if (detailLoader.status === Loader.Ready) collectionMorphActive = false
        } else if (collectionMorphUsesGrid || detailLoader.status === Loader.Ready) {
            // The playlist hero geometry is fixed, so its existing texture can
            // start moving immediately while the detail page incubates.
            collectionMorphAnimation.restart()
        }
    }

    function closeCollection() {
        if (collectionMorphActive || currentRoute.indexOf("detail/") !== 0)
            return
        if (!collectionMorphAvailable) {
            currentRoute = previousRoute || "library/albums"
            routeChanged(currentRoute)
            return
        }
        collectionMorphClosing = true
        collectionMorphProgress = 1
        collectionMorphActive = true
        collectionMorphAnimation.from = 1
        collectionMorphAnimation.to = 0
        Qt.callLater(function() { collectionMorphAnimation.restart() })
    }

    function openNowPlaying() {
        if (nowPlayingOpen && !morphClosing) return
        transitionNowPlaying(true)
    }

    Connections {
        target: shell.playerController
        ignoreUnknownSignals: true
        function onTrackMetadataChanged(track) {
            if (shell.currentRoute.indexOf("detail/") !== 0 || !shell.selectedCollectionRows.length) return
            const previous = shell.selectedCollectionRows.find(row => row.localPath && row.localPath.toLowerCase() === String(track.localPath).toLowerCase())
            if (previous && String(shell.selectedCollectionArtwork) === String(previous.artwork)) {
                shell.selectedCollectionArtwork = track.artwork || ""
                shell.collectionMorphArtworkSource = track.artwork || ""
            }
            shell.selectedCollectionRows=shell.selectedCollectionRows.map(row => row.localPath && row.localPath.toLowerCase()===String(track.localPath).toLowerCase()?Object.assign({},row,track):row)
        }
        function onCatalogChanged() {
            if(shell.currentRoute!=="detail/album" && shell.currentRoute!=="detail/artist")return
            if(shell.selectedOnlineCollection)return
            const artist=shell.currentRoute==="detail/artist"
            shell.selectedCollectionRows=(shell.catalog.songs || []).filter(row =>
                (artist ? (row.artist || qsTr("未知艺术家")) : (row.album || qsTr("未知专辑")))===shell.selectedCollectionTitle)
            const first=shell.selectedCollectionRows[0] || ({})
            shell.selectedCollectionSubtitle=(artist ? qsTr("艺术家") : (first.artist || qsTr("未知艺术家")))+" · "+shell.selectedCollectionRows.length+qsTr(" 首歌曲")
            shell.selectedCollectionArtwork=first.artwork || ""
        }
    }

    function openMusicEditor(track) {
        musicEditorTrack = playerController ? playerController.readTrackTags(track || displayedTrack) : (track || displayedTrack)
        musicEditorOpen = true
    }

    function requestTrackSort(column, order) {
        if (playerController) { playerController.sortTracks(column, order); return }
        if (facade)
            facade.requestQueue("library.sort", column + ":" + order)
    }

    function handleTrackCommand(command, track, rowIndex, playbackContext) {
        const payload = JSON.stringify({ track: track || {}, rowIndex: rowIndex })
        if (command === "play_now") {
            playTrack(track, playbackContext)
        } else if (command === "play_next" || command === "add_to_queue" || command === "add_queue") {
            if (playerController) playerController.enqueueTrack(track, command === "play_next")
        } else if (command === "download") {
            chooseDownload([track])
        } else if (command === "favorite") {
            if (track && track.radioId && radioController) radioController.toggleFavorite(track)
            else if (playlistController) playlistController.toggleTrackLiked(track)
        } else if (command === "add_to_playlist") {
            pendingPlaylistTracks = [track]; addPlaylistCreateOnly = false; addPlaylistOpen = true
        } else if (command === "show_in_explorer") {
            if (playerController) playerController.showInExplorer(track)
        } else if (command === "remove_from_library") {
            if (playerController) playerController.removeLibraryTrack(track, false)
        } else if (command === "edit_tags") {
            openMusicEditor(track)
        } else if (command === "delete_from_disk") {
            globalAlertTitle = qsTr("从磁盘删除歌曲")
            globalAlertMessage = qsTr("这会把对应音频文件移入 Windows 回收站。此操作不会直接永久擦除文件，但仍建议先确认歌曲与路径。")
            globalAlertOptions = []
            globalAlertCommand = command
            globalAlertContext = ({ payload: payload })
            globalAlertOpen = true
        } else if (facade) {
            facade.requestQueue("track." + command, payload)
        }
    }

    function openDuplicateAlert() {
        backendDuplicates.analyze()
        duplicateDialog.open = backendDuplicates.busy
    }

    Connections {
        target: typeof backendAccounts !== "undefined" ? backendAccounts : null
        function onAccountsChanged() {
            shell.neteaseAccountName = (backendAccounts.accounts.netease || {}).name || ""
            shell.bilibiliAccountName = (backendAccounts.accounts.bilibili || {}).name || ""
        }
    }
    AlertDialog {
        id: duplicateDialog; anchors.fill: parent; z: 280
        title: qsTr("重复歌曲分析")
        message: backendDuplicates.busy ? qsTr("正在处理，请稍候…") : qsTr("完整内容一致的文件才会列入结果。删除操作将重复文件移入回收站。")
        primaryLabel: backendDuplicates.busy ? qsTr("取消处理") : backendDuplicates.groups.length ? qsTr("合并") : qsTr("完成")
        options: !backendDuplicates.busy && backendDuplicates.groups.length ? [qsTr("仅合并索引，保留文件"), qsTr("移入回收站并合并")] : []
        contentComponent: Component {
            Flickable {
                width: parent ? parent.width : 412; height: 200
                clip: true; contentHeight: duplicateReport.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Text { id: duplicateReport; width: parent.width; text: backendDuplicates.report; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: AppTheme.textSecondary; font.pixelSize: 12 }
            }
        }
        onRejected: { backendDuplicates.cancel(); open=false }
        onAccepted: {
            if(backendDuplicates.busy){backendDuplicates.cancel();return}
            if(backendDuplicates.groups.length)backendDuplicates.merge(selectedOption===1)
            else open=false
        }
    }

    function closeNowPlaying() {
        if (nowPlayingLoader.item && nowPlayingLoader.item.immersiveActive) { nowPlayingLoader.item.immersiveActive = false; return }
        if (!nowPlayingOpen || morphClosing) return
        transitionNowPlaying(false)
    }

    function transitionNowPlaying(opening) {
        morphAnimation.stop()
        coverMorphAnimation.stop()
        nowPlayingOpen = true
        morphClosing = !opening
        morphAnimating = true
        morphAnimation.from = morphProgress
        morphAnimation.to = opening ? 1 : 0
        coverMorphAnimation.from = coverMorphProgress
        coverMorphAnimation.to = opening ? 1 : 0
        coverMorphAnimation.start()
        morphAnimation.start()
    }

    function mix(a, b, t) { return a + (b - a) * t }

    Rectangle {
        id: appSurface
        enabled: !equalizerPopup.visible && !lyricsMatchPopup.visible && !(AppTheme.currentPopup && ["backgroundColorPicker", "backgroundWallpaperPicker", "playlistSharePopup"].indexOf(AppTheme.currentPopup.objectName) >= 0)
        anchors.fill: parent
        radius: shell.hostWindow ? shell.hostWindow.cornerRadius : AppTheme.windowCornerRadius
        clip: true
        color: "transparent"
        border.width: 1 / Screen.devicePixelRatio
        border.pixelAligned: false
        border.color: "#18ffffff"

        // Capture page content only. The floating player must never sample itself.
        Item {
            id: libraryBackdrop
            objectName: "libraryBackdrop"
            anchors.fill: parent
        Item {
            id: desktopBackground
            objectName: "desktopBackground"
            anchors.fill: parent
            // Compose the glass sample and tint before applying desktop alpha.
            // Otherwise the glass re-samples an opaque source over the alpha layer.
            layer.enabled: shell.desktopTransparencyActive && !shell.artworkCanvasActive
            layer.effect: ShaderEffect {
                property var source
                property real sidebarFraction: shell.sidebarWidth / Math.max(1,shell.width)
                fragmentShader: "qrc:/shaders/window-transparency.frag.qsb"
            }
        GlobalBackground {
            id: globalBackground
            visible: !shell.artworkCanvasActive
            objectName: "globalBackground"
            anchors.fill: parent
            artwork: shell.backgroundArtwork
            settingsStore: shell.settingsController
            playing: false
        }
        Loader {
            id: artistCanvasLoader
            anchors.fill: parent
            active: shell.artistCanvasActive
            sourceComponent: ArtistBackdrop {
                objectName: "artistBackdrop"
                artistKey: shell.selectedCollectionTitle
                artwork: shell.artistHeroSource
                fallbackArtwork: shell.artistFallbackArtwork
                sidebarWidth: shell.sidebarWidth
                heroHeight: detailLoader.item ? detailLoader.item.artistExpandedHeight : height*.76
                scrollOffset: detailLoader.item ? detailLoader.item.artistScrollOffset : 0
                collapse: detailLoader.item ? detailLoader.item.artistCollapse : 0
            }
        }

        Loader {
            id: mosaicCanvasLoader
            anchors.fill: parent
            active: shell.mosaicCanvasActive
            sourceComponent: AlbumMosaicPage {
                catalog: shell.catalog
                sidebarWidth: shell.sidebarWidth
                darkMode: shell.darkMode
                filterText: shell.filterForRoute("library/albums")
                enabled: !shell.nowPlayingOpen
                Component.onCompleted: { const position=shell.mosaicPosition; panX=position.x; panY=position.y }
                onPanXChanged: shell.mosaicPosition=Qt.point(panX,panY)
                onPanYChanged: shell.mosaicPosition=Qt.point(panX,panY)
                onTrackActivated: (track, playbackContext) => shell.playTrack(track, playbackContext)
                onTrackCommandRequested: (command,track,rowIndex,playbackContext) => shell.handleTrackCommand(command,track,rowIndex,playbackContext)
                onPlayAllRequested: tracks => { if (shell.playerController) shell.playerController.playAll(tracks) }
            }
        }

        GlassSurface {
            objectName: "sidebarFrost"
            anchors.fill: sidebarSurface
            visible: !shell.nowPlayingOpen
            backdrop: shell.mosaicCanvasActive ? mosaicCanvasLoader.item : shell.artistCanvasActive ? artistCanvasLoader.item : globalBackground
            backdropBlur: 12
            cornerRadius: 0; opaqueBackdropBase: false
            tint: "transparent"; edgeColor: "transparent"; shadowOpacity: 0
        }
        Rectangle {
            id: sidebarSurface
            objectName: "sidebarSurface"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: shell.sidebarWidth
            topLeftRadius: 12
            bottomLeftRadius: 12
            // This tint composites over our artwork, independently of whether
            // the native window is allowed to reveal the desktop behind it.
            color: shell.mosaicCanvasActive ? (shell.darkMode ? "#b5101620" : "#9a202936") : shell.artistCanvasActive ? "transparent" : AppTheme.sidebarSurface
            Behavior on width { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
        }
        }

        Column {
            id: sidebar
            enabled: !shell.nowPlayingOpen
            x: 12
            y: (AppTheme.toolbarHeight - AppTheme.toolbarControlHeight) / 2
            width: shell.sidebarWidth - 24
            spacing: 6
            Behavior on width { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }

            Item {
                id: brand
                width: parent.width
                height: AppTheme.toolbarControlHeight
                clip: true
                IconGlyph {
                    objectName: "sidebarToggleGlyph"
                    x: shell.sidebarCollapsed ? (parent.width - width) / 2 : 14 + shell.sidebarContentOffset
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22
                    kind: "sidebar"
                    glyphColor: AppTheme.sidebarText
                }
                Image {
                    x: 47 + shell.sidebarContentOffset
                    anchors.verticalCenter: parent.verticalCenter
                    source: Qt.resolvedUrl(AppTheme.canvasDark
                                           ? "assets/freeListen_wordmark.svg"
                                           : "assets/freeListen_wordmark_dark.svg")
                    width: 126
                    height: AppTheme.toolbarControlHeight
                    opacity: shell.sidebarCollapsed ? 0 : 1
                    visible: !shell.sidebarCollapsed
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    Behavior on opacity { NumberAnimation { duration: AppTheme.duration(150); easing.type: Easing.OutCubic } }
                }
                HoverHandler { id: brandHover }
                MouseArea { objectName: "sidebarToggle"; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: shell.sidebarCollapsed = !shell.sidebarCollapsed }
            }

            Item { width: 1; height: 12 }
            SidebarButton { label: qsTr("发现"); iconKind: "navDiscover"; route: "discover" }
            SidebarButton { label: qsTr("歌单"); iconKind: "navPlaylists"; route: "playlists" }
            SidebarButton { label: qsTr("电台"); iconKind: "radio"; route: "radio" }
            SidebarButton { label: qsTr("歌曲"); iconKind: "navSongs"; route: "library/songs" }
            SidebarButton { label: qsTr("专辑"); iconKind: "navAlbums"; route: "library/albums" }
            SidebarButton { label: qsTr("艺术家"); iconKind: "navArtists"; route: "library/artists" }
            SidebarButton { label: qsTr("我的收藏"); iconKind: "heart"; route: "my-lists" }
            Item { width: 1; height: 8 }
            SectionLabel { text: "List" }
            component SidebarQueueRow: Rectangle {
                id: queueDelegate
                required property int rowIndex
                required property var trackData
                required property ListView ownerList
                objectName: "sidebarQueueRow" + rowIndex
                width: ownerList.width
                x: 0
                height: 52
                radius: 12
                color: rowIndex === shell.currentQueueIndex
                       ? AppTheme.sidebarSelected
                       : queueRowHover.hovered ? AppTheme.sidebarHover : "transparent"
                border.width: rowIndex === shell.currentQueueIndex ? 1 / Screen.devicePixelRatio : 0
                border.pixelAligned: false
                border.color: shell.darkMode ? "#24ffffff" : "#50ffffff"
                Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }
                CoverArt {
                    x: shell.sidebarCollapsed ? (queueDelegate.width - width) / 2 : 8 + shell.sidebarContentOffset
                    Behavior on x { NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: width
                    sourcePixelSize: 128
                    cornerRadius: 9
                    showShadow: false
                    source: queueDelegate.trackData.artwork && queueDelegate.trackData.artwork.length
                            ? queueDelegate.trackData.artwork : ""
                }
                Column {
                    x: 56 + shell.sidebarContentOffset
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - 92)
                    spacing: 1
                    opacity: shell.sidebarCollapsed ? 0 : 1
                    visible: opacity > 0.001
                    Behavior on opacity { NumberAnimation { duration: AppTheme.duration(140) } }
                    Text { width: parent.width; text: queueDelegate.trackData.title; elide: Text.ElideRight; color: AppTheme.sidebarText; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { width: parent.width; text: queueDelegate.trackData.artist; elide: Text.ElideRight; color: AppTheme.sidebarSecondary; font.pixelSize: 10 }
                }
                HoverHandler { id: queueRowHover }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton) shell.removeQueue(queueDelegate.rowIndex)
                        else shell.activateQueue(queueDelegate.rowIndex, queueDelegate.trackData)
                    }
                }
                DragHandler {
                    id: queueDrag
                    target: null
                    xAxis.enabled: false
                    property real dragOffset: 0
                    onActiveTranslationChanged: if (active) dragOffset = activeTranslation.y
                    onActiveChanged: if (!active) {
                        const offset = dragOffset
                        dragOffset = 0
                        if (Math.abs(offset) < 8) return
                        const target = Math.max(0, Math.min(queueDelegate.ownerList.count - 1,
                                                          Math.floor((queueDelegate.y + offset + queueDelegate.height / 2) / (queueDelegate.height + queueDelegate.ownerList.spacing))))
                        if (target !== queueDelegate.rowIndex) shell.moveQueue(queueDelegate.rowIndex, target)
                    }
                }
                transform: Translate { y: queueDrag.active ? queueDrag.dragOffset : 0 }
                RoundIconButton {
                    objectName: "sidebarQueueRemove" + queueDelegate.rowIndex
                    anchors.right: parent.right
                    anchors.rightMargin: 4 - shell.sidebarContentOffset
                    anchors.verticalCenter: parent.verticalCenter
                    diameter: 26
                    kind: "close"
                    glyphColor: AppTheme.sidebarSecondary
                    transparentSurface: true
                    visible: !shell.sidebarCollapsed
                    opacity: queueRowHover.hovered ? 1 : 0
                    enabled: opacity > 0.1
                    Behavior on opacity { NumberAnimation { duration: AppTheme.duration(110) } }
                    onClicked: shell.removeQueue(queueDelegate.rowIndex)
                }
            }
            ListView {
                id: sidebarQueue
                objectName: shell.useBackendModels && shell.playerController ? "" : "sidebarQueue"
                visible: !(shell.useBackendModels && shell.playerController)
                width: parent.width
                height: Math.max(0, shell.height - sidebar.y - y - 12)
                bottomMargin: floatingPlayer.visible ? floatingPlayer.height + 18 : 0
                spacing: 6
                clip: true
                interactive: contentHeight + bottomMargin > height
                boundsBehavior: Flickable.StopAtBounds
                model: visible ? shell.queueSongs : []
                delegate: SidebarQueueRow {
                    required property int index
                    required property var modelData
                    rowIndex: index
                    trackData: modelData
                    ownerList: sidebarQueue
                }
            }
            ListView {
                id: sidebarBackendQueue
                objectName: shell.useBackendModels && shell.playerController ? "sidebarQueue" : ""
                visible: shell.useBackendModels && !!shell.playerController
                width: parent.width
                height: Math.max(0, shell.height - sidebar.y - y - 12)
                bottomMargin: floatingPlayer.visible ? floatingPlayer.height + 18 : 0
                spacing: 6
                clip: true
                interactive: contentHeight + bottomMargin > height
                boundsBehavior: Flickable.StopAtBounds
                model: visible ? shell.playerController.queueModel : null
                delegate: SidebarQueueRow {
                    required property int index
                    required property string title
                    required property string artist
                    required property string artwork
                    rowIndex: index
                    trackData: ({ title: title, artist: artist, artwork: artwork })
                    ownerList: sidebarBackendQueue
                }
            }
        }

        Rectangle {
            id: topBar
            enabled: !shell.nowPlayingOpen
            z: 20
            clip: false
            x: shell.sidebarWidth
            y: 0
            width: parent.width - shell.sidebarWidth
            height: AppTheme.toolbarHeight
            Behavior on x { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
            Behavior on width { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: "transparent" }
            }
            MouseArea {
                anchors.fill: parent
                anchors.rightMargin: 205
                acceptedButtons: Qt.LeftButton
                onPressed: if (shell.hostWindow && shell.hostWindow.startSystemMove) shell.hostWindow.startSystemMove()
            }

            RoundIconButton {
                id: backButton
                objectName: "globalBackButton"
                x: 20; anchors.verticalCenter: parent.verticalCenter
                diameter: 32; kind: "chevronDown"; glyphRotation: 90
                transparentSurface: true; darkMode: AppTheme.canvasDark
                hoverColor: shell.artworkCanvasActive ? "#40808080" : AppTheme.actionHover
                pressedColor: shell.artworkCanvasActive ? "#60808080" : AppTheme.actionPressed
                glyphColor: AppTheme.canvasText
                visible: shell.canNavigateBack
                onClicked: shell.navigateBack()
            }


            Text {
                objectName: "topBarCurrentLyric"
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 2 * Math.max(72 + searchField.width, 230))
                readonly property var lyricRows: shell.playerController ? shell.playerController.lyrics : []
                text: {
                    if (!shell.playerController || ["Playing", "Paused", "Buffering"].indexOf(shell.playerController.state) < 0) return ""
                    const index = shell.playerController.currentLyricIndex
                    return index >= 0 && index < lyricRows.length ? String(lyricRows[index].text || "") : ""
                }
                visible: !shell.mosaicCanvasActive && width > 0 && text.length > 0
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: AppTheme.canvasSecondary; opacity: .9
                font.family: AppTheme.fontFamily; font.pixelSize: 13
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: AppTheme.normalWindowCornerRadius - closeWindowControl.width / 2 - 4
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                TopGlyph { objectName: "topDownloadButton"; selected: shell.downloadsOpen; kind: "download"; visible: { const r = shell.settingsController ? shell.settingsController.revision : 0; return shell.settingsController ? shell.settingsController.value("download.enabled", true) : false } onClicked: shell.downloadsOpen = !shell.downloadsOpen }
                TopGlyph { objectName: "topThemeButton"; kind: shell.darkMode ? "moon" : "sun"; onClicked: shell.toggleTheme() }
                TopGlyph { objectName: "topSettingsButton"; selected: shell.settingsOpen; kind: "gear"; onClicked: shell.settingsOpen = !shell.settingsOpen }
                Row {
                    id: topTrafficCluster
                    objectName: "topTrafficCluster"
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    WindowTrafficButton {
                        action: "minimize"
                        fillColor: "#2fc866"
                        revealGlyph: topTrafficHover.hovered
                                     || shell.captureView === "traffic-hover"
                                     || Qt.application.arguments.indexOf("traffic-hover") >= 0
                        reducedMotion: !shell.animationsEnabled
                        onClicked: if (shell.hostWindow) shell.hostWindow.showMinimized()
                    }
                    WindowTrafficButton {
                        action: "maximize"
                        fillColor: "#ffbf18"
                        revealGlyph: topTrafficHover.hovered
                                     || shell.captureView === "traffic-hover"
                                     || Qt.application.arguments.indexOf("traffic-hover") >= 0
                        reducedMotion: !shell.animationsEnabled
                        onClicked: if (shell.hostWindow) {
                            if (shell.hostWindow.visibility === Window.Maximized) shell.hostWindow.showNormal()
                            else shell.hostWindow.showMaximized()
                        }
                    }
                    WindowTrafficButton {
                        id: closeWindowControl
                        action: "close"
                        fillColor: "#ff5f57"
                        revealGlyph: topTrafficHover.hovered
                                     || shell.captureView === "traffic-hover"
                                     || Qt.application.arguments.indexOf("traffic-hover") >= 0
                        reducedMotion: !shell.animationsEnabled
                        onClicked: if (shell.hostWindow) shell.hostWindow.close()
                    }
                    HoverHandler { id: topTrafficHover }
                }
            }
        }

            Item {
                id: searchField
                x: topBar.x + 60; y: (AppTheme.toolbarHeight - AppTheme.toolbarControlHeight) / 2
                width: searchInput.activeFocus ? 244 : 210
                height: searchCapsule.height; z: 21
                property int suggestionIndex: -1
                readonly property var suggestions: shell.settingsOpen ? [] : shell.onlineSearchScope
                    ? (shell.onlineController ? shell.onlineController.suggestions || [] : [])
                    : shell.localSuggestions(searchInput.text)
                readonly property bool expanded: searchInput.activeFocus && !shell.settingsOpen && searchInput.text.trim().length > 0 && suggestions.length > 0
                function submit() {
                    const value = suggestionIndex >= 0 && expanded ? suggestions[suggestionIndex] : searchInput.text
                    shell.runSearch(value); searchInput.focus = false
                }
                Behavior on width { NumberAnimation { duration: AppTheme.duration(320); easing.type: Easing.OutCubic } }
                Timer { id: suggestionDelay; interval: 180; onTriggered: {
                    searchField.suggestionIndex = -1
                    if(shell.onlineController && shell.onlineSearchScope && !shell.settingsOpen && searchInput.activeFocus) shell.onlineController.suggest(searchInput.text)
                } }
                Rectangle {
                    id: searchCapsule
                    objectName: "searchSuggestionCapsule"
                    width: searchField.width
                    height: searchField.expanded ? 40 + Math.min(8,searchField.suggestions.length)*36 : AppTheme.toolbarControlHeight
                    radius: 10; clip: true
                    color: searchInput.activeFocus ? "#ffffff" : shell.artworkCanvasActive ? "transparent" : searchField.expanded ? AppTheme.floatingSurface : AppTheme.actionSurface
                    border.width: searchInput.activeFocus ? 1 : 0
                    border.color: AppTheme.actionBorder
                    Behavior on width { NumberAnimation { duration: AppTheme.duration(320); easing.type: Easing.OutCubic } }
                    Behavior on height { enabled: shell.animationsEnabled; SpringAnimation { spring: 3.2; damping: .78; epsilon: .1 } }
                    Loader {
                        anchors.fill: parent
                        active: shell.artworkCanvasActive && !searchInput.activeFocus
                        sourceComponent: GlassSurface {
                            // Sample only the artist canvas, excluding this field
                            // and the toolbar to avoid recursive self-sampling.
                            backdrop: shell.mosaicCanvasActive ? mosaicCanvasLoader.item : artistCanvasLoader.item
                            opaqueBackdropBase: false
                            frosted: true
                            cornerRadius: searchCapsule.radius
                            backdropBlur: 24
                            tint: AppTheme.canvasDark ? "#20262b" : "#e8ecef"
                            tintStrength: .22
                            exclusionStrength: .03
                            noiseStrength: .004
                            shadowOpacity: 0
                        }
                    }
                    MouseArea { x: 0; y: 0; width: AppTheme.toolbarControlHeight; height: AppTheme.toolbarControlHeight; onClicked: searchField.submit()
                        IconGlyph { objectName: "integratedSearchIcon"; anchors.centerIn: parent; width: 14; height: 14; kind: "search"; glyphColor: searchInput.activeFocus ? "#20262b" : AppTheme.canvasText }
                    }
                    // The expanded field owns wheel/hit tests beneath the header.
                    MouseArea { anchors.fill: parent; z: -1; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
                    TextInput {
                        id: searchInput
                        objectName: "globalSearchInput"
                        x: 33
                        y: 0; width: searchCapsule.width-x-12; height: AppTheme.toolbarControlHeight
                        verticalAlignment: Text.AlignVCenter
                        color: activeFocus ? "#000000" : AppTheme.canvasText; font.family: AppTheme.fontFamily; font.pixelSize: 12; clip: true
                        selectionColor: "#c3dbff"; selectedTextColor: "#000000"
                        Text { anchors.verticalCenter: parent.verticalCenter; text: shell.searchPlaceholder(); color: searchInput.activeFocus ? "#646b73" : AppTheme.canvasSecondary; visible: !searchInput.text.length; font.pixelSize: 12 }
                        onTextChanged: { searchField.suggestionIndex=-1; if(shell.settingsOpen)shell.settingsSearchQuery=text;else { if(!shell.onlineSearchScope)shell.pageSearchQuery=text.trim(); suggestionDelay.restart() } }
                        onActiveFocusChanged: { if(activeFocus)suggestionDelay.restart();else {suggestionDelay.stop();searchField.suggestionIndex=-1} }
                        Keys.onDownPressed: if(searchField.expanded)searchField.suggestionIndex=Math.min(searchField.suggestions.length-1,searchField.suggestionIndex+1)
                        Keys.onUpPressed: if(searchField.expanded)searchField.suggestionIndex=Math.max(0,searchField.suggestionIndex-1)
                        Keys.onEscapePressed: searchInput.focus=false
                        Keys.onEnterPressed: searchField.submit()
                        Keys.onReturnPressed: searchField.submit()
                    }
                    Column {
                        x: 6; y: 36; width: parent.width-12
                        opacity: searchField.expanded ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: AppTheme.duration(140) } }
                        Repeater {
                            model: searchField.suggestions
                            delegate: Rectangle {
                                id: suggestionRow
                                objectName: "searchSuggestionRow" + index
                                required property int index
                                required property string modelData
                                width: searchCapsule.width-12; height: 36; radius: 10
                                color: suggestionHover.hovered || searchField.suggestionIndex===index ? "#edf1f5" : "transparent"
                                Text { x: 9; anchors.verticalCenter: parent.verticalCenter; width: parent.width-18; text: suggestionRow.modelData; elide: Text.ElideRight; color: "#20262b"; font.family: AppTheme.fontFamily; font.pixelSize: 12 }
                                HoverHandler { id: suggestionHover }
                                MouseArea { anchors.fill: parent; onClicked: {shell.runSearch(suggestionRow.modelData);searchInput.focus=false} }
                            }
                        }
                    }
                }

            }


        Item {
            id: contentLoader
            enabled: !shell.nowPlayingOpen
            x: shell.sidebarWidth
            y: shell.artistCanvasActive ? 0 : AppTheme.toolbarHeight
            width: parent.width - shell.sidebarWidth
            height: parent.height - y
            Behavior on x { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
            Behavior on width { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
            z: 1
            NavigationCache {
                id: navigationCache
                objectName: "navigationStateCache"
                anchors.fill: parent
                route: shell.baseRoute
                transitionSourceItem: shell.collectionMorphActive ? shell.collectionMorphSourceItem : null
                enabled: !shell.settingsOpen && !shell.mosaicCanvasActive && shell.currentRoute.indexOf("detail/")!==0
                visible: !shell.settingsOpen && !shell.mosaicCanvasActive
                // Hand off the text layers before the incoming list fades in.
                // The independent cover remains visible throughout the flight.
                opacity: shell.currentRoute === "detail/artist" ? 0 : shell.currentRoute === "detail/playlist" || (shell.currentRoute === "detail/album" && (shell.selectedOnlineCollection || shell.albumGridLayout))
                         ? (shell.collectionMorphActive ? Math.max(0,1-shell.collectionMorphProgress/.25) : 0) : 1
                pages: [
                    {route:"library/songs",component:libraryComponent},
                    {route:"library/albums",component:libraryComponent},
                    {route:"library/artists",component:libraryComponent},
                    {route:"my-lists",component:myListsComponent},
                    {route:"discover",component:discoverComponent},
                    {route:"playlists",component:playlistComponent},
                    {route:"radio",component:radioComponent},
                    {route:"search",component:searchComponent}
                ]
            }
            Loader {
                id: detailLoader
                anchors.fill: parent; z: 2
                active: shell.currentRoute.indexOf("detail/")===0
                // Artist content must appear even when no image/animation is
                // producing frames to advance asynchronous incubation.
                asynchronous: shell.currentRoute !== "detail/artist"
                visible: active && !shell.settingsOpen
                sourceComponent: collectionComponent
                opacity: shell.collectionMorphActive ? Math.max(0, (shell.collectionMorphProgress-.25)/.75) : 1
                enabled: !shell.collectionMorphActive
                onLoaded: Qt.callLater(shell.startPreparedCollectionMorph)
            }
            Loader {
                anchors.fill: parent; z: 3
                active: shell.settingsOpen
                sourceComponent: settingsComponent
            }
        }

        }

        GlassSurface {
            id: playerMorphSurface
            objectName: "playerMorphSurface"
            z: 39
            visible: shell.morphAnimating
            x: shell.mix(floatingPlayer.x, 0, shell.morphProgress)
            y: shell.mix(floatingPlayer.y, 0, shell.morphProgress)
            width: shell.mix(floatingPlayer.width, appSurface.width, shell.morphProgress)
            height: shell.mix(floatingPlayer.height, appSurface.height, shell.morphProgress)
            cornerRadius: shell.mix(floatingPlayer.cornerRadius, appSurface.radius, shell.morphProgress)
            backdrop: floatingPlayer.backdrop
            opaqueBackdropBase: false; frosted: true; backdropBlur: floatingPlayer.glassBlur
            tint: floatingPlayer.glassTint
            tintStrength: floatingPlayer.glassTintStrength; shadowOpacity: .08
            opacity: 1 - Math.max(0, (shell.morphProgress - .45) / .55)
        }
        Item {
            id: playerMorphMask
            anchors.fill: parent
            visible: false
            layer.enabled: shell.morphAnimating
            Rectangle {
                x: playerMorphSurface.x; y: playerMorphSurface.y
                width: playerMorphSurface.width; height: playerMorphSurface.height
                radius: playerMorphSurface.cornerRadius; color: "black"
            }
        }
        Loader {
            id: nowPlayingLoader
            objectName: "nowPlayingLoader"
            anchors.fill: parent
            z: 40
            active: shell.nowPlayingOpen
            visible: active
            opacity: shell.morphAnimating ? Math.min(1, shell.morphProgress / .85) : 1
            layer.enabled: shell.morphAnimating
            layer.effect: MultiEffect {
                maskEnabled: true; maskSource: playerMorphMask
                maskThresholdMin: .5; maskSpreadAtMin: 1
            }
            sourceComponent: nowPlayingComponent
        }

        FloatingPlayer {
            live: shell.playerController ? shell.playerController.live : false
            playbackMode: shell.playerController ? shell.playerController.playbackMode : "listLoop"
            id: floatingPlayer
            artworkInTransition: shell.morphAnimating
            surfaceInTransition: shell.morphAnimating
            expandedWidth: shell.width - 2 * AppTheme.playerEdgeMargin
            backdrop: libraryBackdrop
            z: 90
            x: AppTheme.playerEdgeMargin
            y: parent.height - floatingPlayer.height - AppTheme.playerEdgeMargin
            collapsed: shell.playerCollapsed || shell.settingsOpen
            playing: shell.playing
            accentColor: shell.accentColor
            progressValue: shell.playerController && shell.playerController.duration > 0
                           ? shell.playerController.position / shell.playerController.duration : 0
            positionMs: shell.playerController && shell.playerController.duration > 0
                        ? shell.playerController.position : 0
            durationMs: shell.playerController && shell.playerController.duration > 0
                        ? shell.playerController.duration : 0
            volumeValue: shell.playerController ? shell.playerController.volume : 0.68
            trackTitle: shell.displayedTrack.title || qsTr("未知歌曲")
            trackArtist: shell.playerController && shell.playerController.live ? (shell.playerController.radioProgram || shell.displayedTrack.artist || qsTr("直播广播")) : shell.displayedTrack.artist || qsTr("未知艺术家")
            trackAlbum: shell.displayedTrack.album || ""
            artworkSource: shell.displayedTrack.artwork && shell.displayedTrack.artwork.length
                           ? shell.displayedTrack.artwork : ""
            visible: !shell.nowPlayingOpen || shell.morphAnimating
            opacity: shell.morphAnimating ? Math.max(0, 1 - shell.morphProgress / .22) : 1
            darkMode: shell.darkMode
            reducedMotion: !shell.animationsEnabled || shell.captureView.length > 0
            volumePreview: shell.captureView === "floating-volume"
            onCoverActivated: shell.openNowPlaying()
            onModeToggleRequested: shell.playerCollapsed = !shell.playerCollapsed
            onPreviousRequested: shell.requestPlayback("previous")
            onPlayPauseRequested: { shell.requestPlayback("togglePlay") }
            onNextRequested: shell.requestPlayback("next")
            onQueueRequested: shell.openQueue(false)
            favorite: {
                if (shell.displayedTrack.radioId && shell.radioController) {
                    const revision = shell.radioController.favoritesRevision
                    return shell.radioController.isFavorite(shell.displayedTrack)
                }
                if (!shell.playlistController) return false
                const revision = shell.playlistController.likedTracksRevision
                return shell.playlistController.isTrackLiked(shell.displayedTrack)
            }
            onFavoriteRequested: shell.handleTrackCommand("favorite",shell.displayedTrack,-1)
            onProgressChangedByUser: function(value) {
                if (shell.playerController && shell.playerController.duration > 0)
                    shell.playerController.seek(Math.round(shell.playerController.duration * value))
            }
            onVolumeChangedByUser: function(value) { if (shell.playerController) shell.playerController.setVolume(value) }
            onCycleModeRequested: if(shell.playerController)shell.playerController.cyclePlaybackMode()
            onEndlessModeRequested: if(shell.playerController)shell.playerController.setPlaybackMode(shell.playerController.playbackMode === "endless" ? "listLoop" : "endless")
            onMuteToggleRequested: if(shell.playerController)shell.playerController.toggleMute()

        }

        Item {
            anchors.fill: parent
            z: 110
            visible: shell.morphAnimating && (!nowPlayingLoader.item || !nowPlayingLoader.item.overflowStyle)
            CoverArt {
                objectName: "playerMorphArtwork"
                readonly property real progress: shell.coverMorphProgress
                readonly property real startX: floatingPlayer.x + floatingPlayer.artworkLocalX
                readonly property real startY: floatingPlayer.y + floatingPlayer.artworkLocalY
                readonly property rect targetFrame: nowPlayingLoader.item ? nowPlayingLoader.item.artworkFrame
                    : Qt.rect(startX, startY, floatingPlayer.artworkSize, floatingPlayer.artworkSize)
                // A shallow quadratic arc; the same progress retraces it on close.
                readonly property real arcOffset: Math.min(32, Math.abs(startY - targetFrame.y) * .05)
                x: shell.mix(startX, targetFrame.x, progress) + 4 * progress * (1 - progress) * arcOffset
                y: shell.mix(startY, targetFrame.y, progress)
                width: shell.mix(floatingPlayer.artworkSize, targetFrame.width, progress)
                height: width
                sourcePixelSize: 768
                cornerRadius: shell.mix(shell.playerCollapsed ? 25 : 10, 20, shell.coverMorphProgress)
                showShadow: false
                source: floatingPlayer.artworkSource
            }
        }

        Item {
            parent: contentLoader
            anchors.fill: parent
            z: shell.collectionMorphUsesGrid ? 4 : 1
            visible: shell.collectionMorphActive

            readonly property rect targetFrame: detailLoader.item ? detailLoader.item.transitionTargetFrame : Qt.rect(0, 0, width, height)
            readonly property rect targetArtwork: detailLoader.item ? detailLoader.item.transitionTargetArtwork
                : shell.collectionMorphUsesGrid ? Qt.rect(32,40,160,160) : Qt.rect(42,14,132,132)

            GlassSurface {
                objectName: "collectionMorphSurface"
                visible: !shell.collectionMorphUsesGrid
                x: shell.mix(shell.collectionMorphSourceFrame.x-contentLoader.x, parent.targetFrame.x,
                             shell.collectionMorphProgress)
                y: shell.mix(shell.collectionMorphSourceFrame.y-contentLoader.y, parent.targetFrame.y,
                             shell.collectionMorphProgress)
                width: shell.mix(shell.collectionMorphSourceFrame.width, parent.targetFrame.width,
                                 shell.collectionMorphProgress)
                height: shell.mix(shell.collectionMorphSourceFrame.height, parent.targetFrame.height,
                                  shell.collectionMorphProgress)
                cornerRadius: shell.collectionMorphKind === "Album" ? 24 : shell.mix(24,0,shell.collectionMorphProgress)
                tint: Qt.rgba(shell.mix(AppTheme.albumShellTint.r, AppTheme.albumWindowTint.r, shell.collectionMorphProgress),
                              shell.mix(AppTheme.albumShellTint.g, AppTheme.albumWindowTint.g, shell.collectionMorphProgress),
                              shell.mix(AppTheme.albumShellTint.b, AppTheme.albumWindowTint.b, shell.collectionMorphProgress),
                              shell.mix(AppTheme.albumShellTint.a, AppTheme.albumWindowTint.a, shell.collectionMorphProgress))
                backdrop: navigationCache; backdropBlur: 36 * shell.collectionMorphProgress
                edgeColor: "#cfffffff"; shadowOpacity: .22 + .33 * shell.collectionMorphProgress
            }

            Item {
                id: collectionMorphArtwork
                objectName: "collectionMorphArtwork"
                readonly property bool frozen: shell.collectionMorphSourceItem !== null
                readonly property bool missingArtwork: frozen ? shell.collectionMorphSourceItem.missingArtwork : morphFallback.missingArtwork
                x: shell.mix(shell.collectionMorphSourceArtwork.x-contentLoader.x, parent.targetArtwork.x,
                             shell.collectionMorphProgress)
                y: shell.mix(shell.collectionMorphSourceArtwork.y-contentLoader.y, parent.targetArtwork.y,
                             shell.collectionMorphProgress)
                width: shell.mix(shell.collectionMorphSourceArtwork.width, parent.targetArtwork.width,
                                 shell.collectionMorphProgress)
                height: shell.mix(shell.collectionMorphSourceArtwork.height, parent.targetArtwork.height,
                                  shell.collectionMorphProgress)
                readonly property real cornerRadius: shell.mix(!shell.collectionMorphUsesGrid && shell.collectionMorphKind === "Album"
                                        ? 18 : shell.collectionMorphSourceArtwork.width / 10,
                                        !shell.collectionMorphUsesGrid && shell.collectionMorphKind === "Album" ? 18 : 15, shell.collectionMorphProgress)
                ShaderEffectSource {
                    id: collectionMorphSnapshot
                    anchors.fill: parent
                    sourceItem: shell.collectionMorphSourceItem
                    textureSize: Qt.size(320,320)
                    hideSource: shell.collectionMorphActive
                    live: false; smooth: true
                    visible: collectionMorphArtwork.frozen
                }
                CoverArt {
                    id: morphFallback
                    anchors.fill: parent
                    visible: !collectionMorphArtwork.frozen
                    source: visible ? shell.collectionMorphArtworkSource : ""
                    sourcePixelSize: 320
                    cornerRadius: collectionMorphArtwork.cornerRadius
                    showShadow: false
                }
            }
        }

        NumberAnimation {
            id: collectionMorphAnimation
            target: shell
            property: "collectionMorphProgress"
            from: 0
            to: 1
            duration: AppTheme.duration(shell.collectionMorphUsesGrid ? 500 : 360)
            easing.type: shell.collectionMorphUsesGrid ? Easing.BezierSpline : Easing.OutCubic
            easing.bezierCurve: [.4,0,.2,1,1,1]
            onStopped: {
                if (shell.collectionMorphClosing) {
                    shell.currentRoute = shell.previousRoute || "library/albums"
                    shell.routeChanged(shell.currentRoute)
                }
                shell.collectionMorphActive = !shell.collectionMorphClosing
                    && shell.currentRoute.indexOf("detail/") === 0 && detailLoader.status !== Loader.Ready
                shell.collectionMorphClosing = false
                shell.releaseInactiveCollectionRows()
            }
        }

        NumberAnimation {
            id: coverMorphAnimation
            target: shell; property: "coverMorphProgress"
            duration: morphAnimation.duration
            easing.type: Easing.BezierSpline; easing.bezierCurve: [.32,.72,0,1,1,1]
        }
        NumberAnimation {
            id: morphAnimation
            target: shell
            property: "morphProgress"
            duration: shell.animationsEnabled && !shell.captureView.length ? AppTheme.duration(720) * Math.abs(to - from) : 0
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [.23,1,.32,1,1,1]
            onFinished: {
                shell.morphAnimating = false
                if (shell.morphClosing) {
                    shell.nowPlayingOpen = false
                    shell.morphClosing = false
                }
            }
        }

        Item {
            id: queueOverlay
            visible: shell.queueFromImmersive ? immersiveQueueLoader.active : shell.queueProgress > 0.001
            anchors.fill: parent
            z: 200
            focus: shell.queueOpen
            Keys.onEscapePressed: function(event) {
                shell.closeQueue()
                event.accepted = true
            }

            Rectangle {
                anchors.fill: parent
                visible: !shell.queueFromImmersive
                color: AppTheme.scrim
                opacity: shell.queueProgress
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: shell.closeQueue(); onWheel: wheel => wheel.accepted = true }
            }

            QueuePanel {
                objectName: "playbackQueuePanel"
                visible: !shell.queueFromImmersive
                x: shell.queueFromNowPlaying && !shell.queueFromOverflow
                   ? -width + shell.queueProgress * width
                   : parent.width - width + (1 - shell.queueProgress) * width
                y: shell.queueFromNowPlaying ? 0 : 58
                width: shell.queueFromNowPlaying ? Math.min(520, parent.width) : 390
                height: shell.queueFromNowPlaying ? parent.height : parent.height - 58
                opacity: .82 + .18 * shell.queueProgress
                rows: shell.queueFromImmersive || sourceModel ? [] : shell.queueSongs
                darkMode: shell.darkMode
                fullScreenPresentation: shell.queueFromNowPlaying
                currentIndex: shell.currentQueueIndex
                sourceModel: !shell.queueFromImmersive && shell.useBackendModels && shell.playerController
                             ? shell.playerController.queueModel : null
                onCloseRequested: shell.closeQueue()
                onClearRequested: shell.clearQueue()
                onPlayRequested: function(index, track) { shell.activateQueue(index, track) }
                onRemoveRequested: function(index) { shell.removeQueue(index) }
                onTrackCommandRequested: (command,track,index) => shell.handleTrackCommand(command,track,index)
                onMoveRequested: function(from, to) { shell.moveQueue(from, to) }
                TapHandler { onTapped: {} }
            }
            Loader {
                id: immersiveQueueLoader
                anchors.fill: parent
                // Keep ownership until the exit callback, never derive Loader
                // lifetime from a property on the item being destroyed.
                active: shell.queueFromImmersive
                sourceComponent: ImmersiveDiscQueue {
                    open: shell.queueOpen
                    reducedMotion: !shell.animationsEnabled || !!shell.captureView.length
                    rows: sourceModel ? [] : shell.queueSongs
                    sourceModel: shell.useBackendModels && shell.playerController ? shell.playerController.queueModel : null
                    currentIndex: shell.currentQueueIndex
                    playing: shell.playing
                    onPlayRequested: (index, track) => shell.activateQueue(index, track)
                    onTogglePlaybackRequested: shell.requestPlayback("togglePlay")
                    onCloseRequested: shell.closeQueue()
                    onClosed: Qt.callLater(function() { if (!shell.queueOpen) shell.queueFromImmersive = false })
                }
            }
        }

        AlertDialog {
            z: 260
            anchors.fill: parent
            open: shell.globalAlertOpen
            title: shell.globalAlertTitle
            message: shell.globalAlertMessage
            options: shell.globalAlertOptions
            primaryLabel: qsTr("继续")
            secondaryLabel: qsTr("取消")
            onAccepted: function(option) {
                shell.globalAlertOpen = false
                if (shell.globalAlertCommand === "delete_from_disk" && shell.playerController) {
                    shell.playerController.removeLibraryTrack(JSON.parse(shell.globalAlertContext.payload).track, true)
                    return
                }
                if (!shell.facade) return
                if (shell.globalAlertCommand === "delete_from_disk")
                    shell.facade.requestQueue("track.delete_from_disk", shell.globalAlertContext.payload || "")
            }
            onRejected: shell.globalAlertOpen = false
        }

        MusicEditorDialog {
            id: musicEditor
            onMatchRequested: lyricsMatchPopup.match(shell.musicEditorTrack, true)
            onMetadataRequested: draft => metadataMatchPopup.match(draft)
            onOpenChanged: if (!open) metadataMatchPopup.close()
            z: 250
            anchors.fill: parent
            open: shell.musicEditorOpen || shell.captureView === "musiceditor" || shell.captureView === "musiceditor-properties"
            track: shell.musicEditorTrack
            darkMode: shell.darkMode
            reduceMotion: shell.captureView.length > 0
            selectedTab: shell.captureView === "musiceditor-properties" ? 2 : 0
            onCloseRequested: shell.musicEditorOpen = false
            onSaveRequested: function(values) {
                if (shell.playerController && shell.playerController.saveTrackTags(shell.musicEditorTrack, values))
                    shell.musicEditorOpen = false
            }
        }
    }

    component SectionLabel: Item {
        property alias text: sectionText.text
        width: shell.sidebarWidth - 24
        height: 18

        Text {
            id: sectionText
            x: 8 + shell.sidebarContentOffset
            anchors.verticalCenter: parent.verticalCenter
            color: AppTheme.sidebarSecondary
            opacity: shell.sidebarCollapsed ? 0 : .82
            visible: !shell.sidebarCollapsed
            scale: shell.sidebarCollapsed ? .2 : 1
            transformOrigin: Item.Left
            font.family: AppTheme.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            Behavior on opacity { NumberAnimation { duration: AppTheme.duration(90); easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: AppTheme.duration(110); easing.type: Easing.InCubic } }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: shell.sidebarCollapsed ? 30 : 0
            x: shell.sidebarCollapsed ? Math.round((parent.width - width) / 2) : 8
            height: 2
            radius: height / 2
            color: shell.darkMode ? "#98a4ad" : "#6f7b84"
            visible: shell.sidebarCollapsed
            opacity: .82
            Behavior on width { NumberAnimation { duration: AppTheme.duration(110); easing.type: Easing.OutCubic } }
        }
    }

    component SidebarButton: Rectangle {
        id: sidebarButton
        objectName: "sidebarNav_" + route.replace("/", "_")
        property string label: ""
        property string iconKind: "music"
        property string route: ""
        property bool selected: shell.currentRoute === route
                                || (shell.currentRoute === "detail/artist" && route === "library/artists")
                                || (shell.currentRoute === "detail/album" && route === "library/albums")
                                || (shell.currentRoute === "detail/playlist" && route === (shell.previousRoute === "my-lists" ? "my-lists" : "playlists"))
        signal pressed
        width: shell.sidebarCollapsed ? 42 : shell.sidebarWidth - 24
        x: Math.round((parent.width - width) / 2)
        height: 42
        radius: 12
        clip: true
        color: selected ? AppTheme.sidebarSelected : sideHover.hovered ? AppTheme.sidebarHover : "transparent"
        border.width: shell.sidebarCollapsed && selected ? 1 / Screen.devicePixelRatio : 0
        border.pixelAligned: false
        border.color: shell.darkMode ? "#24ffffff" : "#50ffffff"
        Behavior on color { ColorAnimation { duration: AppTheme.duration(110) } }
        Behavior on width { enabled: shell.captureView.length === 0; NumberAnimation { duration: AppTheme.duration(220); easing.type: Easing.InOutCubic } }
        HoverHandler { id: sideHover }
        TapHandler {
            onTapped: {
                shell.settingsOpen = false
                shell.currentRoute = route
                shell.routeChanged(shell.currentRoute)
                sidebarButton.pressed()
            }
        }
        IconGlyph {
            x: shell.sidebarCollapsed ? 11 : 14 + shell.sidebarContentOffset
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            kind: parent.iconKind
            glyphColor: AppTheme.sidebarText
            strokeWidth: 1.45
        }
        Text {
            x: 47 + shell.sidebarContentOffset
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 8
            text: label
            color: AppTheme.sidebarText
            opacity: shell.sidebarCollapsed ? 0 : 1
            visible: !shell.sidebarCollapsed
            font.family: AppTheme.fontFamily
            font.pixelSize: 14
            font.weight: selected ? Font.DemiBold : Font.Normal
            Behavior on opacity { NumberAnimation { duration: AppTheme.duration(140); easing.type: Easing.OutCubic } }
        }
    }

    component TopGlyph: RoundIconButton {
        property bool selected: false
        diameter: AppTheme.toolbarControlHeight
        // SVGs have different viewBox padding; keep their visible height close
        // to the 18 px window dots while preserving a 32 px pointer target.
        glyphSize: kind === "sun" ? 18 : kind === "gear" ? 22 : 23
        transparentSurface: shell.artworkCanvasActive || !selected
        prominent: selected
        darkMode: AppTheme.canvasDark
        hoverColor: shell.artworkCanvasActive ? "#40808080" : AppTheme.actionHover
        pressedColor: shell.artworkCanvasActive ? "#60808080" : AppTheme.actionPressed
        surfaceColor: darkMode ? "#30ffffff" : "#32606a74"
        glyphColor: AppTheme.canvasText
    }

    Component {
        id: libraryComponent
        LibraryPage {
            readonly property string routeKey: parent.routeKey || "library/albums"
            filterText: shell.filterForRoute(routeKey)
            id: libraryPage
            catalog: routeKey === "library/albums" && shell.albumMosaicLayout ? null : shell.catalog
            albumGridLayout: shell.albumGridLayout
            tracksModel: shell.useBackendModels && shell.appController ? shell.appController.tracksModel : null
            section: routeKey === "library/songs" ? "songs" : routeKey === "library/artists" ? "artists" : "albums"
            darkMode: shell.darkMode
            deferCollectionOpen: true
            onCollectionTransitionRequested: function(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem) {
                shell.prepareCollectionMorph(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem)
                libraryPage.commitPreparedCollection()
            }
            onOpenCollection: function(kind, title, tint) { shell.openCollection(kind, title, tint) }
            onTrackActivated: function(track, playbackContext) { shell.playTrack(track, playbackContext) }
            onTrackCommandRequested: function(command, track, rowIndex, playbackContext) {
                shell.handleTrackCommand(command, track, rowIndex, playbackContext)
            }
            onTrackSortRequested: function(column, order) { shell.requestTrackSort(column, order) }
        }
    }
    FocusScope {
        id: downloadsOverlay
        z: 130
        anchors.fill: parent
        visible: shell.downloadsOpen || downloadDrawer.x < width
        focus: shell.downloadsOpen
        function dismiss() {
            downloadDrawer.deletingId = ""
            shell.downloadsOpen = false
        }
        Keys.onEscapePressed: event => { dismiss(); event.accepted = true }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: downloadsOverlay.dismiss()
            onWheel: wheel => wheel.accepted = true
        }
        DownloadPanel {
            id: downloadDrawer
            y: 60; height: parent.height - y
            width: 450
            x: shell.downloadsOpen ? parent.width - width : parent.width
            controller: shell.downloadController
            onCloseRequested: downloadsOverlay.dismiss()
            Behavior on x { NumberAnimation { duration: AppTheme.duration(240); easing.type: Easing.OutCubic } }
        }
    }
    ContextMenu {
        id: nowPlayingFavoriteMenu
        objectName: "nowPlayingFavoriteMenu"
        anchors.fill: parent
        z: 150
        menuWidth: 244
        actions: {
            const entries = [{ label: qsTr("收藏到“我的收藏”"), enabled: false }]
            for (let i = 0; i < shell.editablePlaylists.length; ++i) {
                const list = shell.editablePlaylists[i]
                entries.push({ label: list.title, command: "list:" + list.id,
                               separatorBefore: i === 0 })
            }
            entries.push({ label: qsTr("新建歌单…"), command: "create", separatorBefore: true })
            return entries
        }
        onCommandTriggered: function(command, track) {
            if (!shell.playlistController || !track) return
            if (command === "create") {
                shell.pendingPlaylistTracks = [track]
                shell.addPlaylistCreateOnly = true
                Qt.callLater(function() { shell.addPlaylistOpen = true })
            } else if (command.indexOf("list:") === 0) {
                shell.playlistController.addTracks(command.substring(5), [track])
            }
        }
    }
    AlertDialog {
        anchors.fill: parent
        z: 150
        open: shell.addPlaylistOpen
        title: shell.addPlaylistCreateOnly ? qsTr("新建收藏歌单") : qsTr("添加到歌单")
        message: shell.addPlaylistCreateOnly ? qsTr("输入名称，将当前歌曲收藏到新歌单") : qsTr("选择歌单，或输入名称新建")
        primaryLabel: shell.addPlaylistCreateOnly ? qsTr("新建并收藏") : qsTr("添加")
        secondaryLabel: qsTr("取消")
        onOpenChanged: if (open && contentItem) {
            contentItem.newName = ""
            contentItem.targetId = ""
        }
        contentComponent: Component {
            Column {
                property string targetId: ""
                property alias newName: listName.text
                spacing: 10
                SettingsSelect {
                    width: parent.width
                    visible: !shell.addPlaylistCreateOnly
                    options: shell.editablePlaylists.map(function(p) { return {label:p.title,value:p.id} })
                    onValueSelected: function(value, index) { parent.targetId = value }
                }
                Rectangle {
                    width: parent.width; height: 40; radius: 10; color: AppTheme.field
                    TextInput { id: listName; anchors.fill: parent; anchors.margins: 10; color: AppTheme.textPrimary; clip: true
                        Text { visible: !listName.text.length; text: qsTr("新歌单名称"); color: AppTheme.textMuted }
                    }
                }
            }
        }
        onRejected: shell.addPlaylistOpen = false
        onAccepted: {
            if (contentItem.newName.trim().length) {
                if (!shell.playlistController.create(contentItem.newName.trim(), shell.pendingPlaylistTracks).length) return
            }
            else if (shell.addPlaylistCreateOnly) return
            else {
                const id = contentItem.targetId || (shell.editablePlaylists.length ? shell.editablePlaylists[0].id : "")
                if (!id.length) return
                shell.playlistController.addTracks(id, shell.pendingPlaylistTracks)
            }
            shell.addPlaylistOpen = false
        }
    }
    Component {
        id: myListsComponent
        MyListsPage {
            filterText: shell.filterForRoute("my-lists")
            catalog: shell.catalog
            playlistController: shell.playlistController
            radioController: shell.radioController
            backdrop: globalBackground
            darkMode: shell.darkMode
            onOpenCollection: function(kind, title, tint) { shell.openCollection(kind, title, tint) }
            onCollectionTransitionRequested: function(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem) {
                shell.prepareCollectionMorph(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem)
                shell.openCollection(kind, title, tint)
            }
            onTrackActivated: (track, playbackContext) => shell.playTrack(track, playbackContext)
            onPodcastRequested: podcast => {
                shell.radioReturnToFavorites=true
                shell.radioController.openPodcast(podcast)
                shell.currentRoute="radio"
                shell.routeChanged("radio")
            }
            onTrackCommandRequested: function(command, track, rowIndex, playbackContext) {
                shell.handleTrackCommand(command, track, rowIndex, playbackContext)
            }
            onTrackSortRequested: function(column, order) { shell.requestTrackSort(column, order) }
            onCreateRequested: function(name) { shell.playlistController.create(name) }
            onUpdateRequested: shell.playlistController.refresh()
            onRefreshPlaylistRequested: function(playlist) { shell.playlistController.open(playlist) }
            onRenamePlaylistRequested: function(playlist) {}
            onRemovePlaylistRequested: function(playlist) { shell.playlistController.remove(playlist.id) }

        }
    }
    Component {
        id: discoverComponent
        DiscoverPage {
            searchController: shell.playerController
            onSearchRequested: (term, platform) => { if (platform.length) shell.playerController.setPlatform(platform); shell.runSearch(term) }
            catalog: shell.playlistController
            darkMode: shell.darkMode
            onCollectionRequested: collection => shell.openOnlineCollection(collection)
            onCollectionTransitionRequested: function(collection, frameRect, artworkRect, artworkSource, artworkItem) {
                shell.prepareCollectionMorph("Playlist", collection.title, collection.color || "#80868d", frameRect, artworkRect, artworkSource, artworkItem)
                shell.openOnlineCollection(collection)
            }
            onTrackActivated: (track, playbackContext) => shell.playTrack(track, playbackContext)
            onTrackCommandRequested: (command,track,rowIndex,playbackContext) => shell.handleTrackCommand(command,track,rowIndex,playbackContext)

        }
    }
    Component {
        id: playlistComponent
        PlaylistPage {
            backdrop: globalBackground
            filterText: shell.filterForRoute("playlists")
            platformNames: shell.platformNames
            catalog: shell.playlistController
            darkMode: shell.darkMode
            filterOpen: shell.captureView === "playlist-filter"
            shareOpen: shell.captureView === "playlist-share"
            onOpenCollection: function(kind, title, tint) { shell.openCollection(kind, title, tint) }
            onCollectionTransitionRequested: function(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem) {
                shell.prepareCollectionMorph(kind, title, tint, frameRect, artworkRect, artworkSource, artworkItem)
                shell.openCollection(kind, title, tint)
            }
            onFilterChanged: function(key, value) { shell.playlistController.filter(key, value) }
            onShareLinkRequested: function(source, link) {
                shell.currentRoute = "detail/playlist"
                shell.playlistController.openLink(link)
            }

        }
    }
    Component {
        id: radioComponent
        RadioPage {
            service: shell.radioController
            playerController: shell.playerController
            backdrop: globalBackground
            darkMode: shell.darkMode
            filterText: shell.filterForRoute("radio")
            onTrackActivated: (track, playbackContext) => shell.playTrack(track, playbackContext)
            onPodcastOpened: shell.radioReturnToFavorites=false
            onPodcastClosed: {
                if(shell.radioReturnToFavorites) {
                    shell.radioReturnToFavorites=false
                    shell.currentRoute="my-lists"
                    shell.routeChanged("my-lists")
                }
            }
        }
    }
    Component {
        id: searchComponent
        SearchPage {
            backdrop: globalBackground
            platformNames: shell.platformNames
            catalog: shell.catalog
            query: shell.searchQuery
            onlineController: shell.onlineController
            darkMode: shell.darkMode
            onTrackActivated: (track, playbackContext) => {
                shell.playTrack(track, playbackContext)
            }
            onTrackCommandRequested: function(command, track, rowIndex, playbackContext) {
                shell.handleTrackCommand(command, track, rowIndex, playbackContext)
            }
            onTrackSortRequested: function(column, order) { shell.requestTrackSort(column, order) }
            onCollectionActivated: collection => shell.openOnlineCollection(collection)
        }
    }
    Component {
        id: collectionComponent
        CollectionPage {
            artistImageAspect: artistCanvasLoader.item ? artistCanvasLoader.item.displayedAspect : 1.6
            artistArtworkReady: !!artistCanvasLoader.item && artistCanvasLoader.item.heroReady
            onlineCollection: shell.selectedOnlineCollection
            albumGridLayout: shell.albumGridLayout
            backdrop: navigationCache
            transitionActive: shell.collectionMorphActive
            filterText: shell.pageSearchQuery
            kind: shell.currentRoute === "detail/artist" ? "Artist" : shell.currentRoute === "detail/playlist" ? "Playlist" : "Album"
            title: shell.selectedCollectionTitle
            subtitle: shell.selectedCollectionSubtitle
            tint: shell.selectedCollectionTint
            coverIndex: shell.selectedCollectionCover
            artworkSource: shell.currentRoute === "detail/artist" ? shell.artistFallbackArtwork : shell.selectedCollectionArtwork
            rows: shell.selectedCollectionRows
            darkMode: shell.darkMode
            reduceMotion: !shell.animationsEnabled
            onBackRequested: shell.closeCollection()
            onPlayAllRequested: shell.playerController.playAll(rows)
            onShuffleAllRequested: { shell.playerController.setPlaybackMode("shuffle"); shell.playerController.playAll(rows) }
            editablePlaylist: kind === "Playlist" && shell.playlistController.detail.kind === "Local" && !shell.playlistController.detail.reference
            onTrackActivated: (track, playbackContext) => shell.playTrack(track, playbackContext)
            onTrackCommandRequested: function(command, track, rowIndex, playbackContext) {
                if (command === "remove_from_playlist" && editablePlaylist) {
                    const detail=shell.playlistController.detail
                    const key=t => t.localPath ? t.localPath.replace(/\\/g,"/").toLowerCase() : t.source+":"+t.rid
                    const index=(detail.tracks || []).findIndex(t => key(t)===key(track))
                    if(index>=0) { shell.playlistController.removeTrack(detail.id,index); shell.playlistController.openTitle(shell.selectedCollectionTitle) }
                } else shell.handleTrackCommand(command, track, rowIndex, playbackContext)
            }
            onTrackSortRequested: function(column, order) { shell.requestTrackSort(column, order) }
            albumYear: kind === "Album" && rows.length ? shell.playerController.albumYear(rows[0].localPath || "") : ""
            artistVisual: (shell.playerController.artistVisual.requestedName || shell.playerController.artistVisual.name) === shell.selectedCollectionTitle ? shell.playerController.artistVisual : ({})
            playCount: kind === "Playlist" ? String(shell.playlistController.detail.playCount || shell.playlistController.detail.playcount || "") : ""
            onDownloadAllRequested: shell.chooseDownload(shell.selectedCollectionRows)
            saved: {
                const revisions = shell.playlistController ? shell.playlistController.playlists : []
                return shell.playlistController && shell.playlistController.isSaved(kind === "Playlist" || shell.selectedOnlineCollection ? shell.playlistController.detail : ({id: kind+":"+shell.selectedCollectionTitle, source:"Local"}))
            }
            onSaveRequested: {
                if (kind === "Playlist" || shell.selectedOnlineCollection) shell.playlistController.toggleSaved(shell.playlistController.detail)
                else shell.playlistController.toggleSaved({ id: kind+":"+shell.selectedCollectionTitle, source: "Local", kind: "Local", title: shell.selectedCollectionTitle, artwork: shell.selectedCollectionArtwork, tracks: shell.selectedCollectionRows })
            }
        }
    }
    Component {
        id: settingsComponent
        SettingsPage {
            settingsStore: shell.settingsController
            downloadController: shell.downloadController
            playerController: shell.playerController
            filterText: shell.settingsSearchQuery
            refreshRateLimit: shell.refreshRateLimit
            darkMode: shell.darkMode
            selectedFont: shell.uiFontFamily
            animationsEnabled: shell.animationsEnabled
            animationStyle: shell.animationStyle
            libraryController: shell.libraryController
            sourceController: shell.sourceController
            dynamicArtworkEnabled: shell.playerController.dynamicArtworkEnabled
            neteaseAccountName: shell.neteaseAccountName
            bilibiliAccountName: shell.bilibiliAccountName
            onCloseRequested: shell.settingsOpen = false
            onThemeToggleRequested: shell.toggleTheme()
            onRefreshRateChanged: {
                shell.refreshRateLimit = value
                shell.facade.setSetting("ui.refreshRateLimit", value)
                if (shell.settingsController) shell.settingsController.setValue("ui.refreshRateLimit", value)
            }
            onScanRequested: {
                if (shell.libraryController) shell.libraryController.scanDefault()
                shell.facade.requestQueue("scanLibrary", "local")
            }
            onMergeRequested: shell.openDuplicateAlert()
            onSourceRemoveRequested: function(sourceId) {
                if (shell.facade)
                    shell.facade.requestQueue("source.remove", sourceId)
            }
            onSourceImportLocalRequested: shell.playerController.importSource()
            onSourceImportOnlineRequested: function(url) { if (shell.sourceController) shell.sourceController.importUrl(url) }
            onSourceSelectionRequested: function(sourceId) { if (shell.sourceController) shell.sourceController.selectSource(sourceId) }
            onSourceUpdatePromptChanged: function(sourceId, enabled) { if (shell.sourceController) shell.sourceController.setUpdatePrompt(sourceId, enabled) }
            onAccountCookieSaveRequested: function(provider, cookie) {
                if (shell.facade)
                    shell.facade.requestAccountCookieSave(provider, cookie)
            }
            onAccountLogoutRequested: function(provider) {
                if (shell.facade)
                    shell.facade.requestAccountLogout(provider)
            }
            onSettingChanged: function(key, value) {
                if (key === "ui.language")
                    shell.uiLanguage = value === "EnUs" ? "en-US" : "zh-CN"
                else if (key === "ui.fontFamily")
                    shell.uiFontFamily = String(value)
                else if (key === "ui.motionEnabled")
                    shell.animationsEnabled = Boolean(value)
                else if (key === "ui.motionStyle")
                    shell.animationStyle = String(value)
                if (shell.facade) shell.facade.setSetting(key, value)
                if (shell.settingsController) shell.settingsController.setValue(key, value)
            }
        }
    }
    Component {
        id: nowPlayingComponent
        NowPlayingPage {
            playerController: shell.playerController
            track: shell.displayedTrack
            immersiveService: typeof backendImmersive !== "undefined" ? backendImmersive : null
            mixing: shell.playerController ? !!shell.playerController.mixing : false
            live: shell.playerController ? shell.playerController.live : false
            radioContent: !!shell.displayedTrack.radioId
            artworkInTransition: shell.morphAnimating
            playbackMode: shell.playerController ? shell.playerController.playbackMode : "listLoop"
            localTrack: !!shell.displayedTrack.localPath
            onCycleModeRequested: if(shell.playerController)shell.playerController.cyclePlaybackMode()
            onEndlessModeRequested: if(shell.playerController)shell.playerController.setPlaybackMode(shell.playerController.playbackMode === "endless" ? "listLoop" : "endless")
            onEqualizerRequested: equalizerPopup.open()
            onInformationRequested: shell.openMusicEditor(shell.displayedTrack)
            onDownloadRequested: shell.chooseDownload([shell.displayedTrack])
            onFavoriteRequested: function(anchorItem) {
                if (!shell.playlistController) return
                const point = anchorItem.mapToItem(shell, 0, anchorItem.height)
                nowPlayingFavoriteMenu.openAt(point.x, point.y, shell.displayedTrack)
            }
            onLyricsMatchRequested: lyricsMatchPopup.match(shell.displayedTrack, false)
            settingsStore: shell.settingsController
            neteaseComments: !!shell.playerController.currentTrack.localPath || shell.playerController.currentTrack.source === "wy"
            commentsAvailable: !!shell.playerController.currentTrack.localPath || ((shell.playerController.currentTrack.source === "kw" || shell.playerController.currentTrack.source === "wy") && !!shell.playerController.currentTrack.rid)
            motionSource: shell.playerController.dynamicArtworkUrl
            lyrics: shell.catalog.lyrics
            trackIdentity: String(shell.playerController.currentTrack.entryId || "")
            commentsBusy: shell.playerController.commentsBusy
            commentsError: shell.playerController.commentsError
            onCommentsRequested: function(more) { shell.playerController.requestComments(commentSortMode, more) }
            comments: shell.catalog && shell.catalog.comments ? shell.catalog.comments : null
            hostWindow: shell.hostWindow
            darkMode: shell.darkMode
            reducedMotion: !shell.animationsEnabled || shell.captureView.length > 0
            playing: shell.playing
            currentLine: shell.playerController && shell.playerController.currentLyricIndex >= 0
                         ? shell.playerController.currentLyricIndex : -1
            progressValue: shell.playerController && shell.playerController.duration > 0
                           ? shell.playerController.position / shell.playerController.duration : 0
            positionMs: shell.playerController && shell.playerController.duration > 0
                        ? shell.playerController.position : 0
            durationMs: shell.playerController && shell.playerController.duration > 0
                        ? shell.playerController.duration : 0
            volumeValue: shell.playerController ? shell.playerController.volume : 0.68
            trackTitle: shell.displayedTrack.title || qsTr("未知歌曲")
            trackArtist: shell.displayedTrack.artist || qsTr("未知艺术家")
            trackAlbum: shell.displayedTrack.album || ""
            artworkSource: shell.displayedTrack.artwork && shell.displayedTrack.artwork.length
                           ? shell.displayedTrack.artwork : ""
            onCloseRequested: shell.closeNowPlaying()
            onThemeToggleRequested: shell.toggleTheme()
            onQueueRequested: shell.openQueue(true)
            onPlayPauseRequested: { shell.requestPlayback("togglePlay") }
            onPreviousRequested: shell.requestPlayback("previous")
            onNextRequested: shell.requestPlayback("next")
            onPlaybackModeRequested: function(mode) { if (shell.playerController) shell.playerController.setPlaybackMode(mode) }
            onProgressChangedByUser: function(value) { if (shell.playerController && shell.playerController.duration > 0) shell.playerController.seek(Math.round(shell.playerController.duration * value)) }
            onVolumeChangedByUser: function(value) { if (shell.playerController) shell.playerController.setVolume(value) }
            onCommentSortRequested: function(mode) { shell.playerController.requestComments(mode) }
            onLyricSeekRequested: function(timeMs, index) {
                if (shell.playerController && timeMs >= 0)
                    shell.playerController.seek(Math.round(timeMs))
                if (shell.facade)
                    shell.facade.requestQueue("lyrics.seek", JSON.stringify({ timeMs: timeMs, index: index }))
            }
            onLyricDisplaySettingRequested: function(key, value) {
                const settingKey = "lyrics." + (({fontSize: "textSize", currentLinePosition: "currentLineAnchor"})[key] || key)
                if (shell.settingsController)
                    shell.settingsController.setValue(settingKey, value)
                if (shell.facade)
                    shell.facade.setSetting(settingKey, value)
            }
        }
    }
    Component {
        id: placeholderComponent
        Item {
            Rectangle { anchors.fill: parent; color: "transparent" }
            Column {
                anchors.centerIn: parent
                spacing: 10
                Text { text: shell.currentRoute === "discover" ? qsTr("发现") : qsTr("歌单"); color: AppTheme.textPrimary; font.pixelSize: 30; font.weight: Font.DemiBold; anchors.horizontalCenter: parent.horizontalCenter }
                Text { text: qsTr("在线功能将在后续阶段接入"); color: AppTheme.textSecondary; font.pixelSize: 14; anchors.horizontalCenter: parent.horizontalCenter }
            }
        }
    }
}
