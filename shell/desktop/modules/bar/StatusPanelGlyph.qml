import QtQuick

// Small, consistent line icons without font-dependent Unicode glyphs.
Canvas {
    id: glyph
    property string kind: "download"
    property color ink: "white"
    implicitWidth: 20
    implicitHeight: 20
    onKindChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d")
        c.reset()
        c.scale(width / 24, height / 24)
        c.strokeStyle = ink
        c.lineWidth = 1.7
        c.lineCap = "round"
        c.lineJoin = "round"
        c.beginPath()
        if (kind === "download" || kind === "upload") {
            const down = kind === "download"
            c.moveTo(12, down ? 4 : 20); c.lineTo(12, down ? 18 : 6)
            c.moveTo(6, down ? 12 : 12); c.lineTo(12, down ? 18 : 6); c.lineTo(18, 12)
        } else if (kind === "power-saver") {
            c.moveTo(6, 19); c.quadraticCurveTo(6, 8, 20, 4)
            c.quadraticCurveTo(21, 18, 10, 18)
            c.moveTo(4, 21); c.lineTo(15, 10)
        } else if (kind === "balanced") {
            c.arc(12, 12, 8, 0, Math.PI * 2)
            c.moveTo(4, 12); c.lineTo(20, 12)
            c.moveTo(12, 4); c.lineTo(12, 20)
        } else if (kind === "performance") {
            c.moveTo(14, 3); c.lineTo(5, 14); c.lineTo(11, 14)
            c.lineTo(10, 21); c.lineTo(19, 10); c.lineTo(13, 10); c.closePath()
        } else if (kind === "check") {
            c.moveTo(5, 12); c.lineTo(10, 17); c.lineTo(19, 7)
        } else {
            c.moveTo(7, 7); c.lineTo(17, 17); c.moveTo(17, 7); c.lineTo(7, 17)
        }
        c.stroke()
    }
}
