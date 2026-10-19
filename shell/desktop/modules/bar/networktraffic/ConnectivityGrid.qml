import QtQuick
import QtQuick.Window

// 30 px connectivity history: 30 columns x 3 rows of 0.5-radius cells.
// Samples are ordered oldest-to-newest, so index `i` is anchored to the end of
// the 90-cell window exactly as the native grid did.
Canvas {
    id: root
    objectName: "traffic-connectivity-grid"
    property var samples: []
    property color ink: "white"
    property color connectedColor: "#34c759"
    property color disconnectedColor: "#ff3b40"
    readonly property real hairline: 1 / (Screen.devicePixelRatio || 1)

    implicitHeight: 30

    function cellPath(c, x, y, width, height, radius) {
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

    onPaint: {
        const c = getContext("2d")
        c.reset()
        c.clearRect(0, 0, width, height)
        const values = root.samples || []
        const count = values.length
        const cellWidth = width / 30
        const cellHeight = height / 3
        const unknown = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.09)
        for (let x = 0; x < 30; ++x) {
            for (let y = 0; y < 3; ++y) {
                const index = x * 3 + y - (90 - count)
                const sample = index >= 0 && index < count ? values[index] : null
                root.cellPath(c, x * cellWidth, y * cellHeight,
                    Math.max(0, cellWidth - 1.5), Math.max(0, cellHeight - 1.5), 0.5)
                c.fillStyle = sample === null || sample === undefined ? unknown
                    : sample ? root.connectedColor : root.disconnectedColor
                c.fill()
            }
        }
    }
    onSamplesChanged: requestPaint()
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
