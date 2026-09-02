import QtQuick
import qs.desktop.modules.dock

Canvas {
    id: root

    property var values: []
    property color lineColor: ThemeService.accentColor
    // Memory usage normally varies by far less than one percent. Scale that
    // graph to its observed range so genuine small changes remain visible.
    property bool adaptiveRange: false
    // Optional presentation filtering. Leave these at their neutral values
    // for diagnostic charts; larger desktop cards can opt into calmer curves.
    property int maxPoints: 0
    property int smoothingWindow: 1

    implicitHeight: 36

    function displayValues() {
        const source = values ?? []
        if (source.length === 0)
            return []
        const count = maxPoints > 1 ? Math.min(maxPoints, source.length) : source.length
        const reduced = []
        for (let point = 0; point < count; ++point) {
            const start = Math.floor(point * source.length / count)
            const end = Math.max(start + 1, Math.floor((point + 1) * source.length / count))
            let total = 0
            let samples = 0
            for (let index = start; index < end; ++index) {
                const value = Number(source[index])
                if (Number.isFinite(value)) {
                    total += value
                    samples++
                }
            }
            reduced.push(samples > 0 ? total / samples : 0)
        }
        const radius = Math.max(0, Math.floor((smoothingWindow - 1) / 2))
        if (radius === 0)
            return reduced
        return reduced.map(function(_, index) {
            let total = 0
            let samples = 0
            for (let offset = -radius; offset <= radius; ++offset) {
                const neighbor = index + offset
                if (neighbor >= 0 && neighbor < reduced.length) {
                    total += reduced[neighbor]
                    samples++
                }
            }
            return total / samples
        })
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        const points = displayValues()
        if (points.length < 2 || width <= 0 || height <= 0)
            return

        const inset = 2
        const plotWidth = width - inset * 2
        const plotHeight = height - inset * 2
        let low = 0
        let high = 1
        if (adaptiveRange) {
            low = points[0]
            high = points[0]
            for (let i = 1; i < points.length; ++i) {
                low = Math.min(low, points[i])
                high = Math.max(high, points[i])
            }
            if (high - low < 0.01) {
                const middle = (high + low) / 2
                low = Math.max(0, middle - 0.005)
                high = Math.min(1, middle + 0.005)
            }
        }
        ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.24)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(inset, height - inset)
        ctx.lineTo(width - inset, height - inset)
        ctx.stroke()

        ctx.strokeStyle = lineColor
        ctx.lineWidth = 2
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.beginPath()
        const coordinates = points.map(function(value, index) {
            const x = inset + plotWidth * index / (points.length - 1)
            const ratio = (value - low) / (high - low)
            return { x: x, y: inset + plotHeight * (1 - Math.max(0, Math.min(1, ratio))) }
        })
        ctx.moveTo(coordinates[0].x, coordinates[0].y)
        for (let i = 1; i < coordinates.length - 1; ++i) {
            const midpointX = (coordinates[i].x + coordinates[i + 1].x) / 2
            const midpointY = (coordinates[i].y + coordinates[i + 1].y) / 2
            ctx.quadraticCurveTo(coordinates[i].x, coordinates[i].y, midpointX, midpointY)
        }
        const last = coordinates[coordinates.length - 1]
        ctx.lineTo(last.x, last.y)
        ctx.stroke()
    }
    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onMaxPointsChanged: requestPaint()
    onSmoothingWindowChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
