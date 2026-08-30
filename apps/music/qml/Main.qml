pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Kos.Ui

KosApplicationWindow {
    id: root

    visible: true
    title: qsTr("Music")
    minimumWidth: 860
    minimumHeight: 580

    property string page: "recent"
    property string detailName: ""
    property string detailSubtitle: ""
    property var selectedPlaylistId: -1
    property string selectedPlaylistName: ""
    property var pendingTrackId: -1
    property string pendingTrackTitle: ""
    property string pendingFormatId: ""
    property string pendingFormatExtension: ""
    property real pendingSeekMs: 0
    property string statusMessage: ""
    property bool renamePlaylistMode: false

    readonly property bool isLibraryTrackPage:
        page === "recent" || page === "songs"
        || page === "album" || page === "artist"
    readonly property int contentIndex: {
        if (isLibraryTrackPage) return 0
        if (page === "albums") return 1
        if (page === "artists") return 2
        if (page === "queue") return 3
        if (page === "playlist") return 4
        return 5
    }
    readonly property string contentTitle: {
        if (page === "recent") return qsTr("Recently added")
        if (page === "songs") return qsTr("Songs")
        if (page === "albums") return qsTr("Albums")
        if (page === "artists") return qsTr("Artists")
        if (page === "queue") return qsTr("Play queue")
        if (page === "playlist") return selectedPlaylistName
        if (page === "folders") return qsTr("Music folders")
        return detailName
    }
    readonly property string contentSubtitle: {
        if (page === "folders")
            return qsTr("Choose which local folders are indexed")
        if (page === "albums")
            return qsTr("%n album(s)", "", music.albums.length)
        if (page === "artists")
            return qsTr("%n artist(s)", "", music.artists.length)
        if (page === "queue")
            return qsTr("%n queued track(s)", "", music.queueModel.count)
        if (page === "playlist")
            return qsTr("%n track(s)", "", music.playlistTracksModel.count)
        if (page === "album" || page === "artist")
            return detailSubtitle.length > 0 ? detailSubtitle
                : qsTr("%n track(s)", "", music.libraryModel.count)
        return qsTr("%n track(s)", "", music.libraryModel.count)
    }

    function formatTime(milliseconds) {
        const seconds = Math.max(0, Math.floor(Number(milliseconds) / 1000))
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor(seconds / 60) % 60
        const rest = seconds % 60
        if (hours > 0)
            return hours + ":" + String(minutes).padStart(2, "0")
                + ":" + String(rest).padStart(2, "0")
        return minutes + ":" + String(rest).padStart(2, "0")
    }

    function showStatus(message) {
        statusMessage = message
        statusTimer.restart()
    }

    function openLibraryPage(destination) {
        page = destination
        detailName = ""
        detailSubtitle = ""
        if (destination === "recent")
            music.setLibraryView("recent")
        else if (destination === "songs")
            music.setLibraryView("songs")
    }

    function openAlbum(name, subtitle, filterValue) {
        detailName = name
        detailSubtitle = subtitle
        page = "album"
        music.setLibraryView("album", filterValue)
    }

    function openArtist(name, filterValue) {
        detailName = name
        detailSubtitle = qsTr("Songs by %1").arg(name)
        page = "artist"
        music.setLibraryView("artist", filterValue)
    }

    function openPlaylist(playlistId, name) {
        selectedPlaylistId = playlistId
        selectedPlaylistName = name
        page = "playlist"
        music.selectPlaylist(playlistId)
    }

    function requestPlaylistFor(trackId) {
        pendingTrackId = trackId
        playlistPicker.open()
    }

    function requestTranscode(trackId, trackTitle) {
        pendingTrackId = trackId
        pendingTrackTitle = trackTitle
        formatDialog.open()
    }

    MusicController { id: music }

    Component.onCompleted: music.setLibraryView("recent")

    Connections {
        target: music

        function onRaiseRequested() {
            root.show()
            root.raise()
            root.requestActivate()
        }

        function onUserMessage(message) {
            root.showStatus(message)
        }
    }

    Timer {
        id: statusTimer
        interval: 4200
        onTriggered: root.statusMessage = ""
    }

    Shortcut {
        sequence: StandardKey.Open
        onActivated: openFileDialog.open()
    }
    Shortcut {
        sequence: StandardKey.Refresh
        onActivated: music.rescanLibrary()
    }
    Shortcut {
        sequence: "Ctrl+L"
        onActivated: {
            if (searchField.visible) {
                searchField.forceActiveFocus()
                searchField.selectAll()
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Add a music folder")
        onAccepted: music.addLibraryFolder(selectedFolder.toString())
    }

    FileDialog {
        id: openFileDialog
        title: qsTr("Open an audio file")
        fileMode: FileDialog.OpenFile
        nameFilters: [
            qsTr("Audio files (*.mp3 *.flac *.ogg *.opus *.wav *.m4a *.aac *.wma *.aiff *.ape)"),
            qsTr("All files (*)")
        ]
        onAccepted: music.openUri(selectedFile.toString())
    }

    Dialog {
        id: playlistEditor
        anchors.centerIn: parent
        title: root.renamePlaylistMode ? qsTr("Rename playlist")
                                       : qsTr("New playlist")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onOpened: {
            playlistName.text = root.renamePlaylistMode
                ? root.selectedPlaylistName : ""
            playlistName.forceActiveFocus()
            playlistName.selectAll()
        }
        onAccepted: {
            const cleaned = playlistName.text.trim()
            if (cleaned.length === 0)
                return
            if (root.renamePlaylistMode) {
                music.renamePlaylist(root.selectedPlaylistId, cleaned)
                root.selectedPlaylistName = cleaned
            } else {
                music.createPlaylist(cleaned)
            }
        }

        contentItem: ColumnLayout {
            spacing: 10
            Label {
                text: qsTr("Playlist name")
                color: AppTheme.mutedText
            }
            LiquidTextField {
                id: playlistName
                Layout.preferredWidth: 330
                maximumLength: 128
                placeholderText: qsTr("My playlist")
                onAccepted: playlistEditor.accept()
            }
        }
    }

    Dialog {
        id: removePlaylistDialog
        anchors.centerIn: parent
        title: qsTr("Remove playlist?")
        modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        onAccepted: {
            music.removePlaylist(root.selectedPlaylistId)
            root.openLibraryPage("recent")
            root.selectedPlaylistId = -1
            root.selectedPlaylistName = ""
        }
        contentItem: Label {
            width: 340
            text: qsTr("The playlist will be removed. Your audio files will not be deleted.")
            color: AppTheme.text
            wrapMode: Text.WordWrap
        }
    }

    Dialog {
        id: playlistPicker
        anchors.centerIn: parent
        title: qsTr("Add to playlist")
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (playlistChoice.currentIndex >= 0) {
                const selected = music.playlists[playlistChoice.currentIndex]
                music.addTrackToPlaylist(Number(selected.id), root.pendingTrackId)
                root.showStatus(qsTr("Added to %1").arg(String(selected.name)))
            }
        }

        contentItem: ColumnLayout {
            spacing: 10
            Label {
                text: music.playlists.length > 0
                    ? qsTr("Choose a playlist")
                    : qsTr("Create a playlist first")
                color: AppTheme.mutedText
            }
            ComboBox {
                id: playlistChoice
                Layout.preferredWidth: 330
                model: music.playlists
                textRole: "name"
                enabled: count > 0
                Accessible.name: qsTr("Playlist")
            }
        }
    }

    Dialog {
        id: formatDialog
        anchors.centerIn: parent
        title: qsTr("Convert %1").arg(root.pendingTrackTitle)
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (formatChoice.currentIndex < 0)
                return
            const format = music.availableTranscodeFormats[formatChoice.currentIndex]
            root.pendingFormatId = String(format.id)
            root.pendingFormatExtension = String(format.extension)
            saveConvertedDialog.defaultSuffix = root.pendingFormatExtension
            saveConvertedDialog.nameFilters = [String(format.label)
                                                + " (*." + String(format.extension) + ")"]
            saveConvertedDialog.open()
        }

        contentItem: ColumnLayout {
            spacing: 10
            Label {
                Layout.preferredWidth: 350
                text: music.availableTranscodeFormats.length > 0
                    ? qsTr("Choose an output format. Available formats reflect the encoders installed on this system.")
                    : qsTr("No supported GStreamer encoders are installed.")
                color: AppTheme.mutedText
                wrapMode: Text.WordWrap
            }
            ComboBox {
                id: formatChoice
                Layout.preferredWidth: 350
                model: music.availableTranscodeFormats
                textRole: "label"
                enabled: count > 0
                Accessible.name: qsTr("Output format")
            }
        }
    }

    FileDialog {
        id: saveConvertedDialog
        title: qsTr("Save converted audio")
        fileMode: FileDialog.SaveFile
        onAccepted: music.transcodeTrack(root.pendingTrackId,
                                          selectedFile.toString(),
                                          root.pendingFormatId, true)
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: root.width < 960 ? 212 : 238
            color: AppTheme.withAlpha(AppTheme.sidebar, 0.94)
            border.width: 1
            border.color: AppTheme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 6

                Label {
                    text: qsTr("KOS Music")
                    color: AppTheme.text
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    Layout.bottomMargin: 12
                }

                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Recently added")
                    symbol: "◷"
                    checked: root.page === "recent"
                    onClicked: root.openLibraryPage("recent")
                }
                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Songs")
                    symbol: "♫"
                    checked: root.page === "songs"
                    onClicked: root.openLibraryPage("songs")
                }
                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Albums")
                    symbol: "▦"
                    checked: root.page === "albums" || root.page === "album"
                    onClicked: root.page = "albums"
                }
                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Artists")
                    symbol: "♙"
                    checked: root.page === "artists" || root.page === "artist"
                    onClicked: root.page = "artists"
                }
                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Queue")
                    symbol: "≡"
                    checked: root.page === "queue"
                    onClicked: root.page = "queue"
                }
                KosNavigationButton {
                    Layout.fillWidth: true
                    text: qsTr("Folders")
                    symbol: "▱"
                    checked: root.page === "folders"
                    onClicked: root.page = "folders"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 12

                    Label {
                        Layout.fillWidth: true
                        text: qsTr("PLAYLISTS")
                        color: AppTheme.mutedText
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    ToolButton {
                        text: "+"
                        flat: true
                        Accessible.name: qsTr("Create playlist")
                        onClicked: {
                            root.renamePlaylistMode = false
                            playlistEditor.open()
                        }
                    }
                }

                ListView {
                    id: playlistList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: music.playlists
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: KosNavigationButton {
                        id: playlistDelegate

                        required property var modelData

                        width: playlistList.width
                        text: String(modelData.name ?? "")
                        symbol: "♬"
                        checked: root.page === "playlist"
                            && Number(root.selectedPlaylistId) === Number(modelData.id)
                        onClicked: root.openPlaylist(Number(modelData.id),
                                                     String(modelData.name))
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: music.scanning

                    BusyIndicator {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        running: visible
                    }
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Scanning library…")
                        color: AppTheme.mutedText
                        elide: Text.ElideRight
                        font.pixelSize: 11
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: music.engineAvailable
                        ? qsTr("Engine: %1").arg(music.engineBackend)
                        : qsTr("Playback engine unavailable")
                    color: music.engineAvailable ? AppTheme.positive : AppTheme.destructive
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                }
                Label {
                    Layout.fillWidth: true
                    text: music.mprisRegistered
                        ? qsTr("MPRIS controls connected")
                        : qsTr("MPRIS needs a session bus")
                    color: music.mprisRegistered ? AppTheme.positive : AppTheme.mutedText
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: root.width < 960 ? 16 : AppTheme.pageMargin
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: root.contentTitle
                        color: AppTheme.text
                        font.pixelSize: 27
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.contentSubtitle
                        color: AppTheme.mutedText
                        elide: Text.ElideRight
                    }
                }

                LiquidTextField {
                    id: searchField
                    Layout.preferredWidth: root.width < 1040 ? 180 : 240
                    visible: root.isLibraryTrackPage
                    placeholderText: qsTr("Search library…")
                    Accessible.name: qsTr("Search music library")
                    onTextChanged: music.setSearch(text)
                }

                Button {
                    text: qsTr("Add folder")
                    highlighted: music.libraryFolders.length === 0
                    onClicked: folderDialog.open()
                }

                ToolButton {
                    text: "⋮"
                    Accessible.name: qsTr("Library actions")
                    onClicked: libraryMenu.popup()

                    Menu {
                        id: libraryMenu
                        MenuItem {
                            text: qsTr("Open audio file…")
                            onTriggered: openFileDialog.open()
                        }
                        MenuItem {
                            text: qsTr("Add music folder…")
                            onTriggered: folderDialog.open()
                        }
                        MenuItem {
                            text: qsTr("Rescan library")
                            enabled: !music.scanning
                            onTriggered: music.rescanLibrary()
                        }
                        MenuSeparator {
                            visible: root.page === "queue"
                                || root.page === "playlist"
                        }
                        MenuItem {
                            visible: root.page === "queue"
                            text: qsTr("Clear queue")
                            onTriggered: music.clearQueue()
                        }
                        MenuItem {
                            visible: root.page === "playlist"
                            text: qsTr("Rename playlist…")
                            onTriggered: {
                                root.renamePlaylistMode = true
                                playlistEditor.open()
                            }
                        }
                        MenuItem {
                            visible: root.page === "playlist"
                            text: qsTr("Remove playlist…")
                            onTriggered: removePlaylistDialog.open()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? errorRow.implicitHeight + 18 : 0
                visible: music.errorMessage.length > 0
                radius: AppTheme.smallRadius
                color: AppTheme.withAlpha(AppTheme.destructive, 0.13)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.destructive, 0.45)

                RowLayout {
                    id: errorRow
                    anchors.fill: parent
                    anchors.margins: 9

                    Label {
                        text: "!"
                        color: AppTheme.destructive
                        font.weight: Font.Bold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: music.errorMessage
                        color: AppTheme.text
                        wrapMode: Text.WordWrap
                    }
                    ToolButton {
                        text: "×"
                        flat: true
                        Accessible.name: qsTr("Dismiss error")
                        onClicked: music.clearError()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 42 : 0
                visible: root.statusMessage.length > 0
                radius: AppTheme.smallRadius
                color: AppTheme.withAlpha(AppTheme.positive, 0.13)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.positive, 0.38)

                Label {
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.statusMessage
                    color: AppTheme.text
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? 56 : 0
                visible: music.transcoding
                radius: AppTheme.smallRadius
                color: AppTheme.withAlpha(AppTheme.accent, 0.11)
                border.width: 1
                border.color: AppTheme.withAlpha(AppTheme.accent, 0.35)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 10

                    Label {
                        text: qsTr("Converting audio")
                        color: AppTheme.text
                        font.weight: Font.DemiBold
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: music.transcodeProgress
                    }
                    Label {
                        text: Math.round(music.transcodeProgress * 100) + "%"
                        color: AppTheme.mutedText
                    }
                    Button {
                        text: qsTr("Cancel")
                        onClicked: music.cancelTranscode()
                    }
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 8

                contentItem: StackLayout {
                    currentIndex: root.contentIndex

                    TrackListView {
                        musicController: music
                        trackModel: music.libraryModel
                        contextMode: "library"
                        emptyTitle: music.libraryFolders.length === 0
                            ? qsTr("Your library is empty")
                            : qsTr("No matching tracks")
                        emptyDescription: music.libraryFolders.length === 0
                            ? qsTr("Add a local music folder to start building your library.")
                            : qsTr("Try a different search or rescan the library.")
                        onAddToPlaylistRequested: trackId => root.requestPlaylistFor(trackId)
                        onTranscodeRequested: (trackId, trackTitle) =>
                            root.requestTranscode(trackId, trackTitle)
                    }

                    MusicGroupGrid {
                        groupModel: music.albums
                        groupKind: "album"
                        emptyTitle: qsTr("No albums yet")
                        onOpenRequested: (name, subtitle, filterValue) =>
                            root.openAlbum(name, subtitle, filterValue)
                        onPlayRequested: filterValue => music.playAlbum(filterValue)
                    }

                    MusicGroupGrid {
                        groupModel: music.artists
                        groupKind: "artist"
                        emptyTitle: qsTr("No artists yet")
                        onOpenRequested: (name, subtitle, filterValue) =>
                            root.openArtist(name, filterValue)
                        onPlayRequested: filterValue => music.playArtist(filterValue)
                    }

                    TrackListView {
                        musicController: music
                        trackModel: music.queueModel
                        contextMode: "queue"
                        emptyTitle: qsTr("The queue is empty")
                        emptyDescription: qsTr("Add tracks from your library to create a play queue.")
                        onAddToPlaylistRequested: trackId => root.requestPlaylistFor(trackId)
                        onTranscodeRequested: (trackId, trackTitle) =>
                            root.requestTranscode(trackId, trackTitle)
                    }

                    TrackListView {
                        musicController: music
                        trackModel: music.playlistTracksModel
                        contextMode: "playlist"
                        playlistId: root.selectedPlaylistId
                        emptyTitle: qsTr("This playlist is empty")
                        emptyDescription: qsTr("Use a track's action menu to add music here.")
                        onAddToPlaylistRequested: trackId => root.requestPlaylistFor(trackId)
                        onTranscodeRequested: (trackId, trackTitle) =>
                            root.requestTranscode(trackId, trackTitle)
                    }

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Indexed folders")
                                    color: AppTheme.text
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }
                                Button {
                                    text: qsTr("Add folder")
                                    highlighted: true
                                    onClicked: folderDialog.open()
                                }
                                Button {
                                    text: qsTr("Rescan")
                                    enabled: !music.scanning
                                    onClicked: music.rescanLibrary()
                                }
                            }

                            KosEmptyState {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: music.libraryFolders.length === 0
                                symbol: "▱"
                                title: qsTr("No music folders")
                                description: qsTr("KOS Music indexes supported audio files without moving or modifying them.")
                                actionText: qsTr("Choose a folder")
                                onActionTriggered: folderDialog.open()
                            }

                            ListView {
                                id: folderList
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: music.libraryFolders.length > 0
                                model: music.libraryFolders
                                spacing: 8
                                clip: true
                                ScrollBar.vertical: ScrollBar {}

                                delegate: Rectangle {
                                    id: folderDelegate
                                    required property string modelData

                                    width: folderList.width
                                    height: 64
                                    radius: AppTheme.smallRadius
                                    color: AppTheme.card
                                    border.width: 1
                                    border.color: AppTheme.border

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        Label {
                                            text: "▱"
                                            color: AppTheme.accent
                                            font.pixelSize: 20
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            Label {
                                                Layout.fillWidth: true
                                                text: folderDelegate.modelData.split("/").pop()
                                                color: AppTheme.text
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                text: folderDelegate.modelData
                                                color: AppTheme.mutedText
                                                font.pixelSize: 11
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                        Button {
                                            text: qsTr("Remove")
                                            onClicked: music.removeLibraryFolder(
                                                           folderDelegate.modelData)
                                        }
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                visible: music.scanWarnings.length > 0
                                text: qsTr("Last scan warning: %1").arg(
                                          music.scanWarnings[music.scanWarnings.length - 1])
                                color: AppTheme.warning
                                wrapMode: Text.WordWrap
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            KosCard {
                Layout.fillWidth: true
                Layout.preferredHeight: 116
                padding: 12

                contentItem: ColumnLayout {
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Artwork {
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 58
                            source: music.currentArtworkUrl
                            title: music.currentTitle
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: music.currentTrackId >= 0
                                    ? music.currentTitle : qsTr("Nothing playing")
                                color: AppTheme.text
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: music.currentTrackId >= 0
                                    ? (music.currentArtist.length > 0
                                       ? music.currentArtist : qsTr("Unknown artist"))
                                    : qsTr("Choose a track from your library")
                                color: AppTheme.mutedText
                                elide: Text.ElideRight
                                font.pixelSize: 12
                            }
                        }

                        ToolButton {
                            text: "⌘"
                            checkable: true
                            checked: music.shuffle
                            enabled: music.queueModel.count > 1
                            Accessible.name: qsTr("Shuffle")
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Shuffle")
                            onClicked: music.shuffle = checked
                        }
                        ToolButton {
                            text: "│‹"
                            enabled: music.canGoPrevious
                            Accessible.name: qsTr("Previous track")
                            onClicked: music.previous()
                        }
                        RoundButton {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            text: music.playbackState === "Playing" ? "Ⅱ" : "▶"
                            highlighted: true
                            enabled: music.currentTrackId >= 0
                            Accessible.name: music.playbackState === "Playing"
                                ? qsTr("Pause") : qsTr("Play")
                            onClicked: music.togglePlayPause()
                        }
                        ToolButton {
                            text: "›│"
                            enabled: music.canGoNext
                            Accessible.name: qsTr("Next track")
                            onClicked: music.next()
                        }
                        ToolButton {
                            text: music.repeatMode === "track" ? "↻¹"
                                : (music.repeatMode === "playlist" ? "↻" : "↪")
                            checkable: true
                            checked: music.repeatMode !== "none"
                            Accessible.name: qsTr("Repeat mode")
                            ToolTip.visible: hovered
                            ToolTip.text: music.repeatMode === "track"
                                ? qsTr("Repeat track")
                                : (music.repeatMode === "playlist"
                                   ? qsTr("Repeat queue") : qsTr("Repeat off"))
                            onClicked: music.repeatMode = music.repeatMode === "none"
                                ? "playlist" : (music.repeatMode === "playlist"
                                                ? "track" : "none")
                        }
                        Label {
                            text: "♩"
                            color: AppTheme.mutedText
                            Accessible.name: qsTr("Volume")
                        }
                        Slider {
                            Layout.preferredWidth: root.width < 1000 ? 72 : 100
                            from: 0
                            to: 1
                            value: music.volume
                            Accessible.name: qsTr("Volume")
                            onMoved: music.volume = value
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Label {
                            Layout.preferredWidth: 40
                            text: root.formatTime(music.positionMs)
                            color: AppTheme.mutedText
                            horizontalAlignment: Text.AlignRight
                            font.pixelSize: 10
                        }
                        Slider {
                            id: positionSlider
                            Layout.fillWidth: true
                            from: 0
                            to: Math.max(1, music.durationMs)
                            value: pressed ? root.pendingSeekMs : music.positionMs
                            enabled: music.seekable
                            Accessible.name: qsTr("Playback position")
                            onPressedChanged: {
                                if (pressed)
                                    root.pendingSeekMs = music.positionMs
                                else
                                    music.seek(Math.round(root.pendingSeekMs))
                            }
                            onMoved: root.pendingSeekMs = value
                        }
                        Label {
                            Layout.preferredWidth: 40
                            text: root.formatTime(music.durationMs)
                            color: AppTheme.mutedText
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
