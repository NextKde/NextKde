import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

// Full MPRIS control surface shown above DockMusicPlayer. It is deliberately a
// PopupWindow: Dock's adaptive height stays untouched while the player gets a
// proper focusable, interactive surface.
PopupWindow {
    id: popup

    property Item anchorItem: null
    property var player: DockMprisService.activePlayer
    readonly property url artworkSource: {
        const revision = DockMprisService.metadataRevision
        return player?.trackArtUrl ? player.trackArtUrl : Qt.resolvedUrl("../../assets/defaultCover.png")
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
    ArtworkPalette {
        id: artworkPalette
        source: popup.artworkSource
    }

    LiquidGlassSurface {
        id: surface
        anchors.fill: parent
        radius: 18
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
        // Hyprglass blur remains visible through the full popup.
        Rectangle {
            anchors.fill: parent
            radius: surface.radius
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
                    text: popup.player?.trackAlbum || popup.player?.identity || "MPRIS Player"
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

        // Use a fixed centre line instead of Row's top-aligned children: the
        // 31px side controls and 38px play control now share one true axis.
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
                symbol: "⏮"
                enabled: popup.player?.canGoPrevious ?? false
                onTriggered: DockMprisService.previous()
            }
            MusicButton {
                anchors.centerIn: parent
                primary: true
                symbol: popup.player?.isPlaying ? "⏸" : "▶"
                enabled: popup.player?.canTogglePlaying ?? false
                onTriggered: DockMprisService.togglePlayPause()
            }
            MusicButton {
                x: 109.5
                anchors.verticalCenter: parent.verticalCenter
                symbol: "⏭"
                enabled: popup.player?.canGoNext ?? false
                onTriggered: DockMprisService.next()
            }
        }
    }

    component MusicButton: Item {
        id: button
        property string symbol: ""
        property bool primary: false
        property bool enabled: true
        signal triggered
        width: primary ? 38 : 31
        height: width
        // MPRIS may report that a track cannot go backward/forward. Keep
        // those buttons non-clickable, but never fade them so far that the
        // control layout becomes unreadable.
        opacity: enabled ? 1.0 : 0.66
        scale: mouse.pressed ? 0.90 : (mouse.containsMouse ? 1.07 : 1.0)
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            // Controls stay neutral glass. Cover colours belong to the
            // complete player surface, not isolated button colour chips.
            color: button.primary ? Qt.rgba(1, 1, 1, 0.23) : Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.34)
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: button.symbol === "▶" ? 1 : 0
                text: button.symbol
                color: ThemeService.foregroundColor
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.30)
                font.pixelSize: button.primary ? 18 : 14
            }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: button.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.triggered()
        }
    }

    MouseArea {
        id: popupMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    BackgroundEffect.blurRegion: popup.visible ? musicPopupBlurHolder : null

    Region {
        id: musicPopupBlurHolder
        RoundedBlurRegion {
            item: surface
            radius: surface.radius
        }
    }
}
