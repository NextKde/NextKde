import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import "desktop/modules/deskcenter/WidgetLayout.mjs" as WidgetLayout

ShellRoot {
    id: test
    // This fixture mounts only the desktop; no shell boot coordinator runs.
    Component.onCompleted: StartupReveal.finish()
    DeskCenterWindow {
        id: desktop
        visible: true
        WlrLayershell.layer: Quickshell.env("WIDGET_RESIZE_CAPTURE_DIR")
            ? WlrLayer.Overlay : WlrLayer.Bottom
        TestEvent { id: events }
    }
    property int stage: 0
    property int resizeIndex: 0
    property var committedBeforeResize: [1, 1]
    property int renderIndex: 0
    property var renderSpans: [[1, 1], [2, 1]]
    property var spans: [[2, 1], [2, 2], [1, 2], [1, 1], [1, 2]]
    property point releasePoint: Qt.point(0, 0)
    property int moveIndex: 0
    property var moveTargets: []
    property var beforeMove: []
    property var retainedWidgetCards: []
    property string primaryId: ""
    property string weatherId: ""
    property string musicId: ""
    property string todoId: ""
    property Item trackedDragCard: null
    property int dragGeometryChanges: 0
    Connections {
        target: test.trackedDragCard
        function onXChanged() { test.dragGeometryChanges++ }
        function onYChanged() { test.dragGeometryChanges++ }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function glassRegion(card) {
        // v8 publishes SurfaceShape directly and deliberately has no legacy
        // blurRegion. Inspect the declaration under the active backend too.
        const pending = [card]
        const seen = []
        while (pending.length > 0) {
            const object = pending.pop()
            if (!object || seen.indexOf(object) >= 0) continue
            seen.push(object)
            if (object.surfaceShape?.target === card) return object
            for (const child of object.data || []) pending.push(child)
            for (const child of object.children || []) pending.push(child)
        }
        return null
    }
    function instanceIdFor(packageId) {
        const found = desktop.widgetInstances.find(item => item.packageId === packageId)
        return found ? found.id : ""
    }
    Timer {
        interval: 350; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready || desktop.widgetCatalog.length === 0) return
                const repeat = find(desktop.contentItem, "desktop-widget-repeater")
                if (stage === 0) {
                    ScreenLifecycle.activeScreen = desktop.screen
                    DesktopFilesService.desktopSubscriptionEnabled = false
                    DesktopFilesService.entries = [0, 1, 2].map(i => ({
                        path: "/tmp/widget-fixture-" + i, name: "fixture-" + i,
                        icon: "text-plain", isDir: false, output: desktop.desktopOutput
                    }))
                    if (Quickshell.env("VERIFY_WIDGET_RESTART") === "1") {
                        const restoredPrimary = instanceIdFor("org.nextkde.widget.calendar.macos")
                        check(restoredPrimary.length > 0, "placed SDK widget instance survives restart")
                        const span = DeskCenterConfigService.spanFor(restoredPrimary)
                        check(span[0] === 1 && span[1] === 2, "portrait span survives restart")
                        const position = DeskCenterConfigService.positionsForOutput(desktop.desktopOutput)[restoredPrimary]
                        check(position && position.column === desktop.maximumWidgetColumns - 1 && position.row === 2,
                            "manual grid position survives restart")
                        check(DeskCenterConfigService.positionsForOutput("projection-test").music.row === 6,
                            "another card's original position survives restart")
                        console.log("WIDGET_RESIZE_RESTART_PASS")
                        Qt.quit()
                        return
                    }
                    DeskCenterConfigService.savePosition("projection-test", [], "music", 2, 6, "8:8")
                    DeskCenterConfigService.savePosition("projection-test",
                        [{id: "music", column: 2, row: 0}], "clock", 4, 0, "8:4")
                    check(DeskCenterConfigService.positionsForOutput("projection-test").music.row === 6,
                        "moving another card preserves the saved row")
                    check(DeskCenterConfigService.displayPositionsForOutput("projection-test", "8:4").music.row === 0,
                        "current screen keeps its temporary placement")
                    check(DeskCenterConfigService.displayPositionsForOutput("projection-test", "8:8").music.row === 6,
                        "restored screen recovers original placement")
                    AppearanceConfigService.setDeskCenterWidgetVisible("groups", false)
                    while (desktop.widgetInstances.length > 0)
                        desktop.removeWidget(desktop.widgetInstances[0].id)
                    for (const pkgId of [
                        "org.nextkde.widget.calendar.macos",
                        "org.nextkde.widget.weather.macos",
                        "org.nextkde.widget.music.macos",
                        "org.nextkde.widget.todo.macos"
                    ]) {
                        const entry = desktop.widgetCatalog.find(item => item.id === pkgId)
                        check(!!entry, "SDK package indexed: " + pkgId)
                        desktop.addGalleryWidget(entry, "1x1")
                    }
                    test.primaryId = instanceIdFor("org.nextkde.widget.calendar.macos")
                    test.weatherId = instanceIdFor("org.nextkde.widget.weather.macos")
                    test.musicId = instanceIdFor("org.nextkde.widget.music.macos")
                    test.todoId = instanceIdFor("org.nextkde.widget.todo.macos")
                    check(test.primaryId && test.weatherId && test.musicId && test.todoId,
                        "all four SDK package instances created")
                    DeskCenterConfigService.savePosition(desktop.desktopOutput, desktop.placements,
                        test.primaryId, desktop.maximumWidgetColumns - 2, desktop.usableRows - 2,
                        desktop.widgetGeometry)
                    desktop.enterWidgetEditMode()
                    stage = 1
                    return
                }
                check(repeat.count === 4, "all enabled SDK cards instantiated")
                if (retainedWidgetCards.length === 0) {
                    const snapshot = []
                    for (let i = 0; i < repeat.count; ++i) {
                        const card = repeat.itemAt(i)
                        snapshot.push({ id: card.modelData.id, item: card })
                    }
                    retainedWidgetCards = snapshot
                }
                for (let i = 0; i < repeat.count; i++) {
                    const card = repeat.itemAt(i)
                    const retained = retainedWidgetCards.find(saved => saved.id === card.modelData.id)
                    check(retained && retained.item === card,
                        card.modelData.id + " retains its instance across layout saves")
                    check(card.visible, card.modelData.id + " remains visible")
                    if (card.moving) continue
                    check(card.x >= 0 && card.y >= 0, "card stays in screen")
                    check(card.x + card.width <= desktop.width + 1, "card stays inside right edge")
                    check(card.y + card.height <= desktop.height - desktop.bottomInset + 1, "card stays above dock")
                    if (stage !== 2 && (Math.abs(card.width - desktop.spanSize(card.displayColumns)) > 1
                            || Math.abs(card.height - desktop.spanSize(card.displayRows)) > 1
                            || Math.abs(card.x - desktop.leftInset - card.placement.column * (desktop.cellSize + desktop.gap)) > 1
                            || Math.abs(card.y - desktop.topInset - card.placement.row * (desktop.cellSize + desktop.gap)) > 1)) return
                }
                const files = find(desktop.contentItem, "desktop-file-grid")
                check(files.width >= DesktopFilesService.layout.iconSize + 88,
                    "rightmost widget preserves a usable file lane")
                if (stage === 4) {
                    if (renderIndex > 0) {
                        const span = renderSpans[renderIndex - 1]
                        for (let i = 0; i < repeat.count; i++) {
                            const card = repeat.itemAt(i)
                            check(card.displayColumns === span[0] && card.displayRows === span[1],
                                "all cards use requested size")
                            for (let j = i + 1; j < repeat.count; j++) {
                                const other = repeat.itemAt(j)
                                check(card.x + card.width <= other.x + 1 || other.x + other.width <= card.x + 1
                                    || card.y + card.height <= other.y + 1 || other.y + other.height <= card.y + 1,
                                    "settled cards never overlap")
                            }
                        }
                    }
                    stage = 5
                    return
                }
                if (stage === 5) {
                    if (renderIndex < renderSpans.length) {
                        const span = renderSpans[renderIndex++]
                        for (const inst of desktop.widgetInstances)
                            DeskCenterConfigService.setSpan(inst.id, span[0], span[1])
                        stage = 4
                        return
                    }
                    DeskCenterConfigService.setSpan(test.primaryId, 1, 2)
                    const occupied = desktop.placementFor(test.weatherId)
                    moveTargets = [
                        { column: desktop.maximumWidgetColumns - 1, row: 0, allowed: true },
                        { column: desktop.maximumWidgetColumns - 1, row: 2, allowed: true },
                        { column: occupied.column, row: occupied.row, allowed: false }
                    ]
                    stage = 6
                    return
                }
                if (stage === 10) {
                    console.log("WIDGET_RESIZE_PASS")
                    running = false
                    finish.start()
                    return
                }
                if (stage >= 6 && stage <= 9) {
                    const target = moveTargets[moveIndex]
                    const draggedId = target.id || test.primaryId
                    const card = find(desktop.contentItem, "desktop-widget-" + draggedId)
                    if (stage === 6) {
                        trackedDragCard = card
                        beforeMove = desktop.placements.slice()
                        if (target.relocate) {
                            let destination = null
                            for (let row = 0; row < desktop.usableRows && !destination; ++row)
                                for (let column = 0; column < desktop.maximumWidgetColumns && !destination; ++column)
                                    if ((column !== card.placement.column || row !== card.placement.row)
                                            && WidgetLayout.canPlace(desktop.placements, draggedId, column, row,
                                                card.displayColumns, card.displayRows, desktop.maximumWidgetColumns, desktop.usableRows))
                                        destination = {column, row}
                            check(destination !== null, "fixture has a free relocation rectangle")
                            target.column = destination.column
                            target.row = destination.row
                        }
                        const start = card.mapToItem(desktop.contentItem, card.width / 2, card.height / 2)
                        const step = desktop.cellSize + desktop.gap
                        const settle = 0.2
                        const deltaX = target.column - card.placement.column
                        const deltaY = target.row - card.placement.row
                        releasePoint = Qt.point(
                            start.x + (deltaX === 0 ? 0
                                : (Math.abs(deltaX) - settle) * Math.sign(deltaX)) * step,
                            start.y + (deltaY === 0 ? 0
                                : (Math.abs(deltaY) - settle) * Math.sign(deltaY)) * step)
                        events.mousePress(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.NoModifier, 5)
                        events.mouseMove(desktop.contentItem, start.x + 25, start.y, 10, Qt.LeftButton, Qt.NoModifier)
                        stage = 7
                        return
                    }
                    if (stage === 7) {
                        check(card.moving, "card body starts position drag")
                        dragGeometryChanges = 0
                        events.mouseMove(desktop.contentItem, releasePoint.x, releasePoint.y, 20, Qt.LeftButton, Qt.NoModifier)
                        stage = 8
                        return
                    }
                    if (stage === 8) {
                        check(card.moving && dragGeometryChanges > 0,
                            "continued drag updates native glass anchor geometry after lift finishes")
                        const step = desktop.cellSize + desktop.gap
                        check(Math.abs(card.x - (desktop.leftInset + card.placement.column * step + card.dragOffsetX)) < 1
                            && Math.abs(card.y - (desktop.topInset + card.placement.row * step + card.dragOffsetY)) < 1,
                            "drag geometry follows the pointer without position animation")
                        const region = card.blurRegion || glassRegion(card)
                        check(region !== null && region.surfaceShape.target === card, "native glass tracks the moved card")
                        const visual = card.mapToItem(null, Qt.rect(0, 0, card.width, card.height))
                        const blur = region.itemRect
                        check(Math.abs(blur.x - visual.x) < 1 && Math.abs(blur.y - visual.y) < 1
                            && Math.abs(blur.width - visual.width) < 1 && Math.abs(blur.height - visual.height) < 1,
                            "blur region follows the dragged and scaled content")
                        const preview = find(desktop.contentItem, "widget-drop-preview")
                        check(preview.visible && preview.allowed === target.allowed,
                            "drop preview distinguishes empty and occupied cells")
                        const xBeforeRelease = card.x
                        const yBeforeRelease = card.y
                        const previewBeforeRelease = Qt.rect(preview.x, preview.y, preview.width, preview.height)
                        const allowedBeforeRelease = preview.allowed
                        events.mouseRelease(desktop.contentItem, releasePoint.x, releasePoint.y, Qt.LeftButton, Qt.NoModifier, 5)
                        check(preview.x === previewBeforeRelease.x && preview.y === previewBeforeRelease.y
                            && preview.width === previewBeforeRelease.width && preview.height === previewBeforeRelease.height
                            && preview.allowed === allowedBeforeRelease,
                            "drop preview holds its last target geometry and colour while fading out")
                        if (target.column !== card.placement.column)
                            check(Math.abs(card.x - xBeforeRelease) < 1 && Math.abs(card.x
                                - (desktop.leftInset + target.column * step)) > 1,
                                "release springs the card towards its cell instead of snapping")
                        if (target.row !== card.placement.row)
                            check(Math.abs(card.y - yBeforeRelease) < 1 && Math.abs(card.y
                                - (desktop.topInset + target.row * step)) > 1,
                                "release springs the card towards its row instead of snapping")
                        stage = 9
                        return
                    }
                    for (const old of beforeMove) {
                        const placed = desktop.placementFor(old.id)
                        const expected = old.id === draggedId && target.allowed ? target : old
                        check(placed.column === expected.column && placed.row === expected.row,
                            "move changes only the dragged card and occupied drop restores original position")
                    }
                    check(!find(desktop.contentItem, "widget-drop-preview").visible, "drop clears preview")
                    console.log("WIDGET_RESIZE_MOVE", draggedId, target.column, target.row, target.allowed)
                    if (moveIndex === 0) {
                        const savedSpan = DeskCenterConfigService.spanFor(test.primaryId)
                        const handle = find(card, "widget-resize-handle")
                        const pointer = find(card, "widget-resize-pointer")
                        const start = pointer.mapToItem(desktop.contentItem, pointer.width / 2, pointer.height / 2)
                        events.mousePress(pointer, pointer.width / 2, pointer.height / 2, Qt.LeftButton, Qt.NoModifier, 5)
                        events.mouseMove(desktop.contentItem, start.x + desktop.cellSize + desktop.gap,
                            start.y, 20, Qt.LeftButton, Qt.NoModifier)
                        check(!handle.previewAllowed, "right-edge resize is rejected")
                        events.mouseRelease(desktop.contentItem, start.x + desktop.cellSize + desktop.gap,
                            start.y, Qt.LeftButton, Qt.NoModifier, 5)
                        check(DeskCenterConfigService.spanFor(test.primaryId).join() === savedSpan.join(),
                            "rejected resize does not save")
                    }
                    moveIndex++
                    if (moveIndex === 3) {
                        const extra = []
                        for (const id of [test.weatherId, test.todoId, test.musicId]) {
                            const original = desktop.placementFor(id)
                            extra.push({ id, relocate: true, allowed: true })
                            extra.push({ id, column: original.column, row: original.row, allowed: true })
                        }
                        moveTargets = moveTargets.concat(extra)
                    }
                    if (moveIndex < moveTargets.length) { stage = 6; return }
                    stage = 10
                    return
                }
                const card = find(desktop.contentItem, "desktop-widget-" + test.primaryId)
                const handle = find(card, "widget-resize-handle")
                const pointer = find(card, "widget-resize-pointer")
                const target = spans[resizeIndex]
                if (stage === 1) {
                    const start = pointer.mapToItem(desktop.contentItem, pointer.width / 2, pointer.height / 2)
                    const step = desktop.cellSize + desktop.gap
                    const committedColumns = card.displayColumns
                    const committedRows = card.displayRows
                    test.committedBeforeResize = [committedColumns, committedRows]
                    const travel = 0.55
                    releasePoint = Qt.point(start.x + (target[0] - committedColumns) * step * travel,
                        start.y + (target[1] - committedRows) * step * travel)
                    events.mousePress(pointer, pointer.width / 2, pointer.height / 2, Qt.LeftButton, Qt.NoModifier, 5)
                    check(handle.resizing, "corner press starts resize " + target)
                    check(handle.previewColumns === committedColumns && handle.previewRows === committedRows,
                        "corner press starts from the committed span")
                    events.mouseMove(desktop.contentItem, releasePoint.x, releasePoint.y, 20, Qt.LeftButton, Qt.NoModifier)
                    check(handle.resizing, "corner move keeps resize " + target)
                    check(handle.previewColumns === target[0] && handle.previewRows === target[1],
                        "past halfway the magnet commits the new span " + target)
                    if (target[0] !== committedColumns) {
                        const corner = card.width
                        const low = Math.min(desktop.spanSize(committedColumns), desktop.spanSize(target[0]))
                        const high = Math.max(desktop.spanSize(committedColumns), desktop.spanSize(target[0]))
                        check(corner > low + 1 && corner < high - 1,
                            "dragged corner sits between the two cell sizes " + target)
                    }
                    if (target[1] !== committedRows) {
                        const corner = card.height
                        const low = Math.min(desktop.spanSize(committedRows), desktop.spanSize(target[1]))
                        const high = Math.max(desktop.spanSize(committedRows), desktop.spanSize(target[1]))
                        check(corner > low + 1 && corner < high - 1,
                            "dragged corner sits between the two cell heights " + target)
                    }
                    stage = 2
                    return
                }
                if (stage === 2) {
                    check(handle.resizing, "corner drag retains pointer grab")
                    check(handle.previewColumns === target[0] && handle.previewRows === target[1],
                        "drag previews requested span")
                    const widthBeforeRelease = card.width
                    const heightBeforeRelease = card.height
                    events.mouseRelease(desktop.contentItem, releasePoint.x, releasePoint.y, Qt.LeftButton, Qt.NoModifier, 5)
                    check(!handle.resizing, "release ends resizing")
                    const changedColumns = target[0] !== test.committedBeforeResize[0]
                    const changedRows = target[1] !== test.committedBeforeResize[1]
                    if (changedColumns)
                        check(Math.abs(card.width - widthBeforeRelease) < 1,
                            "release does not resize the card instantaneously " + target)
                    if (changedRows)
                        check(Math.abs(card.height - heightBeforeRelease) < 1,
                            "release does not resize the card instantaneously " + target)
                    check((changedColumns && Math.abs(card.width - desktop.spanSize(target[0])) > 1)
                        || (changedRows && Math.abs(card.height - desktop.spanSize(target[1])) > 1),
                        "release springs the corner onto the cell " + target)
                    stage = 3
                    return
                }
                check(!handle.resizing, "release ends resizing")
                const saved = DeskCenterConfigService.spanFor(test.primaryId)
                check(saved[0] === target[0] && saved[1] === target[1], "drag commits span")
                check(card.displayColumns === target[0] && card.displayRows === target[1], "card uses committed span")
                check(card.dragOffsetX === 0 && card.dragOffsetY === 0, "resize never becomes reorder drag")
                console.log("WIDGET_RESIZE_SPAN", target[0], target[1])
                resizeIndex++
                if (resizeIndex < spans.length) { stage = 1; return }
                DeskCenterConfigService._settings.positionsJson = JSON.stringify({
                    "projection-test": DeskCenterConfigService.positionsForOutput("projection-test")
                })
                DeskCenterConfigService.projectedPositions = ({})
                DeskCenterConfigService.revision++
                stage = 4
            } catch (error) {
                console.error("WIDGET_RESIZE_FAIL: " + error)
                Qt.quit()
            }
        }
    }
    Timer { id: finish; interval: 350; onTriggered: Qt.quit() }
    Timer { interval: 40000; running: true; onTriggered: { console.error("WIDGET_RESIZE_FAIL: timeout"); Qt.quit() } }
}
