import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import "../../../Kos/Ui"

// Full MPRIS control surface shown above DockMusicPlayer. It is deliberately a
// PopupWindow: Dock's adaptive height stays untouched while the player gets a
// proper focusable, interactive surface.
PopupWindow {
    id: popup

    property Item anchorItem: null
    property var player: DockMprisService.activePlayer
    readonly property url artworkSource: {
        const revision = DockMprisService.metadataRevision
        return player?.trackArtUrl
            ? player.trackArtUrl : BundledIcons.source("default-cover")
    }
    property bool pointerInside: popupMouse.containsMouse
    readonly property bool monochrome: IconAppearanceService.mode !== "color"

    readonly property real safeLength: player?.lengthSupported
        && player.length > 0 ? player.length : 0
    readonly property real progress: safeLength > 0
        ? Math.max(0, Math.min(1, (player?.position ?? 0) / safeLength)) : 0

    function formatTime(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0))
        const minutes = Math.floor(value / 60)
        const remainder = String(value % 60).padStart(2, "0")
        return minutes + ":" + remainder
    }

    function artworkTint(color, alpha) {
        if (monochrome) {
            const luminance = color.r * 0.2126 + color.g * 0.7152
                + color.b * 0.0722
            return Qt.rgba(luminance, luminance, luminance, alpha)
        }
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function seekAt(x) {
        if (!player?.canSeek || !player?.positionSupported || safeLength <= 0)
            return
        player.position = Math.max(0, Math.min(safeLength, x / progressTrack.width * safeLength))
        player.positionChanged()
    }

    // This popup is independent from Dock's adaptive geometry. Keep it compact
    // enough that the full player does not visually dominate the Dock.
    implicitWidth: 336
    implicitHeight: 196
    color: "transparent"
    grabFocus: false

    anchor {
        item: popup.anchorItem
        edges: Edges.Top
        gravity: Edges.Top
        margins.top: -10
    }

    Timer {
        interval: 250
        repeat: true
        running: popup.visible && popup.player?.isPlaying
        // MPRIS position is intentionally lazy; request refresh only while
        // this full player is visible instead of animating in the idle Dock.
        onTriggered: popup.player.positionChanged()
    }

    // Reuse the same asynchronous cover-art palette as DockMusicPlayer so
    // compact and expanded music controls always belong to one visual system.
    ArtworkColorSource {
        id: artworkPalette
        source: popup.artworkSource
    }

    LiquidGlassPanel {
        id: surface
        anchors.fill: parent
        radius: 18
        cornerExponent: AppearanceTokens.shape.cornerExponent
        // Keep the original Dock glass base. Cover colour is applied by the
        // explicit translucent gradient below, just like DockMusicPlayer.
        baseColor: ThemeService.backgroundColor
        surfaceOpacity: 1.0
        ambientPrimary: popup.artworkTint(artworkPalette.primary, 1.0)
        ambientSecondary: popup.artworkTint(artworkPalette.secondary, 1.0)
        ambientStrength: 0.42
        materialDepth: 1.3
        material: "regular"

        // LiquidGlassSurface deliberately caps ambient pigment, which is too
        // subtle for music artwork. This is the same direct cover-gradient
        // strategy used by DockMusicPlayer, but with lower alpha so the
        // Hyprglass blur remains visible through the full popup. The radius
        // follows the panel, not the literal: with the mask on the panel is
        // square and this rect has to be square too, otherwise its own circular
        // corners stop short of the superelliptical silhouette and leave the
        // panel corners untinted.
        Rectangle {
            anchors.fill: parent
            radius: surface.contentRadius
            color: "transparent"
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: popup.artworkTint(artworkPalette.primary, 0.38)
                }
                GradientStop {
                    position: 0.52
                    color: popup.artworkTint(artworkPalette.secondary, 0.28)
                }
                GradientStop {
                    position: 1.0
                    color: popup.artworkTint(artworkPalette.primary, 0.16)
                }
            }
        }

        Row {
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 12
            }
            height: 72
            spacing: 11

            Rectangle {
                width: 72
                height: 72
                radius: 5
                color: Qt.rgba(0, 0, 0, 0.18)
                // Rectangle.clip only clips to its rectangular bounds. This
                // follows the working compact-player pattern: the Image owns
                // the effect and remains visible, while a rendered mask gives
                // its pixels a real 5px rounded corner.
                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: popup.artworkSource
                    sourceSize.width: Math.max(1, Math.ceil(width * 2))
                    sourceSize.height: Math.max(1, Math.ceil(height * 2))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    smooth: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: coverMask
                        saturation: popup.monochrome ? -1.0 : 0.0
                    }
                }
                Rectangle {
                    id: coverMask
                    anchors.fill: parent
                    radius: 5
                    visible: false
                    layer.enabled: true
                }
            }

            Column {
                width: parent.width - 83
                anchors.verticalCenter: parent.verticalCenter
                // Keep all four metadata rows within the 72px artwork height
                // so anchors.verticalCenter can centre the whole group rather
                // than centring an overflowing column.
                spacing: 4

                Text {
                    width: parent.width
                    text: popup.player?.trackTitle || "未播放曲目"
                    color: ThemeService.foregroundColor
                    elide: Text.ElideRight
                    font {
                        pixelSize: 16
                        weight: Font.Bold
                    }
                }
                Text {
                    width: parent.width
                    text: popup.player?.trackArtist || "未知艺术家"
                    color: ThemeService.foregroundColor
                    opacity: 0.72
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }
                Text {
                    width: parent.width
                    text: DockMprisService.playbackStatus || popup.player?.trackAlbum || popup.player?.identity || "MPRIS Player"
                    color: ThemeService.foregroundColor
                    opacity: 0.48
                    elide: Text.ElideRight
                    font.pixelSize: 11
                }

                // Keep only the compact Dynamic Island-style activity cue;
                // the track metadata above already communicates the context.
                Item {
                    width: parent.width
                    // The waveform itself remains 22px high, but is centred
                    // over this compact allocation and no longer pushes the
                    // title / artist block toward the top edge.
                    height: 10
                    Item {
                        width: 38
                        height: 22
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        visible: popup.player?.isPlaying ?? false
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.44)
                        }
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                required property int index
                                readonly property real quietHeight: 5 + (index % 2)
                                readonly property real loudHeight: 13 + ((index * 5) % 7)
                                width: 3
                                height: quietHeight
                                x: 8 + index * 7
                                anchors.verticalCenter: parent.verticalCenter
                                radius: width / 2
                                // Neutral white keeps this tiny activity cue
                                // legible without competing with cover colours.
                                color: "white"
                                opacity: 0.96

                                SequentialAnimation on height {
                                    running: popup.visible && (popup.player?.isPlaying ?? false)
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 85 }
                                    NumberAnimation { to: loudHeight; duration: 220; easing.type: Easing.OutCubic }
                                    NumberAnimation { to: quietHeight; duration: 260; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: progressTrack
            anchors {
                top: parent.top
                topMargin: 96
                left: parent.left
                right: parent.right
                margins: 12
            }
            // A compact hit area keeps the visible rail close to timestamps
            // without making seeking harder than the visual design suggests.
            height: 14

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 5
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.18)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * popup.progress
                height: 5
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.76)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(parent.width - width,
                    parent.width * popup.progress - width / 2))
                width: 11
                height: 11
                radius: width / 2
                color: ThemeService.foregroundColor
                visible: !!popup.player?.canSeek && popup.safeLength > 0
            }
            MouseArea {
                anchors.fill: parent
                enabled: !!popup.player?.canSeek && popup.safeLength > 0
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: popup.seekAt(mouse.x)
                onPositionChanged: {
                    if (pressed)
                        popup.seekAt(mouse.x)
                }
            }
        }

        Item {
            anchors {
                top: progressTrack.bottom
                left: parent.left
                right: parent.right
                margins: 12
            }
            height: 14
            Text {
                anchors.left: parent.left
                text: popup.formatTime(popup.player?.position ?? 0)
                color: ThemeService.foregroundColor
                opacity: 0.62
                font.pixelSize: 10
            }
            Text {
                anchors.right: parent.right
                text: popup.safeLength > 0 ? popup.formatTime(popup.safeLength) : "--:--"
                color: ThemeService.foregroundColor
                opacity: 0.62
                font.pixelSize: 10
            }
        }

        // Desktop lyric visibility is independent of the app lyric preference.
        MediaControlButton {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 21 }
            width: 32; height: 32
            iconName: "media-lyrics"
            text: qsTr("桌面歌词")
            checkable: true
            checked: ConfigService.desktopLyricsEnabled
            glassInk: ThemeService.foregroundColor
            onClicked: ConfigService.updateDesktopLyricsEnabled(!ConfigService.desktopLyricsEnabled)
        }

        // 32px side controls and the 38px play control share one centre line.
        Item {
            width: 150
            height: 38
            anchors {
                bottom: parent.bottom
                // Raise the control strip slightly so it reads as one compact
                // playback group with the timeline and timestamps above.
                bottomMargin: 20
                horizontalCenter: parent.horizontalCenter
            }

            MusicButton {
                x: 9.5
                anchors.verticalCenter: parent.verticalCenter
                iconName: "media-previous"
                text: qsTr("上一首")
                enabled: popup.player?.canGoPrevious ?? false
                onClicked: DockMprisService.previous()
            }
            MusicButton {
                anchors.centerIn: parent
                primary: true
                iconName: popup.player?.isPlaying ? "media-pause" : "media-play"
                text: popup.player?.isPlaying ? qsTr("暂停") : qsTr("播放")
                busy: DockMprisService.loading
                enabled: popup.player?.canTogglePlaying ?? false
                onClicked: DockMprisService.togglePlayPause()
            }
            MusicButton {
                x: 109.5
                anchors.verticalCenter: parent.verticalCenter
                iconName: "media-next"
                text: qsTr("下一首")
                enabled: popup.player?.canGoNext ?? false
                onClicked: DockMprisService.next()
            }
        }
    }

    component MusicButton: MediaControlButton {
        width: primary ? 38 : 32
        height: width
        glassInk: ThemeService.foregroundColor
    }

    MouseArea {
        id: popupMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    BackgroundEffect.blurRegion: popup.visible ? surface.blurRegion : null
}
