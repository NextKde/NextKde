import QtQuick
import qs.desktop.modules.common

// Shared Wi-Fi glyph for the Bar and every network power control.  The faint
// outline shows the radio is present; the bright arcs show the current signal
// level, so a powered but disconnected radio is distinct from a weak link.
Item {
    id: root

    property bool wifiEnabled: true
    property bool connected: false
    property int signalStrength: -1
    // Every caller on shell chrome passes an explicit role; this default only
    // has to stay readable on the glass the shell actually painted.
    property color glyphColor: AppearanceTokens.content.glassInk()
    property real lineWidth: 1.55
    // The bar text carries a Text.Outline edge so it holds over a bright
    // backdrop. A Canvas has no text style, so the same edge is drawn: the
    // whole mark once more with a wider stroke in outlineColor, underneath.
    property bool outlined: false
    property color outlineColor: Qt.rgba(0, 0, 0, 0.40)
    property real outlineWidth: 1.1
    readonly property int signalLevel: !wifiEnabled || !connected
        || signalStrength < 0 ? 0
        : (signalStrength < 30 ? 1 : (signalStrength < 60 ? 2 : 3))

    implicitWidth: 20
    implicitHeight: 20

    Canvas {
        id: canvas
        anchors.fill: parent

        function strokeArc(ctx, radius) {
            ctx.beginPath()
            ctx.arc(10, 14.2, radius, Math.PI * 1.22, Math.PI * 1.78)
            ctx.stroke()
        }

        function drawArcs(ctx, count) {
            for (let ring = 0; ring < count; ring++) {
                strokeArc(ctx, 3.0 + ring * 2.7)
            }
        }

        function strokeDot(ctx) {
            ctx.beginPath()
            ctx.arc(10, 13.8, 1.15, 0, Math.PI * 2)
            ctx.stroke()
        }

        function drawDot(ctx) {
            ctx.beginPath()
            ctx.arc(10, 13.8, 1.15, 0, Math.PI * 2)
            ctx.fill()
        }

        function strokeSlash(ctx) {
            ctx.beginPath()
            ctx.moveTo(4.0, 4.2)
            ctx.lineTo(15.6, 15.4)
            ctx.stroke()
        }

        // One pass over every mark this glyph can show, widened so half of the
        // extra width falls outside the mark -- that outside half is the edge.
        function drawOutline(ctx) {
            ctx.save()
            ctx.globalAlpha = root.outlineColor.a
            ctx.strokeStyle = root.outlineColor
            ctx.lineWidth = root.lineWidth + root.outlineWidth * 2
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            for (let ring = 0; ring < 3; ring++) {
                strokeArc(ctx, 3.0 + ring * 2.7)
            }
            // The dot is filled, so it is outlined by stroking a wider ring
            // around the same circle before its fill lands on top.
            strokeDot(ctx)
            if (!root.wifiEnabled) {
                strokeSlash(ctx)
            }
            ctx.restore()
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

            if (root.outlined) {
                drawOutline(ctx)
                ctx.strokeStyle = root.glyphColor
                ctx.fillStyle = root.glyphColor
                ctx.lineWidth = root.lineWidth
            }

            // Keep the full glyph geometry visible at low opacity. Signal
            // quality is then represented by the number of bright arcs.
            ctx.globalAlpha = root.wifiEnabled ? 0.22 : 0.16
            drawArcs(ctx, 3)
            drawDot(ctx)

            if (root.wifiEnabled) {
                ctx.globalAlpha = root.connected ? 1.0 : 0.52
                drawArcs(ctx, root.signalLevel)
                drawDot(ctx)
            } else {
                // A slash makes the powered-off state unambiguous in the Bar,
                // where there is no surrounding active/inactive button fill.
                ctx.globalAlpha = 0.72
                strokeSlash(ctx)
            }
        }

        Connections {
            target: root
            function onWifiEnabledChanged() { canvas.requestPaint() }
            function onConnectedChanged() { canvas.requestPaint() }
            function onSignalStrengthChanged() { canvas.requestPaint() }
            function onGlyphColorChanged() { canvas.requestPaint() }
            function onLineWidthChanged() { canvas.requestPaint() }
            function onOutlinedChanged() { canvas.requestPaint() }
            function onOutlineColorChanged() { canvas.requestPaint() }
            function onOutlineWidthChanged() { canvas.requestPaint() }
            function onWidthChanged() { canvas.requestPaint() }
            function onHeightChanged() { canvas.requestPaint() }
        }
    }
}
