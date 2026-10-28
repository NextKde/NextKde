import QtQuick
import QtTest
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import "desktop/modules/deskcenter/WidgetLayout.mjs" as WidgetLayout

ShellRoot {
    id: test
    DeskCenterWindow {
        id: desktop
        visible: true
        WlrLayershell.layer: Quickshell.env("WIDGET_RESIZE_CAPTURE_DIR")
            ? WlrLayer.Overlay : WlrLayer.Bottom
        TestEvent { id: events }
    }
    property int stage: 0
    property int resizeIndex: 0
    property int renderIndex: 0
    property var renderSpans: [[1, 1], [1, 2], [2, 2], [2, 1]]
    property var spans: [[2, 1], [2, 2], [1, 2], [1, 1], [1, 2]]
    property point releasePoint: Qt.point(0, 0)
    property int moveIndex: 0
    property var moveTargets: []
    property var beforeMove: []
    function check(ok, message) { if (!ok) throw new Error(message) }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    Timer {
        interval: 350; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready) return
                const repeat = find(desktop.contentItem, "desktop-widget-repeater")
                if (stage === 0) {
                    ScreenLifecycle.activeScreen = desktop.screen
                    DesktopFilesService.desktopSubscriptionEnabled = false
                    DesktopFilesService.entries = [0, 1, 2].map(i => ({
                        path: "/tmp/widget-fixture-" + i, name: "fixture-" + i,
                        icon: "text-plain", isDir: false, output: desktop.desktopOutput
                    }))
                    if (Quickshell.env("VERIFY_WIDGET_RESTART") === "1") {
                        const span = DeskCenterConfigService.spanFor("clock")
                        check(span[0] === 1 && span[1] === 2, "portrait span survives restart")
                        const position = DeskCenterConfigService.positionsForOutput(desktop.desktopOutput).clock
                        check(position.column === desktop.maximumWidgetColumns - 1 && position.row === 2,
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
                    for (const id of DeskCenterConfigService.defaultOrder)
                        AppearanceConfigService.setDeskCenterWidgetVisible(id, true)
                    // Start with room around the clock so accepted corner resizes
                    // need not move any neighbouring widget.
                    for (const id of DeskCenterConfigService.defaultOrder)
                        DeskCenterConfigService.setSpan(id, 1, 1)
                    DeskCenterConfigService.savePosition(desktop.desktopOutput, [], "clock",
                        desktop.maximumWidgetColumns - 2, desktop.usableRows - 2, desktop.widgetGeometry)
                    desktop.enterWidgetEditMode(false)
                    stage = 1
                    return
                }
                check(repeat.count === 7, "all enabled cards instantiated")
                for (let i = 0; i < repeat.count; i++) {
                    const card = repeat.itemAt(i)
                    check(card.visible, card.modelData.id + " remains visible")
                    check(card.x >= 0 && card.y >= 0, "card stays in screen")
                    check(card.x + card.width <= desktop.width + 1, "card stays inside right edge")
                    check(card.y + card.height <= desktop.height - desktop.bottomInset + 1, "card stays above dock")
                    // Frame-driven animations can finish later than a timer
                    // on a loaded compositor. Await the actual destination.
                    if (stage !== 2 && (Math.abs(card.width - desktop.spanSize(card.displayColumns)) > 1
                            || Math.abs(card.height - desktop.spanSize(card.displayRows)) > 1
                            || Math.abs(card.x - desktop.leftInset - card.placement.column * (desktop.cellSize + desktop.gap)) > 1
                            || Math.abs(card.y - desktop.topInset - card.placement.row * (desktop.cellSize + desktop.gap)) > 1)) return
                }
                const files = find(desktop.contentItem, "desktop-file-grid")
                check(files.width >= DesktopFilesService.layout.iconSize + 88,
                    "rightmost widget preserves a usable file lane")
                if (stage === 4) {
                    // Load and render every widget at every supported size,
                    // including the narrow music/calendar/weather content.
                    if (renderIndex > 0) {
                        const span = renderSpans[renderIndex - 1]
                        for (let i = 0; i < repeat.count; i++) {
                            const card = repeat.itemAt(i)
                            check(card.displayColumns === span[0] && card.displayRows === span[1], "all cards use requested size")
                            for (let j = i + 1; j < repeat.count; j++) {
                                const other = repeat.itemAt(j)
                                check(card.x + card.width <= other.x + 1 || other.x + other.width <= card.x + 1
                                    || card.y + card.height <= other.y + 1 || other.y + other.height <= card.y + 1,
                                    "settled cards never overlap")
                            }
                        }
                        const directory = Quickshell.env("WIDGET_RESIZE_CAPTURE_DIR")
                        if (directory) {
                            for (const id of ["music", "calendar", "weather"]) {
                                find(desktop.contentItem, "desktop-widget-" + id).grabToImage(function(result) {
                                    check(result.saveToFile(directory + "/" + id + "-" + span[0] + "x" + span[1] + ".png"), "capture saved")
                                })
                            }
                        }
                    }
                    stage = 5
                    return
                }
                if (stage === 5) {
                    if (renderIndex < renderSpans.length) {
                        const span = renderSpans[renderIndex++]
                        for (const id of DeskCenterConfigService.defaultOrder)
                            DeskCenterConfigService.setSpan(id, span[0], span[1])
                        stage = 4
                        return
                    }
                    DeskCenterConfigService.setSpan("clock", 1, 2)
                    const occupied = desktop.placementFor("weather")
                    moveTargets = [
                        { column: desktop.maximumWidgetColumns - 1, row: 0, allowed: true },
                        { column: desktop.maximumWidgetColumns - 1, row: 2, allowed: true },
                        { column: occupied.column, row: occupied.row, allowed: false }
                    ]
                    stage = 6
                    return
                }
                if (stage >= 6) {
                    const target = moveTargets[moveIndex]
                    const draggedId = target.id || "clock"
                    const card = find(desktop.contentItem, "desktop-widget-" + draggedId)
                    if (stage === 6) {
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
                        releasePoint = Qt.point(start.x + (target.column - card.placement.column) * step,
                            start.y + (target.row - card.placement.row) * step)
                        events.mousePress(card, card.width / 2, card.height / 2, Qt.LeftButton, Qt.NoModifier, 5)
                        events.mouseMove(desktop.contentItem, start.x + 25, start.y, 10, Qt.LeftButton, Qt.NoModifier)
                        events.mouseMove(desktop.contentItem, releasePoint.x, releasePoint.y, 20, Qt.LeftButton, Qt.NoModifier)
                        stage = 7
                        return
                    }
                    if (stage === 7) {
                        check(card.moving, "card body starts position drag")
                        const preview = find(desktop.contentItem, "widget-drop-preview")
                        check(preview.visible && preview.allowed === target.allowed, "drop preview distinguishes empty and occupied cells")
                        events.mouseRelease(desktop.contentItem, releasePoint.x, releasePoint.y, Qt.LeftButton, Qt.NoModifier, 5)
                        stage = 8
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
                        const savedSpan = DeskCenterConfigService.spanFor("clock")
                        const handle = find(card, "widget-resize-handle")
                        const pointer = find(card, "widget-resize-pointer")
                        const start = pointer.mapToItem(desktop.contentItem, pointer.width / 2, pointer.height / 2)
                        events.mousePress(pointer, pointer.width / 2, pointer.height / 2, Qt.LeftButton, Qt.NoModifier, 5)
                        events.mouseMove(desktop.contentItem, start.x + desktop.cellSize + desktop.gap,
                            start.y, 20, Qt.LeftButton, Qt.NoModifier)
                        check(!handle.previewAllowed, "right-edge resize is rejected")
                        events.mouseRelease(desktop.contentItem, start.x + desktop.cellSize + desktop.gap,
                            start.y, Qt.LeftButton, Qt.NoModifier, 5)
                        check(DeskCenterConfigService.spanFor("clock").join() === savedSpan.join(),
                            "rejected resize does not save")
                    }
                    moveIndex++
                    if (moveIndex === 3) {
                        // These cards have a full-card launch MouseArea. The
                        // parent drag must take over without launching apps.
                        const extra = []
                        for (const id of ["weather", "todo", "music"]) {
                            const original = desktop.placementFor(id)
                            extra.push({ id, relocate: true, allowed: true })
                            extra.push({ id, column: original.column, row: original.row, allowed: true })
                        }
                        moveTargets = moveTargets.concat(extra)
                    }
                    if (moveIndex < moveTargets.length) { stage = 6; return }
                    console.log("WIDGET_RESIZE_PASS")
                    running = false
                    finish.start()
                    return
                }
                const card = find(desktop.contentItem, "desktop-widget-clock")
                const handle = find(card, "widget-resize-handle")
                const pointer = find(card, "widget-resize-pointer")
                const target = spans[resizeIndex]
                if (stage === 1) {
                    const start = pointer.mapToItem(desktop.contentItem, pointer.width / 2, pointer.height / 2)
                    const step = desktop.cellSize + desktop.gap
                    releasePoint = Qt.point(start.x + (target[0] - card.displayColumns) * step,
                        start.y + (target[1] - card.displayRows) * step)
                    events.mousePress(pointer, pointer.width / 2, pointer.height / 2, Qt.LeftButton, Qt.NoModifier, 5)
                    check(handle.resizing, "corner press starts resize " + target)
                    events.mouseMove(desktop.contentItem, releasePoint.x, releasePoint.y, 20, Qt.LeftButton, Qt.NoModifier)
                    check(handle.resizing, "corner move keeps resize " + target)
                    stage = 2
                    return
                }
                if (stage === 2) {
                    check(handle.resizing, "corner drag retains pointer grab")
                    check(handle.previewColumns === target[0] && handle.previewRows === target[1], "drag previews requested span")
                    events.mouseRelease(desktop.contentItem, releasePoint.x, releasePoint.y, Qt.LeftButton, Qt.NoModifier, 5)
                    stage = 3
                    return
                }
                check(!handle.resizing, "release ends resizing")
                const saved = DeskCenterConfigService.spanFor("clock")
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
