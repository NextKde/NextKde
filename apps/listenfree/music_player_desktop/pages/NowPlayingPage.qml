pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "../components"

Item {
    id: page
    objectName: "nowPlayingPage"

    property var lyrics: []
    property bool live: false
    property bool radioContent: live
    property var comments: null
    property string trackIdentity: ""
    onTrackIdentityChanged: { if (commentsOpen) commentsRequested(false) }
    property bool commentsAvailable: false
    property bool neteaseComments: false
    property bool artworkInTransition: false
    property bool commentsBusy: false
    property string commentsError: ""
    signal commentsRequested(bool more)
    onCommentsOpenChanged: if (commentsOpen) commentsRequested(false)
    property var settingsStore: null
    function setting(key, fallback) {
        if (!settingsStore) return fallback
        const revision = settingsStore.revision
        return settingsStore.value(key, fallback)
    }
    property var hostWindow
    property bool immersiveActive: false
    onImmersiveActiveChanged: {
        if (immersiveActive) forceActiveFocus()
        else if (immersiveFullScreen && hostWindow && hostWindow.visibility === Window.FullScreen) toggleFullScreen()
    }
    property bool immersiveFullScreen: false
    property var immersiveService: null
    property var playerController: null
    property var track: ({})
    readonly property bool overflowStyle: setting("nowPlaying.playerStyle", "Classic") === "Overflow"
    property bool overflowControlsOpen: false
    property bool pointerInControls: false
    property int preImmersiveVisibility: Window.Windowed
    function toggleImmersive() {
        immersiveActive = !immersiveActive
        commentsOpen = false
    }
    function toggleFullScreen() {
        if (!hostWindow) return
        if (hostWindow.visibility === Window.FullScreen) {
            immersiveFullScreen = false
            if (preImmersiveVisibility === Window.Maximized) hostWindow.showMaximized()
            else hostWindow.showNormal()
        } else {
            preImmersiveVisibility = hostWindow.visibility
            immersiveFullScreen = true
            hostWindow.showFullScreen()
        }
    }
    readonly property bool controlsShown: !overflowStyle || overflowControlsOpen || progressBar.pressed || volumeSlider.pressed
    property real controlsOpacity: controlsShown ? 1 : 0
    Behavior on controlsOpacity { NumberAnimation { duration: page.reducedMotion ? 0 : AppTheme.duration(180) } }
    onOverflowStyleChanged: { overflowControlsOpen = false; controlsHideTimer.stop() }
    function scheduleControlsHide() {
        if (pointerInControls || progressBar.pressed || volumeSlider.pressed) controlsHideTimer.stop()
        else controlsHideTimer.restart()
    }
    function finishControlInteraction(control, x, y) {
        // Hover delivery can pause during an exclusive slider grab. Use the
        // actual release point so releasing outside also hides without a move.
        const point = control.mapToItem(bottomHotzone, x, y)
        pointerInControls = point.x >= 0 && point.x <= bottomHotzone.width && point.y >= 0 && point.y <= bottomHotzone.height
        Qt.callLater(scheduleControlsHide)
    }
    function updateBottomHover() {
        if (progressBar.pressed || volumeSlider.pressed) return
        const point = bottomHover.point.position
        pointerInControls = bottomHover.hovered && point.x >= 0 && point.x <= bottomHotzone.width
            && point.y >= 0 && point.y <= bottomHotzone.height
            && (overflowControlsOpen || point.y >= bottomHotzone.height - 21)
        if (pointerInControls) { controlsHideTimer.stop(); overflowControlsOpen = true }
        else scheduleControlsHide()
    }
    Timer {
        id: controlsHideTimer
        interval: 650
        onTriggered: if (!page.pointerInControls && !progressBar.pressed && !volumeSlider.pressed) page.overflowControlsOpen = false
    }
    property int currentLine: 2
    property bool darkMode: false
    property bool reducedMotion: false
    property bool mixing: false
    property bool playing: true
    property real progressValue: 0.23
    property real volumeValue: 0.68
    property real positionMs: 51000
    property real durationMs: 236000
    property string trackTitle: "world étude"
    property string trackArtist: qsTr("豊崎愛生")
    property string trackAlbum: "world Étude / アルタイル"
    property string playbackMode: "listLoop"
    property bool localTrack: false
    signal cycleModeRequested
    signal endlessModeRequested
    signal equalizerRequested
    signal informationRequested
    signal downloadRequested
    signal favoriteRequested(var anchorItem)
    signal lyricsMatchRequested
    property url motionSource: ""
    property url artworkSource: Qt.resolvedUrl("../assets/album_Cover_2@2x.png")
    property bool commentsOpen: false
    property string commentSortMode: "latest"
    property bool immersiveNoticeOpen: false
    onImmersiveNoticeOpenChanged: if (immersiveNoticeOpen) { immersiveActive = true; immersiveNoticeOpen = false }
    property alias lyricAlignmentMode: lyricsPanel.alignmentMode
    property alias lyricCurrentLinePosition: lyricsPanel.currentLinePosition
    property alias lyricFontSize: lyricsPanel.fontSize
    signal closeRequested
    signal themeToggleRequested
    signal queueRequested
    signal playPauseRequested
    signal previousRequested
    signal nextRequested
    signal playbackModeRequested(string mode)
    signal progressChangedByUser(real value)
    signal volumeChangedByUser(real value)
    signal commentSortRequested(string mode)
    signal lyricSeekRequested(real timeMs, int index)
    signal lyricDisplaySettingRequested(string key, var value)

    // Qt Quick dimensions are logical pixels. Reserve the controls' full height
    // before sizing the square artwork, including on wide, short windows.
    readonly property real controlScale: Math.max(.75, Math.min(1.25, width / 1066, height / 709))
    readonly property real horizontalInset: Math.max(32, Math.min(width * .0825, 144))
    readonly property real contentWidth: Math.max(0, Math.min(width - 2 * horizontalInset, 1600))
    readonly property real contentLeft: (width - contentWidth) / 2
    readonly property real columnGap: Math.max(48, Math.min(width * .06, 112))
    readonly property real leftColumnWidth: Math.max(0, (contentWidth - columnGap) * .41)
    readonly property real topInset: Math.max(48, Math.min(height * .09, 96))
    readonly property real bottomInset: Math.max(62, Math.min(height * .09, 96))
    readonly property real availableHeight: Math.max(0, height - topInset - bottomInset)
    readonly property real controlsHeight: 244 * controlScale
    readonly property real coverSize: Math.max(0, Math.floor(Math.min(leftColumnWidth - 12, availableHeight - controlsHeight)))
    readonly property rect artworkFrame: overflowStyle ? Qt.rect(0, 0, overflowImageHost.width, height) : Qt.rect(musicPanel.x + cover.x, musicPanel.y + cover.y, cover.width, cover.height)

    function formatTime(milliseconds) {
        const totalSeconds = Math.max(0, Math.floor(Number(milliseconds || 0) / 1000))
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0")
    }

    Item {
    anchors.fill: parent
    visible: !page.immersiveActive
    GlobalBackground {
        objectName: "nowPlayingBackground"
        visible: !page.overflowStyle
        settingsStore: page.settingsStore
        immersive: true
        anchors.fill: parent
        artwork: page.overflowStyle ? "" : page.artworkSource
        motionTexture: page.overflowStyle ? null : cover.dynamicFirstFrame
        autoStyle: page.setting("nowPlaying.backgroundStyle", "BlurredArtwork")
        playing: page.playing
    }
    Loader {
        anchors.fill: parent
        active: page.overflowStyle
        sourceComponent: ArtworkBackground {
            artwork: page.artworkSource
            sylvakruAuto: true
            neutralImage: true
            blurRadius: width * .045
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: page.overflowStyle
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#18000000" }
            GradientStop { position: .5; color: "#50000000" }
            GradientStop { position: 1; color: "#d9000000" }
        }
    }
    Item {
        id: overflowImageHost
        width: page.width * .68
        height: page.height
        visible: page.overflowStyle && !(immersiveLoader.item && immersiveLoader.item.visible && immersiveLoader.item.videoVisible)
    }
    Rectangle {
        id: overflowCoverMask
        width: overflowImageHost.width; height: page.height
        visible: false
        layer.enabled: page.overflowStyle
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "white" }
            GradientStop { position: .6; color: "white" }
            GradientStop { position: .8; color: "#aaffffff" }
            GradientStop { position: 1; color: "transparent" }
        }
    }
    // A continuous vignette belongs to the artwork, never to the controls:
    // bright covers keep legible white icons without introducing a bottom panel.
    Rectangle {
        anchors.fill: parent
        visible: page.overflowStyle
        gradient: Gradient {
            GradientStop { position: 0; color: "#80000000" }
            GradientStop { position: .16; color: "transparent" }
            GradientStop { position: .62; color: "transparent" }
            GradientStop { position: 1; color: "#b3000000" }
        }
    }
    // The page is a real input surface, including empty space. Keep this below
    // its controls so lyric context menus and sliders retain their own input.
    MouseArea {
        objectName: "nowPlayingInputBarrier"
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: mouse => { mouse.accepted = true; AppTheme.closePopup() }
        onWheel: wheel => wheel.accepted = true
    }
    MouseArea {
        x: 0; y: 0; width: parent.width - 180; height: 44
        acceptedButtons: Qt.LeftButton
        onPressed: if (page.hostWindow && page.hostWindow.startSystemMove) page.hostWindow.startSystemMove()
    }

    Item {
        id: musicPanel
        x: page.overflowStyle ? 0 : page.contentLeft + (page.leftColumnWidth - width - 12) / 2
        y: page.overflowStyle ? 0 : page.topInset + (page.availableHeight - height) / 2
        width: page.overflowStyle ? page.width : page.coverSize
        height: page.overflowStyle ? page.height : cover.height + page.controlsHeight
        z: page.overflowStyle ? 2 : 0

        CoverArt {
            id: cover
            parent: page.overflowStyle ? overflowImageHost : musicPanel
            objectName: "nowPlayingArtwork"
            opacity: !page.overflowStyle && page.artworkInTransition ? 0 : 1
            width: parent.width
            height: page.overflowStyle ? page.height : width
            artworkTier: page.overflowStyle ? "Hero" : "XLarge"
            cornerRadius: page.overflowStyle ? 0 : 20
            layer.enabled: page.overflowStyle
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: overflowCoverMask
                maskThresholdMin: .5
                maskSpreadAtMin: 1
            }
            source: page.artworkSource
            motionSource: page.immersiveActive ? "" : page.motionSource
            motionPlaying: page.visible && (!page.hostWindow || page.hostWindow.visibility !== Window.Minimized)
        }
        MouseArea {
            objectName: "nowPlayingArtworkHitTarget"
            visible: !page.overflowStyle
            x: cover.x
            y: cover.y
            width: cover.width
            height: cover.height
            cursorShape: Qt.PointingHandCursor
            onClicked: page.closeRequested()
        }

        Item {
            id: titleArea
            visible: !page.overflowStyle
            y: cover.height + 20 * page.controlScale
            width: parent.width + 12
            height: 44 * page.controlScale
            Column {
                anchors.left: parent.left
                anchors.right: page.radioContent ? mediaAction.left : favoriteAction.left
                anchors.rightMargin: 12
                spacing: 2 * page.controlScale
                Text {
                    width: parent.width
                    text: page.trackTitle
                    color: "#fffdfd"
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 22 * page.controlScale
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: page.trackArtist + (page.trackAlbum.length ? " / " + page.trackAlbum : "")
                    color: "#e0dcdd"
                    opacity: .9
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 12 * page.controlScale
                    elide: Text.ElideRight
                }
            }
            RoundIconButton {
                id: favoriteAction
                objectName: "nowPlayingFavoriteButton"
                visible: !page.radioContent
                anchors.right: mediaAction.left
                anchors.rightMargin: 8 * page.controlScale
                anchors.verticalCenter: parent.verticalCenter
                diameter: 32 * page.controlScale
                kind: "star"
                darkMode: true
                tooltip: qsTr("收藏到“我的收藏”")
                onClicked: page.favoriteRequested(favoriteAction)
            }
            RoundIconButton {
                id: mediaAction
                objectName: "nowPlayingMediaAction"
                visible: !page.radioContent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                diameter: 32 * page.controlScale; kind: page.localTrack ? "info" : "download"; darkMode: true
                tooltip: page.localTrack ? qsTr("编辑信息") : qsTr("下载")
                onClicked: page.localTrack ? page.informationRequested() : page.downloadRequested()
            }
        }

        ProgressBar {
            id: progressBar
            commitOnRelease: true
            objectName: "nowPlayingProgressBar"
            compactHandle: true
            y: page.overflowStyle ? parent.height - height : titleArea.y + titleArea.height + 8 * page.controlScale
            width: parent.width
            height: page.overflowStyle ? (page.controlsShown ? 24 : 2) : 16 * page.controlScale
            trackThickness: page.overflowStyle ? (page.controlsShown ? 6 : 2) : 4
            alignToBottom: page.overflowStyle
            showHandle: !page.overflowStyle || page.controlsShown
            interactive: !page.live && (!page.overflowStyle || page.controlsShown)
            onPressedChanged: page.scheduleControlsHide()
            onInteractionEnded: (x, y) => page.finishControlInteraction(progressBar, x, y)
            value: page.progressValue
            trackColor: "#57ffffff"
            fillColor: "#eaffffff"
            handleColor: "white"
            darkMode: page.darkMode
            reducedMotion: page.reducedMotion
            onValueChangedByUser: function(value) { page.progressChangedByUser(value) }
        }
        Item {
            id: timeLabels
            x: page.overflowStyle ? 32 : 0
            y: page.overflowStyle ? parent.height - 34 : progressBar.y + progressBar.height + 2 * page.controlScale
            width: page.overflowStyle ? parent.width - 64 : parent.width
            opacity: page.controlsOpacity
            height: 16 * page.controlScale
            Text { anchors.left: parent.left; text: page.live ? qsTr("直播中") : page.formatTime(page.positionMs); color: "#f2eeee"; font.pixelSize: 12 * page.controlScale }
            Text { anchors.right: parent.right; visible: !page.live; text: "-" + page.formatTime(Math.max(0, page.durationMs - page.positionMs)); color: "#f2eeee"; font.pixelSize: 12 * page.controlScale }
        }

        Text {
            id: mixStatus
            objectName: "nowPlayingMixStatus"
            anchors.horizontalCenter: parent.horizontalCenter
            y: timeLabels.y
            visible: page.mixing && !page.live
            text: qsTr("混音")
            color: "#b7b9be"
            font.family: AppTheme.fontFamily
            font.pixelSize: 11 * page.controlScale
            property real shimmerPhase: 0
            readonly property bool shimmering: visible && page.playing && !page.reducedMotion
                && (!page.hostWindow || page.hostWindow.visibility !== Window.Minimized)
            layer.enabled: shimmering && GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: ShaderEffect {
                property real phase: mixStatus.shimmerPhase
                fragmentShader: "qrc:/shaders/mix-status.frag.qsb"
            }
            NumberAnimation on shimmerPhase {
                from: 0; to: 1; duration: 2400; loops: Animation.Infinite
                running: mixStatus.shimmering
                onRunningChanged: if (!running) mixStatus.shimmerPhase = 0
            }
        }

        Row {
            id: playbackControls
            objectName: "nowPlayingTransport"
            opacity: page.controlsOpacity
            visible: opacity > 0
            enabled: page.controlsShown
            anchors.horizontalCenter: parent.horizontalCenter
            y: page.overflowStyle ? parent.height - height - 38 : timeLabels.y + timeLabels.height + 20 * page.controlScale
            spacing: 10 * page.controlScale
            height: 64 * page.controlScale
            RoundIconButton { objectName: "nowPlayingModeButton"; anchors.verticalCenter: parent.verticalCenter; diameter: 40 * page.controlScale; kind: AppTheme.playbackModeInfo(page.playbackMode).kind; tooltip: page.playbackMode === "endless" ? qsTr("无尽模式（长按关闭）") : AppTheme.playbackModeInfo(page.playbackMode).label + qsTr("（长按开启无尽模式）"); holdEnabled: true; glyphColor: "#f4f1f2"; transparentSurface: true; darkMode: page.darkMode; reducedMotion: page.reducedMotion; onClicked: page.cycleModeRequested(); onLongPressed: page.endlessModeRequested() }
            RoundIconButton { objectName: "nowPlayingPreviousButton"; anchors.verticalCenter: parent.verticalCenter; diameter: 48 * page.controlScale; kind: "previous"; glyphColor: "#f8f8f8"; transparentSurface: true; darkMode: page.darkMode; reducedMotion: page.reducedMotion; onClicked: page.previousRequested() }
            RoundIconButton { objectName: "nowPlayingPlayPauseButton"; anchors.verticalCenter: parent.verticalCenter; diameter: 64 * page.controlScale; kind: page.playing ? "pause" : "play"; glyphColor: "#ffffff"; transparentSurface: true; darkMode: page.darkMode; reducedMotion: page.reducedMotion; onClicked: page.playPauseRequested() }
            RoundIconButton { objectName: "nowPlayingNextButton"; anchors.verticalCenter: parent.verticalCenter; diameter: 48 * page.controlScale; kind: "next"; glyphColor: "#f8f8f8"; transparentSurface: true; darkMode: page.darkMode; reducedMotion: page.reducedMotion; onClicked: page.nextRequested() }
            RoundIconButton { objectName: "nowPlayingEqualizerButton"; anchors.verticalCenter: parent.verticalCenter; diameter: 40 * page.controlScale; kind: "settings"; tooltip: qsTr("音效调节"); glyphColor: "#f4f1f2"; transparentSurface: true; darkMode: page.darkMode; reducedMotion: page.reducedMotion; onClicked: page.equalizerRequested() }
        }

        Row {
            id: volumeControls
            x: page.overflowStyle ? 32 : 0
            y: page.overflowStyle ? parent.height - 76 : playbackControls.y + playbackControls.height + 24 * page.controlScale
            width: page.overflowStyle ? Math.min(200, parent.width * .2) : parent.width
            opacity: page.controlsOpacity
            visible: opacity > 0
            enabled: page.controlsShown
            height: 30 * page.controlScale
            spacing: 14 * page.controlScale
            IconGlyph { id: volumeIcon; width: 20 * page.controlScale; height: width; anchors.verticalCenter: parent.verticalCenter; kind: "volume"; glyphColor: "#f0edef"; volumeLevel: Math.round(page.volumeValue * 3); strokeWidth: 1.35 }
            ProgressBar {
                id: volumeSlider
                onPressedChanged: page.scheduleControlsHide()
                onInteractionEnded: (x, y) => page.finishControlInteraction(volumeSlider, x, y)
                objectName: "nowPlayingVolumeSlider"
                width: parent.width - volumeIcon.width - volumeLabel.width - 2 * parent.spacing
                height: 14 * page.controlScale
                anchors.verticalCenter: parent.verticalCenter
                value: page.volumeValue
                trackColor: "#49ffffff"
                fillColor: "#d9ffffff"
                darkMode: page.darkMode
                reducedMotion: page.reducedMotion
                onValueChangedByUser: function(value) { page.volumeChangedByUser(value) }
            }
            Text { id: volumeLabel; width: 22 * page.controlScale; text: Math.round(page.volumeValue * 100); horizontalAlignment: Text.AlignRight; color: "#f1edef"; font.pixelSize: 12 * page.controlScale; anchors.verticalCenter: parent.verticalCenter }
        }
        RoundIconButton {
            id: overflowFavoriteAction
            objectName: "overflowFavoriteButton"
            visible: !page.radioContent && page.overflowStyle && opacity > 0
            enabled: page.controlsShown
            opacity: page.controlsOpacity
            x: overflowMediaAction.x - width - 10; y: overflowMediaAction.y
            diameter: 32; kind: "star"
            transparentSurface: true; glyphColor: "white"; darkMode: true
            tooltip: qsTr("收藏到“我的收藏”")
            onClicked: page.favoriteRequested(overflowFavoriteAction)
        }
        RoundIconButton {
            id: overflowMediaAction
            objectName: "overflowMediaAction"
            visible: !page.radioContent && page.overflowStyle && opacity > 0
            enabled: page.controlsShown
            opacity: page.controlsOpacity
            x: parent.width - width - overflowUtilityRow.width - 48; y: parent.height - 78
            diameter: 32; kind: page.localTrack ? "info" : "download"
            transparentSurface: true; glyphColor: "white"; darkMode: true
            tooltip: page.localTrack ? qsTr("编辑信息") : qsTr("下载")
            onClicked: page.localTrack ? page.informationRequested() : page.downloadRequested()
        }
    }

    Item {
        objectName: "nowPlayingLyricsRegion"
        z: 1
        visible: !page.immersiveActive || page.commentsOpen
        x: page.overflowStyle ? page.width * .64 : page.contentLeft + page.leftColumnWidth + page.columnGap * .82
        y: page.overflowStyle ? 50 : Math.max(42, page.topInset * .55)
        width: page.overflowStyle ? page.width - x - 62 : page.width - x - 54
        height: page.overflowStyle ? page.height - 105 : page.height - y
        clip: true
    Flipable {
        id: lyricDoor
        objectName: "nowPlayingLyricDoor"
        anchors.fill: parent
        property real angle: page.commentsOpen ? 180 : 0
        transform: Rotation { origin.x: lyricDoor.width / 2; origin.y: lyricDoor.height / 2; axis.x: 0; axis.y: 1; axis.z: 0; angle: lyricDoor.angle }
        Behavior on angle { NumberAnimation { duration: page.reducedMotion ? 0 : AppTheme.duration(280); easing.type: Easing.BezierSpline; easing.bezierCurve: [.23, 1, .32, 1, 1, 1] } }
        front: Item {
            anchors.fill: parent
            clip: true
            enabled: lyricDoor.side === Flipable.Front
            LyricsPanel {
                playing: page.playing
                id: lyricsPanel
                objectName: "nowPlayingLyricsPanel"
                x: 0; y: page.overflowStyle ? 18 : 0
                width: parent.width; height: parent.height - (page.overflowStyle ? 36 : 0)
                lyrics: page.lyrics
                currentLineIndex: page.currentLine
                positionMs: page.positionMs
                wordTimingEnabled: page.setting("lyrics.wordTimingEnabled", true)
                karaokeEnabled: page.setting("lyrics.karaokeEnabled", true)
                darkMode: page.darkMode
                reducedMotion: page.reducedMotion
                artworkBackground: true
                animationActive: page.visible && !page.immersiveActive && lyricDoor.side === Flipable.Front && (!page.hostWindow || page.hostWindow.visibility !== Window.Minimized)
                springEnabled: page.setting("lyrics.springScrollingEnabled", true)
                scaleEnabled: page.setting("lyrics.currentLineScaleEnabled", true)
                inactiveBlurEnabled: page.setting("lyrics.inactiveBlurEnabled", true)
                showTranslation: page.setting("lyrics.showTranslation", true)
                showRomanization: page.setting("lyrics.showRomanization", false)
                secondaryLineOrder: page.setting("lyrics.secondaryLineOrder", "TranslationFirst")
                alignmentMode: page.setting("lyrics.alignment", "Center")
                currentLinePosition: page.setting("lyrics.currentLineAnchor", "Center")
                fontSize: page.setting("lyrics.textSize", 28)
                onSeekRequested: function(timeMs, index) { page.lyricSeekRequested(timeMs, index) }
                onDisplaySettingRequested: function(key, value) { page.lyricDisplaySettingRequested(key, value) }
                onMatchRequested: page.lyricsMatchRequested()
                Connections {
                    target: page
                    function onProgressChangedByUser(value) { lyricsPanel.notifySeek() }
                }
            }
        }
        back: CommentsPanel {
            id: commentsPanel
            title: page.neteaseComments ? qsTr("网易云评论") : qsTr("评论")
            objectName: "nowPlayingCommentsPanel"
            anchors.fill: parent
            enabled: lyricDoor.side === Flipable.Back
            darkMode: page.darkMode
            activeSortMode: page.commentSortMode
            comments: page.comments || []
            busy: page.commentsBusy
            errorMessage: page.commentsError
            onMoreRequested: page.commentsRequested(true)
            onRetryRequested: page.commentsRequested(false)
            onSortModeChanged: function(mode) { page.commentSortMode = mode; page.commentSortRequested(mode) }
        }
    }

    }
    Text {
        objectName: "overflowTrackHeading"
        z: 4
        visible: page.overflowStyle
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8; width: Math.max(0, parent.width - 400); height: 22
        text: page.trackTitle + "  ·  " + page.trackArtist
        color: "#e8e6e3"; font.family: AppTheme.fontFamily; font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    Item {
        id: bottomHotzone
        objectName: "overflowControlsHotzone"
        anchors.bottom: parent.bottom
        width: parent.width
        // Keep the observed surface fixed as controls appear. Moving a hovered
        // item's bounds can synthesize a leave at the bottom window edge.
        height: 130
        z: 3
        HoverHandler {
            id: bottomHover
            enabled: page.overflowStyle && page.visible
            blocking: false
            onHoveredChanged: page.updateBottomHover()
            onPointChanged: page.updateBottomHover()
        }
    }
    Row {
        id: windowControls
        z: 4
        anchors.right: parent.right
        anchors.rightMargin: AppTheme.normalWindowCornerRadius - closeWindowControl.width / 2 - 4
        y: (AppTheme.toolbarHeight - AppTheme.toolbarControlHeight) / 2
        spacing: 10
        HeaderGlyph { objectName: "nowPlayingCloseButton"; kind: "chevronDown"; onClicked: page.closeRequested() }
        HeaderGlyph { objectName: "nowPlayingThemeButton"; kind: page.darkMode ? "moon" : "sun"; onClicked: page.themeToggleRequested() }
        Row {
            id: nowPlayingTrafficCluster
            spacing: 10
            WindowTrafficButton {
                action: "minimize"
                fillColor: "#2fc866"
                revealGlyph: nowPlayingTrafficHover.hovered || Qt.application.arguments.indexOf("nowplaying-traffic-hover") >= 0
                reducedMotion: page.reducedMotion
                onClicked: if (page.hostWindow) page.hostWindow.showMinimized()
            }
            WindowTrafficButton {
                action: "maximize"
                fillColor: "#ffbf18"
                revealGlyph: nowPlayingTrafficHover.hovered || Qt.application.arguments.indexOf("nowplaying-traffic-hover") >= 0
                reducedMotion: page.reducedMotion
                onClicked: if (page.hostWindow) {
                    if (page.hostWindow.visibility === Window.Maximized) page.hostWindow.showNormal()
                    else page.hostWindow.showMaximized()
                }
            }
            WindowTrafficButton {
                id: closeWindowControl
                action: "close"
                fillColor: "#ff5f57"
                revealGlyph: nowPlayingTrafficHover.hovered || Qt.application.arguments.indexOf("nowplaying-traffic-hover") >= 0
                reducedMotion: page.reducedMotion
                onClicked: if (page.hostWindow) page.hostWindow.close()
            }
            HoverHandler { id: nowPlayingTrafficHover }
        }
    }

    Row {
        id: queueRow
        x: 32
        y: parent.height - 50
        spacing: 18
        FooterGlyph {
            id: queueButton
            parent: page.overflowStyle ? overflowUtilityRow : queueRow
            objectName: "nowPlayingQueueButton"; kind: "queue"; onClicked: page.queueRequested()
        }
    }
    Column {
        id: classicUtilityRow
        z: 4
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        spacing: 14
        FooterGlyph {
            id: commentsButton
            parent: page.overflowStyle ? overflowUtilityRow : classicUtilityRow
            objectName: "nowPlayingCommentsButton"
            kind: "comments"
            active: page.commentsOpen
            enabled: page.commentsAvailable
            onClicked: page.commentsOpen = !page.commentsOpen
        }
        FooterGlyph {
            id: immersiveButton
            parent: page.overflowStyle ? overflowUtilityRow : classicUtilityRow
            objectName: "nowPlayingImmersiveButton"
            kind: "immersive"
            active: page.immersiveActive
            onClicked: page.toggleImmersive()
        }
    }
    Item {
        id: overflowUtilityRow
        objectName: "overflowUtilityControls"
        visible: page.overflowStyle && opacity > 0
        enabled: page.controlsShown
        opacity: page.controlsOpacity
        anchors.right: parent.right
        anchors.rightMargin: 24
        y: parent.height - 77; width: 118; height: 30; z: 2
        // Explicit positions keep the requested order after live reparenting.
        states: State {
            when: page.overflowStyle
            PropertyChanges { target: commentsButton; x: 0; y: 0 }
            PropertyChanges { target: immersiveButton; x: 44; y: 0 }
            PropertyChanges { target: queueButton; x: 88; y: 0 }
        }
    }

    } // Normal NowPlaying is replaced by a whole-screen immersive composition.
    Loader {
        id: immersiveLoader
        objectName: "immersiveLoader"
        anchors.fill: parent
        active: page.immersiveActive
        z: 1
        sourceComponent: ImmersiveStage {
            service: page.immersiveService
            playerPage: page
            controller: page.playerController
            track: page.track
            artwork: page.artworkSource
            settingsStore: page.settingsStore
            lyrics: page.lyrics; positionMs: page.positionMs; playing: page.playing
            title: page.trackTitle; artist: page.trackArtist
            exposed: page.visible && !page.commentsOpen && (!page.hostWindow || (page.hostWindow.visible && page.hostWindow.visibility !== Window.Minimized))
            visible: !page.commentsOpen
            reducedMotion: page.reducedMotion
            showTranslation: page.setting("lyrics.showTranslation", true)
            wordTimingEnabled: page.setting("lyrics.wordTimingEnabled", true)
            onSeekRequested: (timeMs, index) => page.lyricSeekRequested(timeMs, index)
            onFullScreenRequested: page.toggleFullScreen()
        }
    }

    component HeaderGlyph: Item {
        property string kind: "globe"
        signal clicked
        width: AppTheme.toolbarControlHeight
        height: AppTheme.toolbarControlHeight
        IconGlyph { anchors.centerIn: parent; width: 22; height: 22; kind: parent.kind; glyphColor: "#e9e6e7"; strokeWidth: 1.2 }
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: parent.clicked() }
    }
    component FooterGlyph: Item {
        property string kind: "queue"
        property bool active: false
        width: 30
        height: 30
        signal clicked
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: parent.kind === "comments" && parent.active ? "#f5f5f7" : footerHover.hovered ? "#18ffffff" : "transparent"
            Behavior on color { ColorAnimation { duration: AppTheme.duration(140) } }
            border.width: 0
            border.color: "#dce0e3"
        }
        IconGlyph {
            anchors.centerIn: parent
            width: 22
            height: 22
            kind: parent.kind
            glyphColor: parent.kind === "comments" && parent.active ? "#686868" : "#eeeeee"
            strokeWidth: 1.45
        }
        HoverHandler { id: footerHover }
        opacity: !enabled ? .25 : footerHover.hovered ? 1 : .88
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: parent.clicked() }
    }
}
