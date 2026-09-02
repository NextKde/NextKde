import QtQuick

// Theme-independent, high-contrast glyphs for the tiny Dock information
// cards. Unlike a tinted themed icon, Canvas paints literal white pixels.
Item {
    id: root

    property string kind: "temperature" // "temperature" | "clock"
    property color glyphColor: "white"

    Image {
        anchors.fill: parent
        visible: root.kind === "clock"
        source: Qt.resolvedUrl("../../assets/time.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Image {
        anchors.fill: parent
        visible: root.kind === "temperature"
        source: Qt.resolvedUrl("../../assets/cpu-temperature.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
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
