import Quickshell
import QtQuick

// A blur region shaped like MaterialFlower's outline — the flower silhouette.
//
// Why scanlines instead of ellipses: Quickshell's `RegionShape.Ellipse` is
// axis-aligned and the twelve lobes are distributed radially, so no set of
// axis-aligned ellipses reproduces them, and `Intersection` cannot build a sine
// lobe out of circles either; a single inscribed circle would blur far less
// than the flower. `Region.regions` is a readonly list too, so JS cannot push a
// computed rectangle list into it — the slots below are therefore declared
// statically and each one binds to a precomputed band.
//
// Geometry is the same polar curve MaterialFlower draws:
//     r(theta) = R * (1 - amplitude + amplitude * sin(lobes * theta))
// and bands are produced by a scanline fill of that polygon. Every horizontal
// line crosses the shape at most twice (the smallest radius is
// R * (1 - 2*amplitude), so the centre stays solid), which is what makes a
// fixed two-slots-per-row layout exact rather than approximate. The region is
// the flower's own content area, so the frost edge lands on the outline that is
// actually drawn and never spills past it.
//
// Coordinates are surface coordinates, exactly like RoundedBlurRegion: `item`
// must be the positioned wrapper whose x/y are the card's surface position.
Region {
    id: root

    required property Item item
    property int lobes: 12
    property real amplitude: 0.075
    // Rows in the scanline fill. More rows means a finer stair on the lobes;
    // 32 keeps the region under 64 rectangles, which KWin handles comfortably.
    property int sliceCount: 32
    // Set false to publish nothing (the component is kept alive but yields an
    // empty region).
    property bool active: true

    readonly property real outlineInset: 1
    // MaterialFlower is centred in its parent and 18px smaller than the card's
    // short side. The region has to reproduce that exactly, or the blur edge
    // will not sit on the outline that is actually drawn.
    property real inset: 18
    readonly property real radius: Math.max(0,
        (Math.min(item.width, item.height) - inset) / 2 - outlineInset)

    // The flower outline in surface coordinates.
    function outline() {
        const points = []
        const count = 240
        const cx = item.x + item.width / 2
        const cy = item.y + item.height / 2
        for (let index = 0; index <= count; ++index) {
            const angle = index / count * Math.PI * 2
            const ripple = 1 - amplitude + amplitude * Math.sin(angle * lobes)
            points.push(Qt.point(cx + Math.cos(angle) * radius * ripple,
                cy + Math.sin(angle) * radius * ripple))
        }
        return points
    }

    // Scanline fill: sliceCount rows x 2 slots, empty slots are null.
    readonly property var bands: {
        if (!active || radius <= 0)
            return []
        const points = outline()
        const step = radius * 2 / sliceCount
        const top = item.y + item.height / 2 - radius
        const out = []
        for (let row = 0; row < sliceCount; ++row) {
            const scanY = top + (row + 0.5) * step
            const crossings = []
            for (let index = 0; index < points.length - 1; ++index) {
                const a = points[index]
                const b = points[index + 1]
                if ((a.y <= scanY) !== (b.y <= scanY)) {
                    const t = (scanY - a.y) / (b.y - a.y)
                    crossings.push(a.x + t * (b.x - a.x))
                }
            }
            crossings.sort(function (left, right) { return left - right })
            out.push(band(crossings, 0, scanY - step / 2, step))
            out.push(band(crossings, 1, scanY - step / 2, step))
        }
        return out
    }

    function band(crossings, index, y, height) {
        const left = crossings[index * 2]
        const right = crossings[index * 2 + 1]
        if (left === undefined || right === undefined || right - left <= 0)
            return null
        return { x: left, y: y, width: right - left, height: height }
    }

    // Read one field of one slot, rounded to the integer the region wants.
    function slot(index, field) {
        const entry = root.bands[index]
        if (!entry)
            return 0
        return Math.round(entry[field])
    }

    // Two slots per scanline row. `Region.regions` is a readonly list, so these
    // have to be declared; the count must stay at sliceCount * 2.
    Region { x: root.slot(0, "x"); y: root.slot(0, "y"); width: root.slot(0, "width"); height: root.slot(0, "height") }
    Region { x: root.slot(1, "x"); y: root.slot(1, "y"); width: root.slot(1, "width"); height: root.slot(1, "height") }
    Region { x: root.slot(2, "x"); y: root.slot(2, "y"); width: root.slot(2, "width"); height: root.slot(2, "height") }
    Region { x: root.slot(3, "x"); y: root.slot(3, "y"); width: root.slot(3, "width"); height: root.slot(3, "height") }
    Region { x: root.slot(4, "x"); y: root.slot(4, "y"); width: root.slot(4, "width"); height: root.slot(4, "height") }
    Region { x: root.slot(5, "x"); y: root.slot(5, "y"); width: root.slot(5, "width"); height: root.slot(5, "height") }
    Region { x: root.slot(6, "x"); y: root.slot(6, "y"); width: root.slot(6, "width"); height: root.slot(6, "height") }
    Region { x: root.slot(7, "x"); y: root.slot(7, "y"); width: root.slot(7, "width"); height: root.slot(7, "height") }
    Region { x: root.slot(8, "x"); y: root.slot(8, "y"); width: root.slot(8, "width"); height: root.slot(8, "height") }
    Region { x: root.slot(9, "x"); y: root.slot(9, "y"); width: root.slot(9, "width"); height: root.slot(9, "height") }
    Region { x: root.slot(10, "x"); y: root.slot(10, "y"); width: root.slot(10, "width"); height: root.slot(10, "height") }
    Region { x: root.slot(11, "x"); y: root.slot(11, "y"); width: root.slot(11, "width"); height: root.slot(11, "height") }
    Region { x: root.slot(12, "x"); y: root.slot(12, "y"); width: root.slot(12, "width"); height: root.slot(12, "height") }
    Region { x: root.slot(13, "x"); y: root.slot(13, "y"); width: root.slot(13, "width"); height: root.slot(13, "height") }
    Region { x: root.slot(14, "x"); y: root.slot(14, "y"); width: root.slot(14, "width"); height: root.slot(14, "height") }
    Region { x: root.slot(15, "x"); y: root.slot(15, "y"); width: root.slot(15, "width"); height: root.slot(15, "height") }
    Region { x: root.slot(16, "x"); y: root.slot(16, "y"); width: root.slot(16, "width"); height: root.slot(16, "height") }
    Region { x: root.slot(17, "x"); y: root.slot(17, "y"); width: root.slot(17, "width"); height: root.slot(17, "height") }
    Region { x: root.slot(18, "x"); y: root.slot(18, "y"); width: root.slot(18, "width"); height: root.slot(18, "height") }
    Region { x: root.slot(19, "x"); y: root.slot(19, "y"); width: root.slot(19, "width"); height: root.slot(19, "height") }
    Region { x: root.slot(20, "x"); y: root.slot(20, "y"); width: root.slot(20, "width"); height: root.slot(20, "height") }
    Region { x: root.slot(21, "x"); y: root.slot(21, "y"); width: root.slot(21, "width"); height: root.slot(21, "height") }
    Region { x: root.slot(22, "x"); y: root.slot(22, "y"); width: root.slot(22, "width"); height: root.slot(22, "height") }
    Region { x: root.slot(23, "x"); y: root.slot(23, "y"); width: root.slot(23, "width"); height: root.slot(23, "height") }
    Region { x: root.slot(24, "x"); y: root.slot(24, "y"); width: root.slot(24, "width"); height: root.slot(24, "height") }
    Region { x: root.slot(25, "x"); y: root.slot(25, "y"); width: root.slot(25, "width"); height: root.slot(25, "height") }
    Region { x: root.slot(26, "x"); y: root.slot(26, "y"); width: root.slot(26, "width"); height: root.slot(26, "height") }
    Region { x: root.slot(27, "x"); y: root.slot(27, "y"); width: root.slot(27, "width"); height: root.slot(27, "height") }
    Region { x: root.slot(28, "x"); y: root.slot(28, "y"); width: root.slot(28, "width"); height: root.slot(28, "height") }
    Region { x: root.slot(29, "x"); y: root.slot(29, "y"); width: root.slot(29, "width"); height: root.slot(29, "height") }
    Region { x: root.slot(30, "x"); y: root.slot(30, "y"); width: root.slot(30, "width"); height: root.slot(30, "height") }
    Region { x: root.slot(31, "x"); y: root.slot(31, "y"); width: root.slot(31, "width"); height: root.slot(31, "height") }
    Region { x: root.slot(32, "x"); y: root.slot(32, "y"); width: root.slot(32, "width"); height: root.slot(32, "height") }
    Region { x: root.slot(33, "x"); y: root.slot(33, "y"); width: root.slot(33, "width"); height: root.slot(33, "height") }
    Region { x: root.slot(34, "x"); y: root.slot(34, "y"); width: root.slot(34, "width"); height: root.slot(34, "height") }
    Region { x: root.slot(35, "x"); y: root.slot(35, "y"); width: root.slot(35, "width"); height: root.slot(35, "height") }
    Region { x: root.slot(36, "x"); y: root.slot(36, "y"); width: root.slot(36, "width"); height: root.slot(36, "height") }
    Region { x: root.slot(37, "x"); y: root.slot(37, "y"); width: root.slot(37, "width"); height: root.slot(37, "height") }
    Region { x: root.slot(38, "x"); y: root.slot(38, "y"); width: root.slot(38, "width"); height: root.slot(38, "height") }
    Region { x: root.slot(39, "x"); y: root.slot(39, "y"); width: root.slot(39, "width"); height: root.slot(39, "height") }
    Region { x: root.slot(40, "x"); y: root.slot(40, "y"); width: root.slot(40, "width"); height: root.slot(40, "height") }
    Region { x: root.slot(41, "x"); y: root.slot(41, "y"); width: root.slot(41, "width"); height: root.slot(41, "height") }
    Region { x: root.slot(42, "x"); y: root.slot(42, "y"); width: root.slot(42, "width"); height: root.slot(42, "height") }
    Region { x: root.slot(43, "x"); y: root.slot(43, "y"); width: root.slot(43, "width"); height: root.slot(43, "height") }
    Region { x: root.slot(44, "x"); y: root.slot(44, "y"); width: root.slot(44, "width"); height: root.slot(44, "height") }
    Region { x: root.slot(45, "x"); y: root.slot(45, "y"); width: root.slot(45, "width"); height: root.slot(45, "height") }
    Region { x: root.slot(46, "x"); y: root.slot(46, "y"); width: root.slot(46, "width"); height: root.slot(46, "height") }
    Region { x: root.slot(47, "x"); y: root.slot(47, "y"); width: root.slot(47, "width"); height: root.slot(47, "height") }
    Region { x: root.slot(48, "x"); y: root.slot(48, "y"); width: root.slot(48, "width"); height: root.slot(48, "height") }
    Region { x: root.slot(49, "x"); y: root.slot(49, "y"); width: root.slot(49, "width"); height: root.slot(49, "height") }
    Region { x: root.slot(50, "x"); y: root.slot(50, "y"); width: root.slot(50, "width"); height: root.slot(50, "height") }
    Region { x: root.slot(51, "x"); y: root.slot(51, "y"); width: root.slot(51, "width"); height: root.slot(51, "height") }
    Region { x: root.slot(52, "x"); y: root.slot(52, "y"); width: root.slot(52, "width"); height: root.slot(52, "height") }
    Region { x: root.slot(53, "x"); y: root.slot(53, "y"); width: root.slot(53, "width"); height: root.slot(53, "height") }
    Region { x: root.slot(54, "x"); y: root.slot(54, "y"); width: root.slot(54, "width"); height: root.slot(54, "height") }
    Region { x: root.slot(55, "x"); y: root.slot(55, "y"); width: root.slot(55, "width"); height: root.slot(55, "height") }
    Region { x: root.slot(56, "x"); y: root.slot(56, "y"); width: root.slot(56, "width"); height: root.slot(56, "height") }
    Region { x: root.slot(57, "x"); y: root.slot(57, "y"); width: root.slot(57, "width"); height: root.slot(57, "height") }
    Region { x: root.slot(58, "x"); y: root.slot(58, "y"); width: root.slot(58, "width"); height: root.slot(58, "height") }
    Region { x: root.slot(59, "x"); y: root.slot(59, "y"); width: root.slot(59, "width"); height: root.slot(59, "height") }
    Region { x: root.slot(60, "x"); y: root.slot(60, "y"); width: root.slot(60, "width"); height: root.slot(60, "height") }
    Region { x: root.slot(61, "x"); y: root.slot(61, "y"); width: root.slot(61, "width"); height: root.slot(61, "height") }
    Region { x: root.slot(62, "x"); y: root.slot(62, "y"); width: root.slot(62, "width"); height: root.slot(62, "height") }
    Region { x: root.slot(63, "x"); y: root.slot(63, "y"); width: root.slot(63, "width"); height: root.slot(63, "height") }
}
