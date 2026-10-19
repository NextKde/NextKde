import QtQuick
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
    GlassText {
        anchors { right: parent.right; top: parent.top; rightMargin: 13; topMargin: 5 }
        text: "›"
        color: ThemeService.foregroundColor
        font { pixelSize: 15; weight: Font.Bold }
    }
    MouseArea {
        id: soundPagePointer
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 27
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: slotCard7.pageRequested("sound")
    }
    Canvas {
        id: volumeGlyph
        anchors { left: parent.left; leftMargin: 12; verticalCenter: volumeSlider.verticalCenter }
        width: 19
        height: 16
        renderTarget: Canvas.Image

        readonly property int volumeLevel: Math.round(slotCard7.volumePreview)
        readonly property bool isMuted: slotCard7.service.audioMuted
        readonly property color ink: AppearanceTokens.content.glassInk()

        onVolumeLevelChanged: requestPaint()
        onIsMutedChanged: requestPaint()
        onInkChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const fg = ink
            const bodyColor = isMuted
                ? Qt.rgba(fg.r, fg.g, fg.b, 0.50) : fg

            ctx.fillStyle = bodyColor
            ctx.strokeStyle = fg
            ctx.lineWidth = 1.5
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            ctx.fillRect(1.0, 5.5, 3.2, 5.0)

            ctx.beginPath()
            ctx.moveTo(4.2, 5.5)
            ctx.lineTo(7.5, 2.5)
            ctx.lineTo(7.5, 13.5)
            ctx.lineTo(4.2, 10.5)
            ctx.closePath()
            ctx.fill()

            if (isMuted) {
                ctx.globalCompositeOperation = "destination-out"
                ctx.lineWidth = 2.6
                ctx.beginPath()
                ctx.moveTo(0.8, 2.0)
                ctx.lineTo(8.8, 14.0)
                ctx.stroke()

                ctx.globalCompositeOperation = "source-over"
                ctx.lineWidth = 1.5
                ctx.strokeStyle = fg
                ctx.beginPath()
                ctx.moveTo(0.8, 2.0)
                ctx.lineTo(8.8, 14.0)
                ctx.stroke()
            } else {
                const arcs = volumeLevel > 66 ? 3 : (volumeLevel > 33 ? 2 : (volumeLevel > 0 ? 1 : 0))
                const cx = 6.0, cy = 8.0
                if (arcs >= 1) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, 4.2, -0.65, 0.65)
                    ctx.stroke()
                }
                if (arcs >= 2) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, 7.0, -0.70, 0.70)
                    ctx.stroke()
                }
                if (arcs >= 3) {
                    ctx.beginPath()
                    ctx.arc(cx, cy, 9.8, -0.72, 0.72)
                    ctx.stroke()
                }
            }
        }

        Connections {
            target: slotCard7.service
            function onAudioMutedChanged() { volumeGlyph.requestPaint() }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: slotCard7.service.setMuted(!slotCard7.service.audioMuted)
        }
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
