import QtQuick
import QtQuick.Effects
import Quickshell.Services.Mpris
import qs.desktop.modules.common

// ────────────────────────────────────────────────────────────────
// DockMusicPlayer — Music player widget sized in icon-width units.
//
// Binds to DockMprisService.activePlayer reactively.  Two modes:
//   - Compact (iconSize < 36):  album art only with a tiny play/pause overlay
//   - Full (iconSize ≥ 36):     art + track title/artist + prev/play/next buttons
//
// Expand/collapse animation when hasPlayer toggles.
// ────────────────────────────────────────────────────────────────

Item {
    id: widget

    // ── Inputs ──
    property int iconSize: 44
    property int dockHeight: 60
    property int widthUnits: 4

    // ── Derived ──
    readonly property real artSize: Math.min(iconSize, dockHeight - widget.vPadding * 2)
    readonly property int vPadding: Math.round(iconSize * 0.25)
    readonly property bool isCompact: iconSize < 36
    readonly property real backgroundGap: iconSize * 0.1
    readonly property real contentWidth: iconSize * widthUnits
    readonly property bool monochrome: ConfigService.iconMode !== "color"

    // ── Player reference ──
    readonly property var player: DockMprisService.activePlayer
    readonly property url artworkSource: {
        const revision = DockMprisService.metadataRevision
        return player?.trackArtUrl ? player.trackArtUrl : Qt.resolvedUrl("../../assets/defaultCover.png")
    }
    property bool detailsHovered: false
    property bool musicPopupRequested: false

    function artworkTint(color, alpha) {
        if (monochrome) {
            const luminance = color.r * 0.2126 + color.g * 0.7152
                + color.b * 0.0722
            return Qt.rgba(luminance, luminance, luminance, alpha)
        }
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    // The content itself is exactly iconSize high. The outer slot includes
    // the same 0.1*iconSize margin used by active app backgrounds, and this
    // extra width is included by AdaptiveMath during width fitting.
    width: contentWidth + backgroundGap * 2
    height: iconSize

    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    // ── Expand / collapse animation ──
    clip: false
    Behavior on width {
        NumberAnimation {
            duration: DockAnimation.musicExpandDuration
            easing.type: DockAnimation.musicExpandEasing
        }
    }

    // The compact Dock player stays compact. Hover opens an independent
    // PopupWindow above it so detailed controls never affect adaptive sizing.
    HoverHandler {
        id: musicHover
        onHoveredChanged: {
            if (hovered) {
                musicPopupRequested = true
                musicPopupCloseDelay.stop()
                musicPopupOpenDelay.restart()
            } else if (!musicPopup.pointerInside) {
                musicPopupOpenDelay.stop()
                musicPopupCloseDelay.restart()
            }
        }
    }

    Timer {
        id: musicPopupOpenDelay
        interval: 420
        repeat: false
        onTriggered: {
            if (!musicHover.hovered || !widget.player)
                return
            DockModelService.openDockPopup(musicPopup)
        }
    }

    Timer {
        id: musicPopupCloseDelay
        interval: 260
        repeat: false
        onTriggered: {
            if (!musicHover.hovered && !musicPopup.pointerInside)
                musicPopup.visible = false
        }
    }

    DockMusicPopup {
        id: musicPopup
        anchorItem: widget
        player: widget.player
        onPointerInsideChanged: {
            if (pointerInside) {
                musicPopupCloseDelay.stop()
            } else if (!musicHover.hovered) {
                musicPopupCloseDelay.restart()
            }
        }
        onVisibleChanged: {
            if (!visible)
                DockModelService.releaseDockPopup(musicPopup)
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Content
    // ═══════════════════════════════════════════════════════════
    Rectangle {
        id: playerBackground
        anchors.horizontalCenter: parent.horizontalCenter
        y: -widget.backgroundGap
        width: widget.width
        height: widget.iconSize + widget.backgroundGap * 2
        radius: widget.iconSize * 0.35
        color: "transparent"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: widget.artworkTint(artworkPalette.primary, 0.82)
            }
            GradientStop {
                position: 0.52
                color: widget.artworkTint(artworkPalette.secondary, 0.64)
            }
            GradientStop {
                position: 1.0
                color: widget.artworkTint(artworkPalette.primary, 0.38)
            }
        }
        z: -1
    }

    ArtworkPalette {
        id: artworkPalette
        source: widget.artworkSource
    }

    Row {
        id: musicRow
        anchors.centerIn: parent
        spacing: Math.round(widget.iconSize * 0.09)
        height: widget.artSize

        // ── Album art ──
        Rectangle {
            width: widget.artSize
            height: widget.artSize
            radius: 6
            color: ThemeService.dividerColor
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: albumArtMask
                anchors.fill: parent
                radius: 6
                visible: false
                layer.enabled: true
            }

            Image {
                id: albumArt
                anchors.fill: parent
                source: widget.artworkSource
                sourceSize.width: Math.max(1, Math.ceil(width * 2))
                sourceSize.height: Math.max(1, Math.ceil(height * 2))
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectCrop
                smooth: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: albumArtMask
                    // In monochrome Dock mode the cover is part of the Dock's
                    // icon language, not an isolated full-colour artwork tile.
                    saturation: widget.monochrome ? -1.0 : 0.0
                }
            }

            // Play/pause overlay on art (compact mode mostly)
            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: 9
                color: Qt.rgba(0, 0, 0, 0.55)
                visible: widget.isCompact
                Text {
                    anchors.centerIn: parent
                    text: widget.player?.isPlaying ? "⏸" : "▶"
                    color: "white"
                    font.pixelSize: 10
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DockMprisService.togglePlayPause()
                }
            }
        }

        // ── Track info + controls (full mode) ──
        Column {
            anchors.verticalCenter: parent.verticalCenter
            visible: !widget.isCompact
            width: Math.max(0, widget.contentWidth - widget.artSize - musicRow.spacing - widget.vPadding * 2)
            spacing: 1

            // Track title + artist marquee
            Item {
                id: trackViewport
                width: parent.width
                height: Math.max(trackTitle.implicitHeight, trackArtist.implicitHeight)
                clip: true

                Row {
                    id: trackMarquee
                    property real scrollOffset: 0

                    x: width <= trackViewport.width
                        ? (trackViewport.width - width) / 2
                        : scrollOffset
                    height: parent.height
                    spacing: 6

                    Text {
                        id: trackTitle
                        anchors.verticalCenter: parent.verticalCenter
                        text: widget.player?.trackTitle ?? "No Track"
                        color: ThemeService.foregroundColor
                        font.pixelSize: Math.max(12, widget.iconSize * 0.28)
                        font.weight: Font.Bold
                    }

                    Text {
                        id: trackArtist
                        anchors.verticalCenter: parent.verticalCenter
                        text: widget.player?.trackArtist
                            ? "·  " + widget.player.trackArtist
                            : ""
                        color: "#fff"
                        font.pixelSize: Math.max(8, widget.iconSize * 0.19)
                    }

                    SequentialAnimation on scrollOffset {
                        id: trackScroll
                        // Avoid continuous full-scene rendering while the
                        // Dock is idle. Long metadata scrolls on demand.
                        running: widget.detailsHovered
                            && trackMarquee.width > trackViewport.width
                        loops: Animation.Infinite

                        PauseAnimation { duration: 1200 }
                        NumberAnimation {
                            from: 0
                            to: -(trackMarquee.width - trackViewport.width)
                            duration: Math.max(900,
                                (trackMarquee.width - trackViewport.width) * 35)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 800 }
                        PropertyAction { value: 0 }

                        onRunningChanged: {
                            if (!running)
                                trackMarquee.scrollOffset = 0;
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: widget.detailsHovered = containsMouse
                }
            }

            // Playback controls
            Row {
                spacing: Math.round(widget.iconSize * 0.07)
                anchors.horizontalCenter: parent.horizontalCenter

                DockPrevBtn {
                    enabled: widget.player?.canGoPrevious ?? false
                }

                DockPlayBtn {
                    enabled: widget.player !== null
                    isPlaying: widget.player?.isPlaying ?? false
                }

                DockNextBtn {
                    enabled: widget.player?.canGoNext ?? false
                }
            }
        }

        // ── Compact mode: cover + track metadata ───────────────────
        // Keep the artwork's play/pause overlay as the direct control, while
        // using the remaining width for a deliberately small now-playing
        // readout. A long title scrolls by itself because the compact card
        // has no room for the full-mode hover interaction.
        Item {
            id: compactTrackInfo
            visible: widget.isCompact
            width: Math.max(0, widget.contentWidth - widget.artSize
                - musicRow.spacing)
            height: widget.artSize
            anchors.verticalCenter: parent.verticalCenter

            Item {
                id: compactTrackViewport
                anchors.fill: parent
                clip: true

                property real scrollOffset: 0
                readonly property string metadata: {
                    const title = widget.player?.trackTitle ?? "No Track"
                    const artist = widget.player?.trackArtist ?? ""
                    const album = widget.player?.trackAlbum ?? ""
                    return [title, artist, album].filter(function(part) {
                        return part.length > 0
                    }).join(" · ")
                }

                Text {
                    id: compactTrackTitle
                    anchors.verticalCenter: parent.verticalCenter
                    text: compactTrackViewport.metadata
                    color: "white"
                    font {
                        pixelSize: Math.max(8,
                            Math.round(widget.iconSize * 0.25))
                        weight: Font.Bold
                    }
                    // The Row's spacing supplies the breathing room from the
                    // cover. Keep short metadata naturally left-aligned there.
                    x: width <= compactTrackViewport.width
                        ? 0 : compactTrackViewport.scrollOffset
                }

                SequentialAnimation on scrollOffset {
                    id: compactTrackScroll
                    running: widget.isCompact
                        && compactTrackTitle.width > compactTrackViewport.width
                    loops: Animation.Infinite

                    PauseAnimation { duration: 900 }
                    NumberAnimation {
                        from: 0
                        to: -(compactTrackTitle.width
                            - compactTrackViewport.width)
                        duration: Math.max(800,
                            (compactTrackTitle.width
                                - compactTrackViewport.width) * 32)
                        easing.type: Easing.Linear
                    }
                    PauseAnimation { duration: 650 }
                    PropertyAction { value: 0 }

                    onRunningChanged: {
                        if (!running)
                            compactTrackViewport.scrollOffset = 0
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Mini playback buttons
    // ═══════════════════════════════════════════════════════════

    // A small, self-contained material is what gives iOS-style controls
    // their liquid feel: the Dock window provides the real backdrop blur,
    // while these circles provide a translucent body, specular top edge and
    // press depth. The play button is deliberately one step larger.
    component DockControlButton: Item {
        id: control
        property bool enabled: true
        property bool primary: false
        property string symbol: ""
        property var trigger: null
        property bool hovered: false
        property bool pressed: false

        width: primary ? Math.max(25, widget.iconSize * 0.58)
                       : Math.max(21, widget.iconSize * 0.49)
        height: width
        opacity: enabled ? 1.0 : 0.35
        scale: pressed ? 0.90 : (hovered ? 1.06 : 1.0)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, ThemeService.isDark ? 0.24 : 0.56)
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0
                    color: widget.artworkTint(artworkPalette.primary,
                        primary ? 0.76 : 0.52)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.rgba(1, 1, 1, primary ? 0.25 : 0.16)
                }
                GradientStop {
                    position: 1
                    color: Qt.rgba(0, 0, 0, primary ? 0.32 : 0.22)
                }
            }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: symbol === "▶" ? 1 : 0
                text: symbol
                color: enabled ? ThemeService.foregroundColor : ThemeService.dividerColor
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.30)
                font.pixelSize: primary ? Math.max(14, widget.iconSize * 0.34)
                                        : Math.max(11, widget.iconSize * 0.27)
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            enabled: control.enabled
            onContainsMouseChanged: control.hovered = containsMouse
            onPressed: control.pressed = true
            onReleased: control.pressed = false
            onCanceled: control.pressed = false
            onClicked: {
                if (control.trigger)
                    control.trigger()
            }
        }
    }

    component DockPrevBtn: DockControlButton {
        symbol: "⏮"
        trigger: DockMprisService.previous
    }

    component DockPlayBtn: DockControlButton {
        property bool isPlaying: false
        primary: true
        symbol: isPlaying ? "⏸" : "▶"
        trigger: DockMprisService.togglePlayPause
    }

    component DockNextBtn: DockControlButton {
        symbol: "⏭"
        trigger: DockMprisService.next
    }
}
