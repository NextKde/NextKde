import QtQuick
import qs.desktop.modules.common

// Theme-independent, high-contrast glyphs for the tiny Dock information
// cards. Unlike a tinted themed icon, Canvas paints literal white pixels.
Item {
    id: root

    property string kind: "temperature" // "temperature" | "clock"
    property color glyphColor: "white"
    // The same readability edge the bar text carries (Text.Outline). Off by
    // default: the Dock's own cards already sit on opaque fills, and only the
    // Bar asks for the extra edge.
    property bool outlined: false
    property color outlineColor: Qt.rgba(0, 0, 0, 0.40)

    // BundledIcon rather than a raw Image because it owns both halves of what
    // this glyph needs: painting the white mask in glyphColor, and drawing the
    // readability edge around it.
    BundledIcon {
        anchors.fill: parent
        visible: root.kind === "clock"
        name: "time"
        size: Math.min(root.width, root.height)
        color: root.glyphColor
        outlined: root.outlined
        outlineColor: root.outlineColor
    }

    BundledIcon {
        anchors.fill: parent
        visible: root.kind === "temperature"
        name: "cpu-temperature"
        size: Math.min(root.width, root.height)
        color: root.glyphColor
        outlined: root.outlined
        outlineColor: root.outlineColor
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        visible: root.kind !== "clock" && root.kind !== "temperature"

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const side = Math.min(width, height)
            const cx = width / 2
            const cy = height / 2
            ctx.strokeStyle = root.glyphColor
            ctx.fillStyle = root.glyphColor
            ctx.lineWidth = Math.max(1.2, side * 0.12)
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            const bulbRadius = side * 0.19
            const tubeTop = cy - side * 0.34
            const tubeBottom = cy + side * 0.18
            ctx.beginPath()
            ctx.moveTo(cx, tubeTop)
            ctx.lineTo(cx, tubeBottom)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cx, cy + side * 0.27, bulbRadius, 0, Math.PI * 2)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(cx + side * 0.20, tubeTop)
            ctx.lineTo(cx + side * 0.32, tubeTop)
            ctx.stroke()
        }

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onKindChanged() { canvas.requestPaint() }
            function onGlyphColorChanged() { canvas.requestPaint() }
        }
    }
}
