import QtQuick
import QtQuick.Window
import "../NetworkRateFormat.mjs" as RateFormat

// 90 px, two-half history chart. Upload is drawn above the midline in red,
// download below it in blue. Each series normalises independently against
// max(256, peak) and occupies a fixed 60-point capacity.
//
// The Canvas only repaints when the data array or the geometry changes; the
// peak labels are ordinary Text items so no text is measured inside onPaint.
Item {
    id: root
    objectName: "traffic-chart"
    property var download: []
    property var upload: []
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    property color separator: Qt.rgba(1, 1, 1, 0.12)
    property color downloadColor: "#0099ff"
    property color uploadColor: "#ff3b40"
    readonly property real hairline: 1 / (Screen.devicePixelRatio || 1)
    readonly property real uploadPeak: peakOf(upload)
    readonly property real downloadPeak: peakOf(download)

    implicitHeight: 90

    function peakOf(values) {
        let maximum = 256
        if (values) {
            for (let i = 0; i < values.length; ++i) {
                const value = Number(values[i])
                if (Number.isFinite(value) && value > maximum)
                    maximum = value
            }
        }
        return maximum
    }
    function roundedPath(c, x, y, width, height, radius) {
        const r = Math.min(radius, width * 0.5, height * 0.5)
        c.beginPath()
        c.moveTo(x + r, y)
        c.lineTo(x + width - r, y)
        c.arcTo(x + width, y, x + width, y + r, r)
        c.lineTo(x + width, y + height - r)
        c.arcTo(x + width, y + height, x + width - r, y + height, r)
        c.lineTo(x + r, y + height)
        c.arcTo(x, y + height, x, y + height - r, r)
        c.lineTo(x, y + r)
        c.arcTo(x, y, x + r, y, r)
        c.closePath()
    }
    function paintSeries(c, values, color, upwards) {
        if (!values || values.length < 2)
            return
        const width = root.width
        const height = root.height
        const maximum = root.peakOf(values)
        const capacity = Math.max(60, values.length)
        const dx = width / (capacity - 1)
        const offset = capacity - values.length
        const middle = height * 0.5
        const amplitude = height * 0.5 - 2
        const sign = upwards ? -1 : 1
        const last = offset + values.length - 1

        c.beginPath()
        c.moveTo(offset * dx, middle)
        for (let i = 0; i < values.length; ++i) {
            const normalized = Math.min(1, Math.max(0, Number(values[i]) / maximum))
            c.lineTo((offset + i) * dx, middle + sign * normalized * amplitude)
        }
        c.lineTo(last * dx, middle)
        c.closePath()
        c.fillStyle = Qt.rgba(color.r, color.g, color.b, 0.55)
        c.fill()

        c.beginPath()
        for (let i = 0; i < values.length; ++i) {
            const normalized = Math.min(1, Math.max(0, Number(values[i]) / maximum))
            const x = (offset + i) * dx
            const y = middle + sign * normalized * amplitude
            if (i === 0)
                c.moveTo(x, y)
            else
                c.lineTo(x, y)
        }
        c.lineWidth = root.hairline
        c.lineJoin = "round"
        c.strokeStyle = color
        c.stroke()
    }

    Canvas {
        id: chart
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const c = getContext("2d")
            c.reset()
            c.clearRect(0, 0, width, height)
            root.roundedPath(c, 0, 0, width, height, 6)
            c.fillStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.045)
            c.fill()
            c.save()
            root.roundedPath(c, 0, 0, width, height, 6)
            c.clip()
            root.paintSeries(c, root.upload, root.uploadColor, true)
            root.paintSeries(c, root.download, root.downloadColor, false)
            c.beginPath()
            c.moveTo(0, height * 0.5)
            c.lineTo(width, height * 0.5)
            c.lineWidth = root.hairline
            c.strokeStyle = root.separator
            c.stroke()
            c.restore()
        }
    }
    Text {
        x: 4
        y: 2
        width: root.width - 8
        text: RateFormat.format(root.uploadPeak)
        color: root.mutedInk
        font.pixelSize: 9
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Text {
        x: 4
        y: root.height - 14
        width: root.width - 8
        text: RateFormat.format(root.downloadPeak)
        color: root.mutedInk
        font.pixelSize: 9
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    onDownloadChanged: chart.requestPaint()
    onUploadChanged: chart.requestPaint()
    onInkChanged: chart.requestPaint()
    onSeparatorChanged: chart.requestPaint()
    onWidthChanged: chart.requestPaint()
    onHeightChanged: chart.requestPaint()
}
