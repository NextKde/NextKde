import QtQuick
import QtQuick.Window

// The small borderless glyph button used by section headings and the header.
// Glyphs are drawn instead of typed so they do not depend on a font fallback
// (the shell has no bundled Inter and the reference uses Forma's vector icons).
Item {
    id: button
    property string kind: "reset"
    property color ink: "white"
    property real glyphSize: 12
    readonly property real hairline: 1 / (Screen.devicePixelRatio || 1)

    implicitWidth: 18
    implicitHeight: 20
    opacity: hover.hovered ? 1 : 0.82

    signal clicked()

    Canvas {
        id: glyph
        width: button.glyphSize
        height: button.glyphSize
        anchors.centerIn: parent
        onPaint: {
            const c = getContext("2d")
            c.reset()
            c.clearRect(0, 0, width, height)
            c.strokeStyle = button.ink
            c.lineWidth = Math.max(button.hairline, width / 12)
            c.lineCap = "round"
            c.lineJoin = "round"
            const unit = width / 12
            c.beginPath()
            if (button.kind === "close") {
                c.moveTo(2.5 * unit, 2.5 * unit)
                c.lineTo(9.5 * unit, 9.5 * unit)
                c.moveTo(9.5 * unit, 2.5 * unit)
                c.lineTo(2.5 * unit, 9.5 * unit)
            } else if (button.kind === "up") {
                c.moveTo(2 * unit, 7.5 * unit)
                c.lineTo(6 * unit, 3.5 * unit)
                c.lineTo(10 * unit, 7.5 * unit)
            } else if (button.kind === "down") {
                c.moveTo(2 * unit, 4.5 * unit)
                c.lineTo(6 * unit, 8.5 * unit)
                c.lineTo(10 * unit, 4.5 * unit)
            } else {
                // Circular arrow: three quarters of a circle plus an arrow head.
                c.arc(6 * unit, 6 * unit, 4.1 * unit, -Math.PI * 0.15, Math.PI * 1.35)
                c.stroke()
                c.beginPath()
                c.moveTo(6 * unit, 1.5 * unit)
                c.lineTo(8.6 * unit, 3.3 * unit)
                c.lineTo(6 * unit, 5.1 * unit)
            }
            c.stroke()
        }
    }

    onKindChanged: glyph.requestPaint()
    onInkChanged: glyph.requestPaint()
    onGlyphSizeChanged: glyph.requestPaint()

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: button.clicked()
    }
}
