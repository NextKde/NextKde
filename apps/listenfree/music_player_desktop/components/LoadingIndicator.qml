import QtQuick
import QtQuick.Controls as Basic

Basic.BusyIndicator {
    id: control
    property color color: AppTheme.textPrimary
    property string description: qsTr("正在加载…")
    implicitWidth: 18
    implicitHeight: 18
    padding: 0
    running: visible
    Accessible.name: description
    Basic.ToolTip.visible: pointer.hovered
    Basic.ToolTip.text: description
    HoverHandler { id: pointer }
    contentItem: Canvas {
        property color ink: control.color
        onInkChanged: requestPaint()
        onPaint: {
            const context = getContext("2d")
            context.clearRect(0, 0, width, height)
            context.strokeStyle = ink
            context.lineWidth = 2
            context.lineCap = "round"
            context.beginPath()
            context.arc(width / 2, height / 2, Math.max(1, Math.min(width, height) / 2 - 3), 0, Math.PI * 1.5)
            context.stroke()
        }
        RotationAnimator on rotation {
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
            running: control.running && control.visible
        }
    }
}
