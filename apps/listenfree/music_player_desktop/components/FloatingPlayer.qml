pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
    }
    objectName: "floatingPlayer"

    property bool collapsed: false
    property bool artworkInTransition: false
    property bool surfaceInTransition: false
    property Item backdrop: null
    // Explicit screenshot preview only; user interaction never pins the popup.
    property bool volumePreview: false
    property bool playing: true
    property string playbackMode: "listLoop"
    property bool favorite: false
    property bool darkMode: false
    readonly property color glassTint: darkMode ? "#20262c" : "#f2f4f6"
    readonly property real glassTintStrength: darkMode ? .08 : .10
    readonly property real glassBlur: 16
    property bool reducedMotion: false
    property int volumeLevel: 2
    property real progressValue: 0.23
    // Playback times use milliseconds to match PlayerController's public API.
    // Keep progressValue separately so seeking remains a normalized 0...1 signal.
    property real positionMs: 51000
    property real durationMs: 236000
    property bool live: false
    property real volumeValue: 0.68
    property color accentColor: AppTheme.accent
    property string trackTitle: "world étude"
    property string trackArtist: qsTr("豊崎愛生")
    property string trackAlbum: "world Étude"
    property alias artworkSource: cover.source
    property real expandedWidth: 1173
    property real collapsedWidth: 166
    readonly property real cornerRadius: collapsed ? 31 : AppTheme.expandedPlayerCornerRadius

    // AppShell reads these values for the island -> NowPlaying cover morph.
    // They must always describe the actual on-screen cover geometry.
    readonly property real artworkLocalX: collapsed ? 10 : 14
    readonly property real artworkSize: collapsed ? 46 : 52
    readonly property real artworkLocalY: (height - artworkSize) / 2
    readonly property color primaryText: AppTheme.canvasText
    readonly property color secondaryText: AppTheme.canvasSecondary
    readonly property string currentTimeText: formatTime(positionMs)
    readonly property string remainingTimeText: "-" + formatTime(Math.max(0, durationMs - positionMs))

    function adjustVolume(wheel) {
        const delta = wheel.angleDelta.y || wheel.pixelDelta.y
        if (delta) root.volumeChangedByUser(Math.max(0, Math.min(1, root.volumeValue + (delta > 0 ? .04 : -.04))))
        wheel.accepted = true
    }

    function formatTime(milliseconds) {
        const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000))
        const minutes = Math.floor(totalSeconds / 60)
        const seconds = totalSeconds % 60
        return minutes.toString().padStart(2, "0") + ":"
                + seconds.toString().padStart(2, "0")
    }

    signal coverActivated
    signal modeToggleRequested
    signal previousRequested
    signal playPauseRequested
    signal nextRequested
    signal queueRequested
    signal favoriteRequested
    signal progressChangedByUser(real value)
    signal volumeChangedByUser(real value)
    signal muteToggleRequested()
    signal cycleModeRequested()
    signal endlessModeRequested()

    width: collapsed ? collapsedWidth : expandedWidth
    height: collapsed ? 62 : 80

    Behavior on width {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : AppTheme.duration(280)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
        }
    }
    Behavior on height {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : AppTheme.duration(280)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
        }
    }

    GlassSurface {
        objectName: "floatingGlassMaterial"
        visible: !root.surfaceInTransition
        blockInput: true
        anchors.fill: parent
        cornerRadius: root.cornerRadius
        backdrop: root.backdrop
        opaqueBackdropBase: false
        backdropBlur: root.glassBlur
        frosted: true
        tint: root.glassTint
        tintStrength: root.glassTintStrength
        shadowOpacity: .08

        Behavior on cornerRadius {
            NumberAnimation {
                duration: root.reducedMotion ? 0 : AppTheme.duration(280)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.77, 0, 0.175, 1, 1, 1]
            }
        }
    }

    CoverArt {
        id: cover
        objectName: "floatingArtwork"
        opacity: root.artworkInTransition ? 0 : 1
        x: root.artworkLocalX
        y: root.artworkLocalY
        width: root.artworkSize
        height: width
        sourcePixelSize: 256
        property real discAngle: 0
        rotation: root.collapsed && !root.artworkInTransition ? discAngle : 0
        NumberAnimation on discAngle {
            from: 0; to: 360
            duration: 30000
            loops: Animation.Infinite
            running: root.collapsed && root.visible && !root.artworkInTransition && !root.reducedMotion
            paused: running && !root.playing
        }
        cornerRadius: root.collapsed ? root.artworkSize / 2 : 11
        showShadow: !root.collapsed

        Behavior on x { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(280); easing.type: Easing.InOutCubic } }
        Behavior on y { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(280); easing.type: Easing.InOutCubic } }
        Behavior on width { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(280); easing.type: Easing.InOutCubic } }
        Behavior on cornerRadius { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(280); easing.type: Easing.InOutCubic } }
    }

    MouseArea {
        objectName: "floatingArtworkHitTarget"
        x: cover.x
        y: cover.y
        width: cover.width
        height: cover.height
        cursorShape: Qt.PointingHandCursor
        onClicked: root.coverActivated()
    }

    Column {
        id: trackInfo
        visible: opacity > .01
        x: 94
        y: 15
        width: Math.min(270, root.width / 2 - 190)
        spacing: 4
        opacity: root.collapsed ? 0 : 1

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }

        Text {
            width: parent.width
            text: root.trackTitle
            color: root.primaryText
            font.family: AppTheme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: root.trackArtist + (root.trackAlbum.length ? " / " + root.trackAlbum : "")
            color: root.secondaryText
            font.family: AppTheme.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    Row {
        id: transport
        visible: opacity > .01
        x: (root.width - width) / 2
        y: 10
        spacing: 12
        opacity: root.collapsed ? 0 : 1

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }

        RoundIconButton {
            objectName: "floatingPreviousButton"
            raisedSurface: true
            diameter: 34
            kind: "previous"
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            onClicked: root.previousRequested()
        }
        RoundIconButton {
            objectName: "floatingPlayPauseButton"
            raisedSurface: true
            diameter: 34
            kind: root.playing ? "pause" : "play"
            prominent: true
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            accentColor: root.accentColor
            onClicked: root.playPauseRequested()
        }
        RoundIconButton {
            objectName: "floatingNextButton"
            raisedSurface: true
            diameter: 34
            kind: "next"
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            onClicked: root.nextRequested()
        }
    }

    Row {
        id: functionControls
        visible: opacity > .01
        x: root.width - width - 18
        y: 10
        spacing: 12
        opacity: root.collapsed ? 0 : 1

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }

        RoundIconButton {
            objectName: "floatingFavoriteButton"
            raisedSurface: true
            diameter: 34
            kind: root.favorite ? "heartFilled" : "heart"
            glyphColor: root.favorite ? root.accentColor : root.darkMode ? "#eef2f4" : "#46545f"
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            onClicked: root.favoriteRequested()
        }

        RoundIconButton {
            objectName: "floatingModeButton"
            raisedSurface: true
            diameter: 34
            kind: AppTheme.playbackModeInfo(root.playbackMode).kind
            tooltip: root.playbackMode === "endless" ? qsTr("无尽模式（长按关闭）") : AppTheme.playbackModeInfo(root.playbackMode).label + qsTr("（长按开启无尽模式）")
            holdEnabled: true
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            onClicked: root.cycleModeRequested()
            onLongPressed: root.endlessModeRequested()
        }

        RoundIconButton {
            objectName: "floatingQueueButton"
            raisedSurface: true
            diameter: 34
            kind: "queue"
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            onClicked: root.queueRequested()
        }

        Item {
            id: volumeControl
            width: 34
            height: 34
            readonly property bool expanded: !root.collapsed && (root.volumePreview || volumeCapsuleHover.hovered || volumeSlider.pressed)

            Item {
                id: volumeCapsule
                objectName: "floatingVolumeCapsule"
                // The popup extends above the island. Keep its hit area in the
                // full canvas so moving onto the slider does not end hover.
                parent: root.parent
                z: root.z + 1
                x: root.x + functionControls.x + volumeControl.x
                y: root.y + functionControls.y + volumeControl.y + volumeControl.height - height
                visible: root.visible && functionControls.visible && !root.collapsed
                opacity: root.opacity * functionControls.opacity
                width: 34
                height: volumeControl.expanded ? 144 : 34

                Behavior on height {
                    NumberAnimation {
                        duration: root.reducedMotion ? 0 : AppTheme.duration(220)
                        easing.type: Easing.OutCubic
                    }
                }

                GlassSurface {
                    objectName: "floatingVolumeMaterial"
                    anchors.fill: parent
                    blockInput: true
                    cornerRadius: 17
                    tint: volumeButton.surfaceColor
                    edgeColor: volumeButton.raisedEdgeColor
                    softShadow: true
                    shadowOpacity: volumeButton.raisedShadowOpacity
                    shadowOffset: volumeButton.raisedShadowOffset
                }

                Text {
                    objectName: "floatingVolumeValue"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 9
                    text: Math.round(root.volumeValue * 100)
                    color: volumeButton.glyphColor
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 11
                    visible: volumeControl.expanded
                }
                ProgressBar {
                    id: volumeSlider
                    objectName: "floatingVolumeSlider"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 32
                    width: 18
                    height: Math.max(0, parent.height - 74)
                    opacity: volumeControl.expanded ? 1 : 0
                    interactive: opacity > .5
                    darkMode: root.darkMode
                    reducedMotion: root.reducedMotion
                    value: root.volumeValue
                    trackColor: root.darkMode ? "#59636a" : "#526b7479"
                    fillColor: volumeButton.glyphColor
                    handleColor: root.darkMode ? "#f4f7f8" : "#596975"
                    orientation: Qt.Vertical
                    onValueChangedByUser: function(value) {
                        root.volumeChangedByUser(value)
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(170); easing.type: Easing.OutCubic }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true
                    onWheel: wheel => root.adjustVolume(wheel)
                }

                HoverHandler { id: volumeCapsuleHover }

                RoundIconButton {
                    id: volumeButton
                    objectName: "floatingVolumeButton"
                    x: 0
                    y: parent.height - 34
                    diameter: 34
                    kind: "volume"
                    raisedSurface: true
                    // The capsule supplies this same surface, even when closed.
                    transparentSurface: true
                    darkMode: root.darkMode
                    reducedMotion: root.reducedMotion
                    glyphColor: root.darkMode ? "#eef2f4" : "#495158"
                    volumeLevel: root.volumeValue <= 0 ? 0 : Math.max(1, Math.round(root.volumeValue * 3))
                    Accessible.name: root.volumeValue > 0 ? qsTr("静音") : qsTr("恢复音量")
                    onWheelScrolled: wheel => root.adjustVolume(wheel)
                    onClicked: root.muteToggleRequested()
                }
            }
        }

        RoundIconButton {
            objectName: "floatingCollapseButton"
            transparentSurface: false
            raisedSurface: true
            diameter: 34
            kind: "chevronDown"
            glyphRotation: 90
            darkMode: root.darkMode
            reducedMotion: root.reducedMotion
            onClicked: root.modeToggleRequested()
        }
    }

    RoundIconButton {
        objectName: "floatingCollapsedPlayPauseButton"
        raisedSurface: true
        visible: opacity > .01
        x: 66
        y: 10
        diameter: 42
        kind: root.playing ? "pause" : "play"
        prominent: true
        darkMode: root.darkMode
        reducedMotion: root.reducedMotion
        accentColor: root.accentColor
        opacity: root.collapsed ? 1 : 0
        onClicked: root.playPauseRequested()

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }
    }

    RoundIconButton {
        objectName: "floatingExpandButton"
        transparentSurface: false
        raisedSurface: true
        visible: opacity > .01
        x: 120
        y: 13
        diameter: 36
        kind: "chevronDown"
        glyphRotation: -90
        darkMode: root.darkMode
        reducedMotion: root.reducedMotion
        opacity: root.collapsed ? 1 : 0
        onClicked: root.modeToggleRequested()

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }
    }

    Text {
        id: currentTimeLabel
        objectName: "floatingCurrentTime"
        visible: !root.live && opacity > .01
        x: 94
        y: 60
        width: 42
        height: 18
        opacity: root.collapsed ? 0 : 1
        text: root.currentTimeText
        color: root.secondaryText
        font.family: AppTheme.fontFamily
        font.pixelSize: 10
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }
    }

    ProgressBar {
        objectName: "floatingProgressBar"
        commitOnRelease: true
        compactHandle: true
        visible: !root.live && opacity > .01
        interactive: !root.live
        x: currentTimeLabel.x + currentTimeLabel.width + 8
        y: 64
        width: remainingTimeLabel.x - x - 8
        height: 14
        opacity: root.collapsed ? 0 : 1
        value: root.progressValue
        darkMode: root.darkMode
        reducedMotion: root.reducedMotion
        trackColor: root.darkMode ? "#4bffffff" : "#3e6b7479"
        fillColor: root.accentColor
        handleColor: root.darkMode ? "#f5f7f8" : root.accentColor
        onValueChangedByUser: function(value) {
            root.progressChangedByUser(value)
        }

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }
    }

    Text {
        id: remainingTimeLabel
        objectName: "floatingRemainingTime"
        visible: !root.live && opacity > .01
        x: root.width - width - 18
        y: 60
        width: 48
        height: 18
        opacity: root.collapsed ? 0 : 1
        text: root.remainingTimeText
        color: root.secondaryText
        font.family: AppTheme.fontFamily
        font.pixelSize: 10
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter

        Behavior on opacity { NumberAnimation { duration: root.reducedMotion ? 0 : AppTheme.duration(150) } }
    }
    LiveWave {
        objectName: "floatingLiveWave"
        x: 94; y: 62; width: root.width-x-22; height: 16
        visible: root.live && !root.collapsed
        running: root.playing
        reducedMotion: root.reducedMotion
        waveColor: root.secondaryText
    }
}
