import QtQuick
import "../../../../shared/Icons" as Symbols
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../../shared/qml/i18n"

ControlCenterCard {
    id: slotCard7
    objectName: "control-center-soundcard"
    required property var service
    property real volumePreview: 0
    signal pageRequested(string page)
    signal volumePreviewRequested(real value)
    signal draggingVolumeRequested(bool value)
    ControlCenterSelection {
        pointer: soundPagePointer
        cornerRadius: slotCard7.cardRadius
        hovered: soundPagePointer.containsMouse || volumeSlider._hovered
        pressed: soundPagePointer.pressed || volumeSlider._pressed
    }
    Row {
        anchors { left: parent.left; top: parent.top; leftMargin: 14; topMargin: 8 }
        spacing: 4
        GlassText {
            text: I18n.tr("Sound")
            color: ThemeService.foregroundColor
            font { pixelSize: 11; weight: Font.DemiBold; family: AppearanceTokens.typography.textFamily }
        }
    }
    GlassText {
        anchors { right: parent.right; top: parent.top; rightMargin: 30; topMargin: 8 }
        text: Math.round(slotCard7.volumePreview) + "%"
        color: ThemeService.foregroundColor
        opacity: 0.50
        font { pixelSize: 9; family: AppearanceTokens.typography.textFamily }
    }
    BundledIcon {
        anchors { right: parent.right; top: parent.top; rightMargin: 13; topMargin: 5 }
        name: "chevron_right"
        color: ThemeService.foregroundColor
        size: 15
    }
    MouseArea {
        id: soundPagePointer
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 27
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: slotCard7.pageRequested("sound")
    }
    Symbols.VolumeIcon {
        id: volumeGlyph
        anchors { left: parent.left; leftMargin: 12; verticalCenter: volumeSlider.verticalCenter }
        width: 19
        height: 16

        readonly property int volumeLevel: Math.round(slotCard7.volumePreview)
        readonly property bool isMuted: slotCard7.service.audioMuted
        readonly property color ink: AppearanceTokens.content.glassInk()

        level: volumeLevel / 100
        muted: isMuted
        color: ink
    }
    ControlCenterSlider {
        id: volumeSlider
        objectName: "volumeSlider"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 36; rightMargin: 17; bottomMargin: 8 }
        value: slotCard7.volumePreview / 100
        onPreviewChanged: function(v) {
            slotCard7.draggingVolumeRequested(true)
            slotCard7.volumePreviewRequested(Math.round(v * 100))
        }
        onCanceled: {
            slotCard7.draggingVolumeRequested(false)
            slotCard7.volumePreviewRequested(slotCard7.service.volumePercent)
        }
        onCommitRequested: function(v) {
            slotCard7.draggingVolumeRequested(false)
            slotCard7.service.setVolume(Math.round(v * 100))
        }
    }
}
