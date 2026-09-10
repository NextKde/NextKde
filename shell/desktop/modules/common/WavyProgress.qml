import QtQuick

Canvas {
    id: root
    property real value: 0
    property bool animated: false
    property color activeColor: "white"
    property color trackColor: Qt.rgba(1, 1, 1, 0.24)
    property real amplitude: 2.5
    property real wavelength: 12
    property real lineWidth: 3
    property real phase: 0

    onValueChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onActiveColorChanged: requestPaint()
    onTrackColorChanged: requestPaint()
    onPhaseChanged: requestPaint()

    NumberAnimation on phase {
        running: root.animated && root.visible
        from: 0
        to: Math.PI * 2
        duration: 1100
        loops: Animation.Infinite
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const centerY = height / 2
        const progressX = Math.max(0, Math.min(width, width * value))
        ctx.lineCap = "round"
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = trackColor.toString()
        ctx.beginPath()
        ctx.moveTo(progressX, centerY)
        ctx.lineTo(width, centerY)
        ctx.stroke()

        if (progressX <= 0)
            return
        ctx.strokeStyle = activeColor.toString()
        ctx.beginPath()
        for (let x = 0; x <= progressX; x += 1) {
            const envelope = Math.min(1, x / 5, (progressX - x) / 5)
            const y = centerY + Math.sin(x / wavelength * Math.PI * 2 + phase)
                * amplitude * Math.max(0, envelope)
            if (x === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.fillStyle = activeColor.toString()
        ctx.beginPath()
        ctx.arc(progressX, centerY, lineWidth * 0.9, 0, Math.PI * 2)
        ctx.fill()
    }
}
