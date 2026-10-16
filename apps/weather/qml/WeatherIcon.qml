// Apple-style hand-drawn weather icon on a Canvas. This is the stand-in for
// SF Symbols' weather glyphs, which are not available outside Apple platforms.
// All drawing uses a 24x24 logical coordinate space, scaled to the item's
// actual (square) size, so one implementation serves every use.
import QtQuick
import Kos.Ui

Canvas {
    id: root

    antialiasing: true

    property int code: 0
    property bool isDay: true
    property bool pulse: false
    property real pulseOpacity: 1.0
    opacity: root.pulse ? root.pulseOpacity : 1.0
    onPulseChanged: if (!pulse) pulseOpacity = 1.0
    SequentialAnimation on pulseOpacity {
        running: root.pulse
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 550; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutSine }
    }

    // Variable color (SF Symbols 词汇): sun rays light up layer by layer.
    property real rayGlow: 1.0
    onRayGlowChanged: requestPaint()
    function playRayLightup() {
        if (AppTheme.reduceMotion)
            return
        rayGlow = 0
        rayAnim.restart()
    }
    SequentialAnimation {
        id: rayAnim
        NumberAnimation { target: root; property: "rayGlow"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
    }
    Component.onCompleted: playRayLightup()

    // Replace (down-up): old glyph drops out downward while the new one lands
    // from above. Skipped entirely under reduce motion (instant swap).
    property real paintAlpha: 1.0
    property int replaceOldCode: -1
    property real replaceOut: 0
    property real replaceIn: 0
    property bool replacing: false
    property bool _armed: false
    property int _lastCode: -1
    onReplaceOutChanged: requestPaint()
    onReplaceInChanged: requestPaint()
    onCodeChanged: {
        if (!_armed) {
            _armed = true
            _lastCode = code
            requestPaint()
            return
        }
        var oldC = _lastCode
        if (AppTheme.reduceMotion || oldC < 0 || oldC === code) {
            _lastCode = code
            requestPaint()
            return
        }
        replaceOldCode = oldC
        replacing = true
        replaceOut = 0
        replaceIn = 0
        replaceAnim.restart()
        _lastCode = code
    }
    SequentialAnimation {
        id: replaceAnim
        onStopped: root.replacing = false
        NumberAnimation { target: root; property: "replaceOut"; from: 0; to: 1; duration: 120; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "replaceIn"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
    }
    onIsDayChanged: requestPaint()

    onPaint: {
        if (width <= 0 || height <= 0)
            return
        var ctx = getContext("2d")
        ctx.reset()
        ctx.save()
        ctx.scale(width / 24, height / 24)

        if (replacing && replaceOldCode >= 0 && replaceOut > 0 && replaceOut < 1) {
            // Old glyph: falls 7 logical px down while fading out.
            root.paintAlpha = Math.max(1 - replaceOut, 0)
            ctx.save()
            ctx.globalAlpha = Math.max(1 - replaceOut, 0)
            ctx.translate(0, 7 * replaceOut)
            drawGlyph(ctx, replaceOldCode)
            ctx.restore()
        }
        if (replaceIn > 0) {
            // New glyph: lands from 7 logical px above.
            root.paintAlpha = replaceIn
            ctx.save()
            ctx.globalAlpha = replaceIn
            ctx.translate(0, -7 * (1 - replaceIn))
            drawGlyph(ctx, Number(code))
            ctx.restore()
        } else if (!replacing) {
            // Steady state (reduce motion, no transition, or transition done).
            root.paintAlpha = 1.0
            drawGlyph(ctx, Number(code))
        }

        ctx.restore()
    }

    function drawGlyph(ctx, weatherCode) {
        if (weatherCode === 0) {
            if (isDay)
                drawSun(ctx, 12, 12, 6, true)
            else
                drawMoon(ctx)
        } else if (weatherCode === 1 || weatherCode === 2) {
            // Sun/moon behind, cloud in front hiding its lower-right.
            if (isDay)
                drawSun(ctx, 9, 9, 4.5, false)
            else
                drawMoon(ctx, 9, 9, 4.5)
            drawCloud(ctx, 13, 11.5, 0.8)
        } else if ((weatherCode >= 51 && weatherCode <= 67)
                   || (weatherCode >= 80 && weatherCode <= 82)) {
            drawCloud(ctx, 12, 9.5, 1.0)
            drawRainDrops(ctx)
        } else if ((weatherCode >= 71 && weatherCode <= 77)
                   || weatherCode === 85 || weatherCode === 86) {
            drawCloud(ctx, 12, 9.5, 1.0)
            drawSnowDots(ctx)
        } else if (weatherCode >= 95) {
            drawCloud(ctx, 12, 9.5, 1.0)
            drawLightning(ctx)
        } else {
            // Overcast, fog and anything unknown: a plain cloud.
            drawCloud(ctx, 12, 12, 1.0)
        }
    }

    function drawSun(ctx, cx, cy, r, withRays) {
        ctx.fillStyle = "#ffd257"
        ctx.strokeStyle = "#ffd257"
        ctx.lineWidth = 1.6
        ctx.lineCap = "round"

        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
        ctx.fill()

        if (!withRays)
            return
        // Variable color: ray i lights up once rayGlow passes i/8, layer by layer.
        for (var i = 0; i < 8; ++i) {
            var alpha = Math.min(Math.max(rayGlow * 8 - i, 0), 1)
            var angle = i * Math.PI / 4
            var cos = Math.cos(angle)
            var sin = Math.sin(angle)
            ctx.globalAlpha = alpha * root.paintAlpha
            ctx.beginPath()
            ctx.moveTo(cx + cos * 8, cy + sin * 8)
            ctx.lineTo(cx + cos * 10.5, cy + sin * 10.5)
            ctx.stroke()
        }
        ctx.globalAlpha = 1
    }

    function drawMoon(ctx, cx, cy, r) {
        cx = (cx === undefined) ? 12 : cx
        cy = (cy === undefined) ? 12 : cy
        r = (r === undefined) ? 6.5 : r
        ctx.fillStyle = "#f7f3dc"
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
        ctx.fill()

        // Punch a crescent out of the disc.
        ctx.globalCompositeOperation = "destination-out"
        ctx.beginPath()
        ctx.arc(cx + 4 * r / 6.5, cy - 3 * r / 6.5, r * 5.5 / 6.5, 0, 2 * Math.PI)
        ctx.fill()
        ctx.globalCompositeOperation = "source-over"
    }

    function drawCloud(ctx, cx, cy, s) {
        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.96)

        // Left and right lobes.
        ctx.beginPath()
        ctx.arc(cx - 3.5 * s, cy + 1 * s, 2.8 * s, 0, 2 * Math.PI)
        ctx.fill()
        ctx.beginPath()
        ctx.arc(cx + 3.5 * s, cy + 1 * s, 2.8 * s, 0, 2 * Math.PI)
        ctx.fill()
        // Central dome.
        ctx.beginPath()
        ctx.arc(cx, cy - 1.2 * s, 3.4 * s, 0, 2 * Math.PI)
        ctx.fill()

        // Bottom slab with rounded lower corners, tying the lobes together.
        var left = cx - 4.5 * s
        var right = cx + 4.5 * s
        var top = cy + 1.2 * s
        var bottom = cy + 3.8 * s
        var corner = 1.2 * s
        ctx.beginPath()
        ctx.moveTo(left, top)
        ctx.lineTo(right, top)
        ctx.lineTo(right, bottom - corner)
        ctx.quadraticCurveTo(right, bottom, right - corner, bottom)
        ctx.lineTo(left + corner, bottom)
        ctx.quadraticCurveTo(left, bottom, left, bottom - corner)
        ctx.closePath()
        ctx.fill()
    }

    function drawRainDrops(ctx) {
        ctx.strokeStyle = "#6cb8ff"
        ctx.lineWidth = 1.8
        ctx.lineCap = "round"
        var xs = [8, 12, 16]
        for (var i = 0; i < xs.length; ++i) {
            var top = i === 1 ? 17 : 17.5
            var bottom = i === 1 ? 21.5 : 21
            ctx.beginPath()
            ctx.moveTo(xs[i], top)
            ctx.lineTo(xs[i], bottom)
            ctx.stroke()
        }
    }

    function drawSnowDots(ctx) {
        ctx.fillStyle = "#ffffff"
        var dots = [[8, 19], [12, 20], [16, 19]]
        for (var i = 0; i < dots.length; ++i) {
            ctx.beginPath()
            ctx.arc(dots[i][0], dots[i][1], 1.1, 0, 2 * Math.PI)
            ctx.fill()
        }
    }

    function drawLightning(ctx) {
        ctx.fillStyle = "#ffd257"
        ctx.beginPath()
        ctx.moveTo(12, 15)
        ctx.lineTo(9, 20)
        ctx.lineTo(11.5, 20)
        ctx.lineTo(10, 24)
        ctx.lineTo(15, 18)
        ctx.lineTo(12.5, 18)
        ctx.lineTo(14.5, 15)
        ctx.closePath()
        ctx.fill()
    }
}
