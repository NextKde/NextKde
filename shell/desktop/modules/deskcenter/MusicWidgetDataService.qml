import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.platform

// Per-instance R1/R11 adapter for the bundled org.nextkde.example.music
// package. Reads only through WidgetHostService (never hands MediaService or
// WindowService directly to the widget) and forwards widget action requests
// through WidgetHostService.invokeAction().
QtObject {
    id: root

    property string widgetId: "org.nextkde.example.music"
    property string instanceId: widgetId
    property var data: ({
        status: "idle",
        hasPlayer: false,
        playing: false,
        loading: false,
        title: "",
        artist: "",
        album: "",
        artworkUrl: "",
        artworkColors: ({ ready: false, primary: "", secondary: "" }),
        positionSeconds: 0,
        lengthSeconds: 0,
        canPrevious: false,
        canTogglePlayPause: false,
        canNext: false,
        canRaise: false,
        lyric: ""
    })
    property var lastActionResult: null
    readonly property var packageInfo: WidgetPackageService.packages.find(item => item.id === widgetId) ?? null
    readonly property bool available: packageInfo !== null

    function refresh() {
        data = WidgetHostService.mediaNowPlayingSnapshot()
    }

    function dispatchAction(actionName, payload) {
        const result = WidgetHostService.invokeAction(actionName, payload)
        lastActionResult = result
        refresh()
        return result
    }

    Component.onCompleted: {
        WidgetPackageService.refresh()
        refresh()
    }

    property Connections _packageConnections: Connections {
        target: WidgetPackageService
        function onPackagesChanged() { root.refresh() }
    }
    property Connections _hostConnections: Connections {
        target: WidgetHostService
        function onMediaArtworkRevisionChanged() { root.refresh() }
    }
    property Connections _mediaConnections: Connections {
        target: MediaService
        function onActivePlayerChanged() { root.refresh() }
        function onMetadataRevisionChanged() { root.refresh() }
        function onHasPlayingPlayerChanged() { root.refresh() }
    }
    property Connections _playerConnections: Connections {
        target: MediaService.activePlayer
        ignoreUnknownSignals: true
        function onIsPlayingChanged() { root.refresh() }
        function onPlaybackStateChanged() { root.refresh() }
        function onTrackTitleChanged() { root.refresh() }
        function onTrackArtistChanged() { root.refresh() }
        function onTrackArtUrlChanged() { root.refresh() }
    }
    property Timer _positionTick: Timer {
        interval: 1000
        repeat: true
        running: root.available && root.data.status === "ready" && root.data.playing
        onTriggered: {
            if (MediaService.activePlayer && MediaService.activePlayer.positionSupported)
                MediaService.activePlayer.positionChanged()
            root.refresh()
        }
    }
}
