import QtQuick
import QtQuick.Effects
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: mediaCard
    objectName: "control-center-mediacard"
    required property var media
    property var player: null
    Rectangle {
        id: artwork
        width: 43; height: 43; radius: 13
        anchors { left: parent.left; top: parent.top; leftMargin: 13; topMargin: 13 }
        color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceContainerHigh, ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
        GlassText {
            anchors.centerIn: parent
            text: "♫"
            color: ThemeService.foregroundColor
            opacity: 0.86
            font.pixelSize: 21
        }
        Image {
            anchors.fill: parent
            source: mediaCard.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: status === Image.Ready
            smooth: true
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: artworkMask
            }
        }
        Rectangle {
            id: artworkMask
            anchors.fill: parent
            radius: artwork.radius
            visible: false
            layer.enabled: true
        }
    }
    Column {
        anchors { left: artwork.right; right: parent.right; top: artwork.top; leftMargin: 8; rightMargin: 10 }
        spacing: 2
        GlassText {
            width: parent.width
            text: mediaCard.player?.trackTitle || I18n.tr("Not playing")
            elide: Text.ElideRight
            color: ThemeService.foregroundColor
            font { pixelSize: 12; weight: Font.Bold; family: AppearanceTokens.typography.textFamily }
        }
        GlassText {
            width: parent.width
            text: mediaCard.media.loading ? mediaCard.media.playbackStatus
                : mediaCard.player?.trackArtist || I18n.tr("Media controls")
            elide: Text.ElideRight
            color: ThemeService.foregroundColor
            opacity: 0.70
            font { pixelSize: 10; family: AppearanceTokens.typography.textFamily }
        }
    }
    Row {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 15 }
        height: 40
        spacing: 12

        TransportButton {
            anchors.verticalCenter: parent.verticalCenter
            objectName: "media-previous"
            iconName: "media-previous"
            text: I18n.tr("Previous")
            enabled: mediaCard.player?.canGoPrevious ?? false
            onClicked: mediaCard.media.previous()
        }
        TransportButton {
            anchors.verticalCenter: parent.verticalCenter
            objectName: "media-toggle"
            primary: true
            iconName: mediaCard.player?.isPlaying ? "media-pause" : "media-play"
            text: mediaCard.player?.isPlaying ? I18n.tr("Pause") : I18n.tr("Play")
            busy: mediaCard.media.loading
            enabled: mediaCard.player?.canTogglePlaying ?? false
            onClicked: mediaCard.media.togglePlayPause()
        }
        TransportButton {
            anchors.verticalCenter: parent.verticalCenter
            objectName: "media-next"
            iconName: "media-next"
            text: I18n.tr("Next")
            enabled: mediaCard.player?.canGoNext ?? false
            onClicked: mediaCard.media.next()
        }
    }
    component TransportButton: MediaControlButton {
        glassInk: ThemeService.foregroundColor
        width: primary ? 40 : 32
        height: width
    }
}
