import QtQuick
import qs.desktop.modules.common
import "WidgetLayout.mjs" as WidgetLayout

// Keep pointer coordinates in the scene: the handle itself moves as its card
// previews the snapped size. Local mouse deltas would jump between two sizes.
Item {
    id: handle
    objectName: "widget-resize-handle"
    width: 36
    height: 36
    property real cellSize: 180
    property real gap: 10
    property real cardWidth: parent.width
    property real cardHeight: parent.height
    property color ink: "white"
    property bool resizing: false
    property bool previewAllowed: true
    property int previewColumns: 1
    property int previewRows: 1
    // Widgets normally top out at two cells per axis; the grouped view is the
    // one anchored card allowed to grow to three rows/columns.
    property int maximumColumns: 2
    property int maximumRows: 2
    // The grouped view cannot shrink below 2x2: below that its header, four
    // type tabs and member grid stop fitting. Ordinary widgets keep one cell.
    property int minimumColumns: 1
    property int minimumRows: 1
    // A package's own declared sizes (metadata.json's `sizes`, e.g.
    // [[2,2],[3,2]]) -- when set, the drag snaps only to one of these exact
    // pairs instead of letting each axis vary independently within
    // [minimum*, maximum*]. That per-axis range only coincides with the
    // declared set when it happens to be rectangular (e.g. one shared row
    // count paired with two column counts); a package declaring a sparser
    // set like [[1,1],[3,3]] must still never land on an undeclared [2,2].
    // null/empty means "no discrete set declared" -- keep the old
    // continuous per-axis magnet behaviour for the legacy named widgets.
    property var declaredSizes: null
    // The corner position the drag actually shows: the pointer, bent by the
    // magnetic mapping so the card is held near whole-cell sizes.
    property real previewWidth: 0
    property real previewHeight: 0
    // Grab feedback is decorative, so reduced-motion hosts switch it off.
    property bool animate: true
    property point startPoint: Qt.point(0, 0)
    property real startWidth: 0
    property real startHeight: 0
    signal committed(int columns, int rows)

    // Grabbing the corner is a physical hold: the grip acknowledges the press
    // before the card itself starts changing size. Frame-synchronised, so the
    // grip follows the display instead of Qt's fixed 16 ms spring step.
    MotionSpring {
        id: gripScale
        target: pointer.pressed ? 1.14 : 1.0
        enabled: handle.animate
        angularFrequency: AppearanceTokens.motion.widgetGripAngularFrequency
        dampingRatio: AppearanceTokens.motion.widgetGripDampingRatio
        epsilon: AppearanceTokens.motion.widgetGripEpsilon
    }
    FrameAnimation {
        running: gripScale.animating
        onTriggered: gripScale.advance(frameTime)
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: pointer.pressed ? "#a0000000" : "#66000000"
        scale: gripScale.value
    }
    BundledIcon {
        anchors.centerIn: parent
        name: "desktop.widget.resize"
        size: 16
        color: handle.ink
    }
    MouseArea {
        id: pointer
        objectName: "widget-resize-pointer"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.SizeFDiagCursor
        preventStealing: true
        onPressed: function(mouse) {
            handle.startPoint = mapToItem(null, mouse.x, mouse.y)
            handle.startWidth = handle.cardWidth
            handle.startHeight = handle.cardHeight
            handle.applySpan(handle.startWidth, handle.startHeight)
            handle.resizing = true
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return
            // The pointer is mapped to the scene, so the preview keeps tracking
            // while the card's own spring animation moves this handle around.
            const point = mapToItem(null, mouse.x, mouse.y)
            const width = handle.startWidth + point.x - handle.startPoint.x
            const height = handle.startHeight + point.y - handle.startPoint.y
            handle.applySpan(width, height)
        }
        onReleased: {
            if (handle.previewAllowed)
                handle.committed(handle.previewColumns, handle.previewRows)
            handle.resizing = false
        }
        onCanceled: handle.resizing = false
    }

    // Shared by onPressed/onPositionChanged: resolves a raw pixel size to
    // the span the release will actually commit, and the pixel preview
    // the card ghosts while dragging.
    function applySpan(width, height) {
        const continuous = WidgetLayout.snappedSpan(width, height, handle.cellSize,
            handle.gap, handle.maximumColumns, handle.maximumRows,
            handle.minimumColumns, handle.minimumRows)
        // handle.declaredSizes may have crossed a Repeater/ListView model:
        // boundary upstream, which boxes it into a Qt sequence wrapper --
        // still indexable/has `.length`, but Array.isArray() on it is
        // false. Duck-type on `.length` instead (see WidgetLayout.mjs's
        // toArray, which nearestDeclaredSize below also goes through).
        const hasDeclaredSizes = !!handle.declaredSizes && handle.declaredSizes.length > 0
        const span = hasDeclaredSizes
            ? WidgetLayout.nearestDeclaredSize(continuous[0], continuous[1], handle.declaredSizes)
            : continuous
        handle.previewColumns = span[0]
        handle.previewRows = span[1]
        if (hasDeclaredSizes) {
            // A discrete set has no meaningful "in between" -- ghost the
            // exact cell size the release will commit instead of an
            // elastic, continuously-dragged pixel size.
            handle.previewWidth = span[0] * handle.cellSize + (span[0] - 1) * handle.gap
            handle.previewHeight = span[1] * handle.cellSize + (span[1] - 1) * handle.gap
        } else {
            handle.previewWidth = WidgetLayout.magnetizedSize(width,
                handle.cellSize, handle.gap, handle.maximumColumns,
                handle.minimumColumns)
            handle.previewHeight = WidgetLayout.magnetizedSize(height,
                handle.cellSize, handle.gap, handle.maximumRows,
                handle.minimumRows)
        }
    }
}
