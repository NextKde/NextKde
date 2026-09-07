import QtQuick

// Shared Wi-Fi glyph for the Bar and every network power control.  The faint
// outline shows the radio is present; the bright arcs show the current signal
// level, so a powered but disconnected radio is distinct from a weak link.
Item {
    id: root

    property bool wifiEnabled: true
    property bool connected: false
    property int signalStrength: -1
    property color glyphColor: "white"
    property real lineWidth: 1.55
    readonly property int signalLevel: !wifiEnabled || !connected
        || signalStrength < 0 ? 0
        : (signalStrength < 30 ? 1 : (signalStrength < 60 ? 2 : 3))

    implicitWidth: 20
    implicitHeight: 20

    Canvas {
        id: canvas
        anchors.fill: parent

        function drawArcs(ctx, count) {
            for (let ring = 0; ring < count; ring++) {
                const radius = 3.0 + ring * 2.7
                ctx.beginPath()
                ctx.arc(10, 14.2, radius,
                    Math.PI * 1.22, Math.PI * 1.78)
                ctx.stroke()
            }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = root.glyphColor
            ctx.fillStyle = root.glyphColor
            ctx.lineWidth = root.lineWidth
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.scale(width / 20, height / 20)
            ctx.translate(0, -1.1)

            // Keep the full glyph geometry visible at low opacity. Signal
            // quality is then represented by the number of bright arcs.
            ctx.globalAlpha = root.wifiEnabled ? 0.22 : 0.16
            drawArcs(ctx, 3)
            ctx.beginPath()
            ctx.arc(10, 13.8, 1.15, 0, Math.PI * 2)
            ctx.fill()

            if (root.wifiEnabled) {
                ctx.globalAlpha = root.connected ? 1.0 : 0.52
                drawArcs(ctx, root.signalLevel)
                ctx.beginPath()
                ctx.arc(10, 13.8, 1.15, 0, Math.PI * 2)
                ctx.fill()
            } else {
                // A slash makes the powered-off state unambiguous in the Bar,
                // where there is no surrounding active/inactive button fill.
                ctx.globalAlpha = 0.72
                ctx.beginPath()
                ctx.moveTo(4.0, 4.2)
                ctx.lineTo(15.6, 15.4)
                ctx.stroke()
            }
        }

        Connections {
            target: root
            function onWifiEnabledChanged() { canvas.requestPaint() }
            function onConnectedChanged() { canvas.requestPaint() }
            function onSignalStrengthChanged() { canvas.requestPaint() }
            function onGlyphColorChanged() { canvas.requestPaint() }
            function onLineWidthChanged() { canvas.requestPaint() }
            function onWidthChanged() { canvas.requestPaint() }
            function onHeightChanged() { canvas.requestPaint() }
        }
    }
}
