import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

// IslandContent — the island's interior.
//
// Ported from the NookX Dynamic Island. The original renders the island from
// a widget catalogue plus a quick-launch list, with a compact top bar, a
// widget column, an application column and two editing surfaces. Here the
// same surfaces are native QML:
//
//   - the top bar carries the add-components entry on the left, the clock in
//     the middle and the edit entry on the right. The brand pill is
//     deliberately not reproduced: the original spells its own product name
//     there, and this shell does not put a product name in the middle of its
//     own desktop furniture;
//   - the body is split by a hairline into a widget column and an
//     application column, both drawn as layered cards;
//   - both columns are drag surfaces: a card is picked up, lifts and turns
//     into the drag, and the column shows where it would land;
//   - the widget editor toggles and reorders the catalogue;
//   - the app picker pins/unpins desktop entries.
//
// ---------------------------------------------------------------------------
// Pointer model
// ---------------------------------------------------------------------------
// There is exactly one pointer source for the whole island: the surface
// MouseArea in IslandWindow, which is the ancestor of everything below. QML
// hover is exclusive -- the topmost item that accepts hover gets it, and
// nothing else does -- so a single hover-enabled descendant is enough to
// make the ancestor believe the pointer left the island. The island then
// collapsed under the pointer, which removed the descendant, which restored
// the ancestor's hover, which expanded it again: the bounce and the jitter
// the user reported had the same cause.
//
// Nothing in this file accepts hover. No hoverEnabled, no HoverHandler: every
// highlight is derived from IslandService.pointerX/pointerY, and every press
// is either taken by a small control of its own or dispatched here by
// hit-testing the column geometry. The pointer's coordinates are therefore
// always in the island's own space, never in the space of a card that is
// moving because of them.
Item {
    id: root

    // 0 = collapsed, 1 = expanded. Everything crossfades on this value.
    property real reveal: 0

    readonly property var config: IslandConfigService
    readonly property var service: IslandService

    // Editor sessions, mirroring the original's _isEditingWidgets /
    // widgetEditingSessionID: one editor at a time, closed explicitly.
    property bool editingWidgets: false
    property bool pickingApps: false
    // The right-hand control reorders the pinned applications. It used to
    // open the widget editor, which left the program order with no editor at
    // all -- the deck could only be reordered by dragging inside a strip that
    // scrolls away from you.
    property bool editingApps: false

    // The notes panel. A widget that is really an application (the memo store)
    // cannot live inside a 190x155 card: the card previews the note list and
    // the panel is where reading and writing happen.
    property bool openNotes: false

    // The Finder: a search field over the data service's file index. It is
    // the one panel that is really an application, so it takes the keyboard
    // while it is open.
    property bool openFinder: false

    // The expanded panel has two shapes: the two-column shelf (the NookX
    // arrangement, and the default) and the card layout, where a rail picks
    // what the panel is showing. Notchy uses the second one -- an expanded
    // panel is 820x250 with one 366.6x170 card at a time and a rail of
    // features beside it.
    property string layoutMode: "columns"
    property string cardPage: "widgets"
    // Which widget the card layout is showing.
    property int cardWidgetIndex: 0

    // The island asks the layer surface for keyboard focus only while
    // something that can be typed into is open. The notes editor is exactly
    // that, so it joins the app picker on this one flag.
    readonly property bool wantsKeyboard: pickingApps || openNotes || openFinder
    property bool notesPreview: false

    // Loading a note into the editor must not be mistaken for an edit.
    property bool applyingNote: false

    // A small Markdown renderer. Not a parser: headings, list bullets,
    // fenced code and escaping are what a note actually uses, and anything
    // else is shown as the literal text the user typed.
    function markdownToHtml(text) {
        const escape = function(s) {
            return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                .replace(/>/g, "&gt;")
        }
        let html = ""
        let inCode = false
        const lines = String(text === undefined ? "" : text).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            const fence = /^\s*```/.test(line)
            if (fence) {
                if (inCode) {
                    html += "</pre>"
                    inCode = false
                } else {
                    html += "<pre style='color:#8fe6c8'>"
                    inCode = true
                }
                continue
            }
            if (inCode) {
                html += escape(line)
                continue
            }
            const heading = /^(#{1,4})\s+(.*)$/.exec(line)
            if (heading) {
                const level = heading[1].length + 1
                html += "<h" + level + ">" + escape(heading[2]) + "</h" + level + ">"
                continue
            }
            const bullet = /^\s*[-*]\s+(.*)$/.exec(line)
            if (bullet) {
                html += "<li>" + escape(bullet[1]) + "</li>"
                continue
            }
            const bold = /^\s*\*\*(.+)\*\*\s*$/.exec(line)
            if (bold) {
                html += "<b>" + escape(bold[1]) + "</b>"
                continue
            }
            html += escape(line) + "<br>"
        }
        if (inCode)
            html += "</pre>"
        return html
    }
    property string appSearch: ""

    // Bar clock, refreshed by a timer so the collapsed pill is always right.
    property string clockText: Qt.formatTime(new Date(), "HH:mm")

    // The ink colour follows the background the island is drawn on. A solid
    // or glass island is always dark, so its text is always light; a
    // transparent island sits on the desktop and has to follow the
    // desktop's own theme, or the text disappears into a light wallpaper.
    readonly property bool islandIsDark: config.backgroundMode !== "none"
        || AppearanceTokens.isDarkTheme
    readonly property color ink: islandIsDark ? "#ffffff" : "#101216"
    // The accent comes from the theme preset. The colours are the shell's own
    // traditional-colour values, so the island's themes read as NextKde's
    // palette rather than a private one.
    readonly property color accent: config.accentColor

    function accentA(alpha) {
        return Qt.rgba(accent.r, accent.g, accent.b, alpha)
    }

    // The payload of a file drag. A text/uri-list is a list of URIs, one per
    // line, and the URI has to be percent-encoded -- a path with a space in
    // it is not a URI otherwise.
    function fileUri(path) {
        return "file://" + String(path || "").split("/").map(function(part) {
            return encodeURIComponent(part)
        }).join("/")
    }

    // --- Fold -------------------------------------------------------------
    // The deck is laid out like a folded brochure: neighbouring panels lean
    // opposite ways, so the row reads as an accordion seen slightly from
    // above rather than as a flat strip of cards.
    property real foldAngle: 16

    function foldFor(index) {
        return (index % 2 === 0 ? 1 : -1) * root.foldAngle
    }

    readonly property color inkMuted: islandIsDark
        ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0.06, 0.07, 0.09, 0.58)
    // 0.45 rather than 0.32: on the near-black panel 0.32 composited to about
    // 2.8:1, below the 4.5:1 a 10px label needs, and the pager and the hint
    // text are both set in it.
    readonly property color inkFaint: islandIsDark
        ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0.06, 0.07, 0.09, 0.46)

    // --- Layout metrics ---------------------------------------------------
    // Shared by the layout and by the hit tests: the geometry and the test
    // that reads it must not be two independent guesses.
    //
    // Every metric is a fraction of `unit` (the expanded panel height) taken
    // from the reference capture, where the panel is 328px tall with a 52px
    // content padding, 55px between blocks, a 74px corner and content blocks
    // between 0.38 and 0.57 of the height. Hard-coding pixels made the port
    // look right at exactly one screen size and wrong at every other.
    property real unit: 320

    readonly property int barHeight: Math.round(unit * 0.22)
    readonly property int sidePadding: Math.round(unit * 0.159)
    readonly property int bottomPadding: Math.round(unit * 0.10)
    readonly property int cardGap: Math.round(unit * 0.168)
    readonly property int widgetCardWidth: Math.round(unit * 0.55)
    readonly property int widgetCardHeight: Math.round(unit * 0.44)
    // Panels of a folded sheet meet at a seam, so the gap is a seam rather
    // than the reference's 0.168u spacing. The rotation itself narrows each
    // panel by (1 - cos(foldAngle)), which is what the extra few pixels cover.
    readonly property int foldGap: Math.max(6, Math.round(cardGap * 0.25))
    readonly property int widgetStep: widgetCardWidth + foldGap
    // App tiles are deliberately smaller than the widget cards: the
    // reference gives its widgets 0.38-0.57 of the panel height, but six
    // launcher icons at that size do not fit beside them, and an icon deck
    // that only shows four of six is worse than one drawn a size down.
    readonly property int appTileWidth: Math.round(unit * 0.28)
    readonly property int appTileHeight: appTileWidth
    readonly property int appStep: appTileWidth + foldGap

    // What the two columns may use: the panel minus both side paddings, both
    // column gaps and the 1px divider. A fraction of the whole panel would
    // overflow on a narrow screen and drive the trailing spacer negative.
    readonly property real bodyWidth: Math.max(0, width - sidePadding * 2)
    readonly property real columnBudget:
        Math.max(200, bodyWidth - cardGap * 2 - 1)

    // --- Derived models ---------------------------------------------------
    readonly property var activeWidgets: {
        const catalogue = config.catalogue
        const byId = {}
        for (let i = 0; i < catalogue.length; i++)
            byId[catalogue[i].id] = catalogue[i]
        const out = []
        const order = config.enabledWidgetOrder || []
        for (let i = 0; i < order.length; i++) {
            if (byId[order[i]])
                out.push(byId[order[i]])
        }
        return out
    }

    // Editor model: the catalogue in its own fixed order.
    //
    // It used to be "enabled widgets first, then the rest", which made the
    // list re-sort itself after every toggle. The row under the pointer became
    // a different component between two clicks, so choosing a component felt
    // like walking down the list in order instead of toggling what was
    // clicked. Reordering belongs to the cards on the island, which are
    // dragged; the editor only turns things on and off.
    readonly property var editModel: config.catalogue || []

    readonly property var filteredApps: {
        const q = root.appSearch.trim().toLowerCase()
        // The picker lists the whole desktop catalogue with the pinned state
        // visible, so an application can be unpinned from the island too --
        // the original's QuickLaunch picker toggles membership the same way.
        // Icons are resolved through the model, never here: a raw entry icon
        // is an icon *name*, and Image reads a bare name as a relative path.
        const all = (IslandQuickLaunchModel.allEntries || []).map(function(e) {
            return {
                id: e.id,
                name: e.name || e.id,
                icon: IslandQuickLaunchModel.iconFor(e.icon)
            }
        })
        if (!q)
            return all
        return all.filter(function(e) {
            return String(e.name || "").toLowerCase().indexOf(q) >= 0
                || String(e.id || "").toLowerCase().indexOf(q) >= 0
        })
    }

    // --- Quick-launch paging ---------------------------------------------
    readonly property int launchPageSize: Math.max(1, config.quickLaunchPageSize)
    readonly property int launchPageCount: Math.max(1,
        Math.ceil((IslandQuickLaunchModel.entries || []).length / launchPageSize))
    property int launchPage: 0
    readonly property int launchPageStart: launchPage * launchPageSize
    readonly property var launchPageEntries: {
        const all = IslandQuickLaunchModel.entries || []
        if (all.length === 0)
            return []
        const start = Math.min(root.launchPageStart, all.length - 1)
        return all.slice(start, start + root.launchPageSize)
    }

    onLaunchPageCountChanged: {
        if (root.launchPage > root.launchPageCount - 1)
            root.launchPage = Math.max(0, root.launchPageCount - 1)
    }

    // --- Pointer-derived hover -------------------------------------------
    property int hoverWidget: -1
    property int hoverApp: -1

    // --- Drag state -------------------------------------------------------
    // `dragKind` is "" while idle. `dragSlot` is the index inside the column
    // being dragged (page-local for the app deck), `dragIndex` the same item
    // in the model that the reorder is committed against.
    property string dragKind: ""
    property int dragSlot: -1
    property int dragIndex: -1
    property int dropSlot: -1
    property real dragOffsetX: 0
    property real tiltAmount: 0
    property point pressPoint: Qt.point(0, 0)
    property real lastPointerX: 0
    property bool pressOnEmpty: false

    // --- Deck entrance -----------------------------------------------------
    // 0..1 ramp for the page-turn. Each tile derives its own progress from
    // this with a stagger, so the deck opens like a fan of cards instead of
    // all at once.
    property real deckEntrance: 1
    property real _autoScrollDir: 0
    // How far the deck has auto-scrolled during this drag. The pointer's own
    // delta is measured in island coordinates, so without this the card
    // snapped back by the scrolled distance the moment the pointer moved.
    property real _scrollComp: 0

    function appEntrance(index) {
        // Normalised against the tile count: dividing by a fixed span left
        // the last four tiles of a full page permanently mid-flip (a resting
        // 25 degree lean and 0.75 opacity) instead of settling flat.
        const count = Math.max(1, root.launchPageEntries.length)
        const span = 0.5
        const stagger = 0.06
        const total = span + (count - 1) * stagger
        return Math.max(0, Math.min(1,
            (root.deckEntrance * total - index * stagger) / span))
    }

    // An open picker, an open editor or a drag in flight owns the
    // interaction; the island must not close underneath it.
    Binding {
        target: IslandService
        property: "heldByOverlay"
        value: root.dragKind !== "" || root.editingWidgets
            || root.pickingApps || root.editingApps || root.openNotes
            || root.openFinder
    }

    function isWidgetEnabled(id) {
        return (config.enabledWidgetOrder || []).indexOf(id) >= 0
    }

    function moveWidget(from, to) {
        const order = (config.enabledWidgetOrder || []).slice()
        if (from < 0 || to < 0 || from >= order.length)
            return
        const clamped = Math.min(to, order.length - 1)
        if (clamped === from)
            return
        const moved = order.splice(from, 1)[0]
        order.splice(clamped, 0, moved)
        config.setEnabledWidgetOrder(order)
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.clockText = Qt.formatTime(new Date(), "HH:mm")
    }

    Timer {
        interval: 16
        repeat: true
        running: root.dragKind !== "" && root._autoScrollDir !== 0
        onTriggered: {
            const view = root.dragKind === "app" ? strip : widgetViewport
            const target = Math.max(0, Math.min(view.maxScroll,
                view.scrollX + root._autoScrollDir * 10))
            const moved = target - view.scrollX
            if (moved === 0)
                return
            view.scrollX = target
            // The row slides under the pointer, so the held tile has to be
            // given the same offset back or it would drift away from the
            // cursor while the deck scrolls.
            root._scrollComp += moved
            root.dragOffsetX += moved
            // The landing slot has to follow: nothing else recomputes it
            // while the pointer sits still against the edge, and a release
            // there would otherwise commit the slot from before the scroll.
            root._updateDrop()
        }
    }

    NumberAnimation {
        id: deckFlip
        target: root
        property: "deckEntrance"
        from: 0
        to: 1
        duration: 460
        easing.type: Easing.OutCubic
    }

    onLaunchPageChanged: if (root.reveal > 0.9) deckFlip.restart()

    // --- Hit testing ------------------------------------------------------
    // All tests convert the island-space pointer into the column's own
    // space. mapFromItem accounts for the column's scroll offset, so a
    // scrolled deck still hits the card under the pointer.
    function _localPoint(item, px, py) {
        return item.mapFromItem(root, px, py)
    }

    function widgetIndexAt(px, py) {
        if (root.reveal < 0.7 || !widgetRow.visible || widgetRow.height <= 0)
            return -1
        // The row can be wider than the viewport that clips it. mapFromItem
        // ignores clipping, so a press in the clipped-off part of the row
        // would still resolve to a card that is not on screen -- and, since
        // the widget column is tested before the application column, that
        // invisible strip would swallow presses meant for the first app
        // tile. The viewport's own rectangle is the real hit area.
        if (!_insideViewport(widgetViewport, px, py))
            return -1
        const p = _localPoint(widgetRow, px, py)
        if (p.y < 0 || p.y > widgetRow.height)
            return -1
        const i = Math.floor(p.x / root.widgetStep)
        if (i < 0 || i >= root.activeWidgets.length)
            return -1
        if (p.x - i * root.widgetStep > root.widgetCardWidth)
            return -1
        // The column is taller than the cards it holds, so the column's own
        // height is not the hit area: a press in the empty space above a card
        // would pick that card up, and in the application column the same
        // slack would launch an application the pointer never touched. The
        // delegate is asked for its own rectangle instead.
        return _withinDelegate(widgetRepeater, i, px, py) ? i : -1
    }

    function _insideViewport(viewport, px, py) {
        const v = _localPoint(viewport, px, py)
        return v.x >= 0 && v.y >= 0 && v.x <= viewport.width && v.y <= viewport.height
    }

    function _withinDelegate(repeater, index, px, py) {
        if (!repeater)
            return false
        const item = repeater.itemAt(index)
        if (!item)
            return false
        const q = item.mapFromItem(root, px, py)
        return q.x >= 0 && q.y >= 0 && q.x <= item.width && q.y <= item.height
    }

    function appIndexAt(px, py) {
        if (root.reveal < 0.7 || !launchRow.visible || launchRow.height <= 0)
            return -1
        if (!_insideViewport(strip, px, py))
            return -1
        const p = _localPoint(launchRow, px, py)
        if (p.y < 0 || p.y > launchRow.height)
            return -1
        const i = Math.floor(p.x / root.appStep)
        if (i < 0 || i >= root.launchPageEntries.length)
            return -1
        if (p.x - i * root.appStep > root.appTileWidth)
            return -1
        return _withinDelegate(appRepeater, i, px, py) ? i : -1
    }

    function _updateHover(px, py) {
        if (!IslandService.hovered) {
            hoverWidget = -1
            hoverApp = -1
            return
        }
        hoverWidget = root.dragKind === "" ? widgetIndexAt(px, py) : -1
        hoverApp = root.dragKind === "" ? appIndexAt(px, py) : -1
    }

    // --- Pointer entry points (called by IslandWindow) --------------------
    function pointerPressed(px, py) {
        pressOnEmpty = false
        if (root.editingWidgets || root.pickingApps || root.editingApps
                || root.openNotes || root.openFinder)
            return
        pressPoint = Qt.point(px, py)
        lastPointerX = px
        dragOffsetX = 0
        tiltAmount = 0

        const wi = widgetIndexAt(px, py)
        if (wi >= 0) {
            _beginDrag("widget", wi, wi)
            return
        }
        const ai = appIndexAt(px, py)
        if (ai >= 0) {
            _beginDrag("app", ai, root.launchPageStart + ai)
            return
        }
        pressOnEmpty = true
    }

    function pointerMoved(px, py) {
        _updateHover(px, py)
        if (root.dragKind === "")
            return

        // The pointer travels in island space, so this offset is the real
        // distance moved. Deriving it from the card's own coordinates would
        // make it depend on the offset being applied -- the card would move
        // half the distance, the tilt would flip sign every event, and the
        // tile would visibly buzz instead of following the pointer.
        dragOffsetX = (px - pressPoint.x) + root._scrollComp
        const speed = px - lastPointerX
        lastPointerX = px
        const wanted = Math.max(-1, Math.min(1, speed / 12))
        tiltAmount = tiltAmount * 0.55 + wanted * 0.45
        _updateDrop()

        // Dragging towards an edge of the deck scrolls it. Without this a
        // reorder can only ever reach the tiles that happen to be on screen,
        // which is why "too many programs" made the right column feel dead.
        if (root.dragKind !== "") {
            const view = root.dragKind === "app" ? strip : widgetViewport
            const v = _localPoint(view, px, py)
            const edge = Math.max(24, root.cardGap * 0.7)
            root._autoScrollDir = v.x > view.width - edge ? 1
                : (v.x < edge ? -1 : 0)
        }
    }

    function pointerReleased(px, py) {
        if (root.dragKind === "") {
            // A press that landed on nothing inside the island closes it,
            // the way the original's empty-area click does. In hover mode the
            // island already follows the pointer, and closing it there would
            // contradict the mode, so the toggle is left to click mode.
            // The mode lives on the configuration, not on IslandService.
            // The opacity guard exists to swallow clicks that land while the
            // body is still fading in -- it must not apply to the collapsed
            // pill, or click mode can never open the island at all: the body's
            // opacity is 0 exactly when the pill is what you are clicking.
            if (root.pressOnEmpty && root.config.expandMode !== "hover"
                    && IslandService.hitTest(px, py)
                    && (!IslandService.expanded || contentArea.opacity > 0.999))
                IslandService.toggle(null)
            root.pressOnEmpty = false
            return
        }

        const moved = Math.abs(px - root.pressPoint.x) > 4
            || Math.abs(py - root.pressPoint.y) > 4

        if (root.dragKind === "app") {
            if (moved) {
                if (root.dropSlot >= 0 && root.dropSlot !== root.dragSlot) {
                    const to = root.launchPageStart + root.dropSlot
                    if (to !== root.dragIndex)
                        IslandQuickLaunchModel.moveEntry(root.dragIndex, to)
                }
            } else {
                // A click, not a drag: launch the application.
                const entry = root.launchPageEntries[root.dragSlot]
                if (entry) {
                    const app = IslandQuickLaunchModel.entryFor(entry.id)
                    if (app && app.kind === "file") {
                        // A dropped file is a shortcut, and a shortcut can be
                        // moved behind the island's back. Ask the index where
                        // it went, repair the reference, then open it.
                        IslandFinderService.resolve(app.path, app.name,
                            function(resolved, found) {
                                if (found && resolved !== app.path)
                                    IslandConfigService.repinPath(app.path, resolved)
                                PlatformClient.request("file.open", { path: resolved },
                                    function(response) {
                                        if (!response || !response.ok)
                                            console.warn("[Island] file.open failed for " + resolved)
                                    })
                            })
                    } else if (app) {
                        AppActionService.launch(app)
                    }
                }
            }
        } else if (moved && root.dropSlot >= 0 && root.dropSlot !== root.dragSlot) {
            root.moveWidget(root.dragSlot, root.dropSlot)
        }

        _endDrag()
    }

    function pointerCancelled() {
        _endDrag()
    }

    function _beginDrag(kind, slot, index) {
        dragKind = kind
        dragSlot = slot
        dragIndex = index
        dropSlot = slot
        dragOffsetX = 0
        _scrollComp = 0
        tiltAmount = 0
        _updateHover(root.pressPoint.x, root.pressPoint.y)
    }

    function _updateDrop() {
        if (root.dragKind === "widget") {
            const last = Math.max(0, root.activeWidgets.length - 1)
            const current = root.dragSlot * root.widgetStep + root.dragOffsetX
            dropSlot = Math.max(0, Math.min(last,
                Math.round(current / root.widgetStep)))
        } else if (root.dragKind === "app") {
            const last = Math.max(0, root.launchPageEntries.length - 1)
            const current = root.dragSlot * root.appStep + root.dragOffsetX
            dropSlot = Math.max(0, Math.min(last,
                Math.round(current / root.appStep)))
        }
    }

    function _endDrag() {
        _autoScrollDir = 0
        _scrollComp = 0
        dragKind = ""
        dragSlot = -1
        dragIndex = -1
        dropSlot = -1
        dragOffsetX = 0
        tiltAmount = 0
        pressOnEmpty = false
    }

    // Wheel scrolling for the widget column. A Flickable would swallow the
    // press that starts a drag, and a WheelHandler on the column would live
    // inside the pointer area's hover chain; the surface owns the handler and
    // routes the wheel here instead.
    function handleWheel(px, py, angleDeltaY) {
        if (root.reveal < 0.7)
            return
        const step = angleDeltaY * 0.7
        const w = _localPoint(widgetViewport, px, py)
        if (w.x >= 0 && w.y >= 0 && w.x <= widgetViewport.width
                && w.y <= widgetViewport.height) {
            widgetViewport.scrollX = _clampScroll(
                widgetViewport.scrollX - step, widgetViewport.maxScroll)
            return
        }
        const a = _localPoint(strip, px, py)
        if (a.x >= 0 && a.y >= 0 && a.x <= strip.width && a.y <= strip.height)
            strip.scrollX = _clampScroll(strip.scrollX - step, strip.maxScroll)
    }

    function _clampScroll(value, maxValue) {
        return Math.max(0, Math.min(maxValue, value))
    }

    Connections {
        target: IslandService
        function onHoveredChanged() {
            root._updateHover(IslandService.pointerX, IslandService.pointerY)
        }

    }

    // ------------------------------------------------------------------
    // Top bar — add-components on the left, clock centred, edit on the right.
    // ------------------------------------------------------------------
    Item {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        // Collapsed, the bar is the whole island, so it is centred in the
        // capsule; expanded, it sits at the top of the panel. The margin is
        // negative while collapsed -- the bar is scaled for the expanded
        // panel and is taller than the 44px capsule -- and clamping it to
        // zero pushed the clock 17px below the capsule's centre, where the
        // surface clip cut its bottom off.
        anchors.topMargin: (1 - root.reveal) * (root.height - height) / 2
        height: root.barHeight

        // "添加组件" — adding a widget belongs to the widget column, so it
        // sits on the left of the bar, in front of it.
        Rectangle {
            id: addWidget
            anchors { left: parent.left; leftMargin: root.sidePadding
                      verticalCenter: parent.verticalCenter }
            readonly property int pillHeight: Math.round(root.barHeight * 0.62)
            width: addWidgetRow.implicitWidth + pillHeight
            height: pillHeight
            radius: pillHeight / 2
            visible: root.reveal > 0.2 && !root.editingWidgets && !root.pickingApps
            color: addWidgetHover.pressed
                ? Qt.rgba(1, 1, 1, 0.20)
                : (addWidgetHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Row {
                id: addWidgetRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: "+"
                    color: root.inkMuted
                    font.pixelSize: Math.max(11, Math.round(root.unit * 0.045))
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: I18n.tr("Add widget")
                    color: root.inkMuted
                    font.pixelSize: Math.max(11, Math.round(root.unit * 0.040))
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            IslandPointerTarget {
                id: addWidgetHover
                anchors.fill: parent
                pointerOrigin: root
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editingWidgets = true
            }
        }

        // The Finder. A separate entry point from the widget editor: one
        // finds files, the other changes what the island shows.
        Rectangle {
            id: finderButton
            anchors { left: addWidget.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
            width: finderLabel.implicitWidth + 14
            height: addWidget.height
            radius: height / 2
            visible: root.reveal > 0.2 && !root.editingWidgets && !root.pickingApps
                && !root.editingApps && !root.openNotes && !root.openFinder
            color: finderTarget.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Text {
                id: finderLabel
                anchors.centerIn: parent
                text: I18n.tr("Find")
                color: root.inkMuted
                font.pixelSize: 10
            }

            IslandPointerTarget {
                id: finderTarget
                anchors.fill: parent
                pointerOrigin: root
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openFinder = true
            }
        }

        // The idle rings. Notchy's island keeps breathing when there is
        // nothing to show; here they sit in the collapsed pill beside the
        // clock, and only while no media is playing -- otherwise the pill
        // would have two things talking at once.
        IslandIdleRings {
            id: idleRings
            width: 16
            height: 16
            visible: root.reveal < 0.5
            // The clock is centred in the pill, so the left end is free.
            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
            active: root.reveal < 0.5 && !DockMprisService.hasPlayingPlayer
            ringColor: root.ink
            ringOpacity: 0.22
        }

        // The clock. Centred in the collapsed capsule, which is the only
        // thing the resting island shows.
        // The collapsed capsule is the clock. Once the panel is open the
        // reference puts the time inside the content (its clock/weather
        // widget) rather than in the bar, so the bar clock fades out instead
        // of competing with it.
        Text {
            anchors.centerIn: parent
            text: root.clockText
            color: root.reveal > 0.35 ? root.inkMuted : root.ink
            font.pixelSize: root.reveal > 0.35 ? 11 : 12
            font.letterSpacing: 0.4
            font.bold: root.reveal < 0.35
            opacity: Math.max(0, 1 - root.reveal * 1.8)
            visible: opacity > 0.01

            Behavior on color { ColorAnimation { duration: 160 } }
        }

        // "编辑组件" — a pill with the grid glyph and the label, the same
        // control the reference puts at the panel's top right.
        Rectangle {
            id: editEntry
            anchors { right: parent.right; rightMargin: root.sidePadding
                      verticalCenter: parent.verticalCenter }
            readonly property int pillHeight: Math.round(root.barHeight * 0.62)
            width: editRow.implicitWidth + pillHeight
            height: pillHeight
            radius: pillHeight / 2
            visible: root.reveal > 0.2 && !root.editingWidgets && !root.pickingApps
            color: editHover.pressed
                ? Qt.rgba(1, 1, 1, 0.20)
                : (editHover.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Row {
                id: editRow
                anchors.centerIn: parent
                spacing: 5

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 2.5
                    color: "transparent"
                    border.width: 1
                    border.color: root.inkMuted

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2.5
                        height: 2.5
                        radius: 1.25
                        color: root.inkMuted
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Edit programs")
                    color: root.inkMuted
                    font.pixelSize: Math.max(11, Math.round(root.unit * 0.040))
                }
            }

            IslandPointerTarget {
                id: editHover
                anchors.fill: parent
                pointerOrigin: root
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editingApps = true
            }
        }
    }

    // ------------------------------------------------------------------
    // Body — widgets on the left, pinned applications on the right.
    // ------------------------------------------------------------------
    Item {
        id: contentArea
        // Position and height are explicit rather than anchored top+bottom:
        // while collapsed the bar is taller than the gap left under it, and
        // an anchored body computed a negative height and handed the layout
        // nonsense for the first half of the animation.
        readonly property int sideMargin: root.sidePadding
        readonly property int bottomMargin: root.bottomPadding
        anchors { left: parent.left; right: parent.right
                  leftMargin: sideMargin; rightMargin: sideMargin }
        y: bar.y + bar.height + 2
        height: Math.max(0, parent.height - y - bottomMargin)
        // The cards are a fixed fraction of the *expanded* height, so for
        // most of the animation the body is shorter than a card. The fade is
        // therefore driven by the body's own height against the card height,
        // not by a reveal constant: at reveal 0.36 the body was still 15px
        // tall while the cards were being drawn at 157px, straight over the
        // bar.
        readonly property real cardFit: Math.max(0, Math.min(1,
            (height - root.widgetCardHeight * 0.70)
                / Math.max(1, root.widgetCardHeight * 0.50)))
        opacity: cardFit
        visible: opacity > 0.01

        // Start the page-turn when the body first appears, not when the
        // island starts expanding: the flip used to spend its first 40% inside
        // a fully transparent body.
        onCardFitChanged: {
            if (cardFit > 0.05 && root.deckEntrance >= 1)
                deckFlip.restart()
        }

        RowLayout {
            anchors.fill: parent
            spacing: root.cardGap
            // The two-column shelf is the default; the card layout replaces
            // it rather than sitting beside it.
            visible: root.layoutMode !== "cards"

            // --- Widget column ---------------------------------------------
            // Content-sized, not half the panel: the reference packs its
            // widgets and applications against the left edge and leaves the
            // right of the slab empty, so a 50/50 split put the divider in
            // the middle of nothing.
            Item {
                id: widgetViewport
                Layout.fillWidth: false
                Layout.fillHeight: true
                // One third of the panel, as asked: the widget side is a
                // shelf, not the main room, and the rest of the width belongs
                // to the applications.
                Layout.preferredWidth: Math.min(
                    Math.max(120, root.activeWidgets.length * root.widgetStep),
                    Math.max(140, root.width / 3))
                clip: true

                property real scrollX: 0
                readonly property real maxScroll:
                    Math.max(0, widgetRow.width - width)
                onMaxScrollChanged: {
                    if (scrollX > maxScroll)
                        scrollX = maxScroll
                }

                Item {
                    id: widgetRow
                    x: -widgetViewport.scrollX
                    height: widgetViewport.height
                    width: Math.max(widgetViewport.width,
                        root.activeWidgets.length * root.widgetStep)

                    Repeater {
                        id: widgetRepeater
                        model: root.activeWidgets

                        delegate: IslandWidgetSlot {
                            required property var modelData
                            required property int index

                            readonly property bool isDragSource:
                                root.dragKind === "widget" && root.dragSlot === index

                            x: index * root.widgetStep
                                + (isDragSource ? root.dragOffsetX : 0)
                            y: Math.round((widgetViewport.height - height) / 2)
                            z: isDragSource ? 100 : 1
                            width: root.widgetCardWidth
                            height: root.widgetCardHeight
                            cornerRadius: Math.round(root.widgetCardHeight * 0.20)
                            flipAngle: root.foldFor(index)
                            foldLean: index % 2 === 0 ? 1 : -1

                            widgetId: modelData.id
                            widgetName: modelData.name
                            onOpenNotesRequested: root.openNotes = true
                            hovered: root.hoverWidget === index
                            dragging: isDragSource
                            tilt: isDragSource ? root.tiltAmount : 0

                            Behavior on x {
                                enabled: !isDragSource
                                NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    // The same overflow affordance the application deck has:
                    // a shelf that keeps going must say so, or the last
                    // visible card looks like the last card.
                    Rectangle {
                        // These live inside the scrolling row, so pinning
                        // them to the viewport means adding the scroll offset
                        // back to x -- an anchor cannot do that.
                        x: widgetViewport.scrollX + widgetViewport.width - width
                        y: Math.round((widgetRow.height - height) / 2)
                        width: 20
                        height: 20
                        radius: 10
                        z: 300
                        color: Qt.rgba(0, 0, 0, 0.62)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.20)
                        visible: widgetViewport.maxScroll > 0
                            && widgetViewport.scrollX < widgetViewport.maxScroll - 1

                        Text {
                            anchors.centerIn: parent
                            text: "\u203A"
                            color: root.ink
                            font.pixelSize: 13
                        }

                        IslandPointerTarget {
                            anchors.fill: parent
                            pointerOrigin: root
                            cursorShape: Qt.PointingHandCursor
                            onClicked: widgetViewport.scrollX = Math.min(
                                widgetViewport.maxScroll,
                                widgetViewport.scrollX + root.widgetStep)
                        }
                    }

                    Rectangle {
                        x: widgetViewport.scrollX
                        y: Math.round((widgetRow.height - height) / 2)
                        width: 20
                        height: 20
                        radius: 10
                        z: 300
                        color: Qt.rgba(0, 0, 0, 0.62)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.20)
                        visible: widgetViewport.scrollX > 1

                        Text {
                            anchors.centerIn: parent
                            text: "\u2039"
                            color: root.ink
                            font.pixelSize: 13
                        }

                        IslandPointerTarget {
                            anchors.fill: parent
                            pointerOrigin: root
                            cursorShape: Qt.PointingHandCursor
                            onClicked: widgetViewport.scrollX = Math.max(0,
                                widgetViewport.scrollX - root.widgetStep)
                        }
                    }

                    // The landing marker, on the edge the card would land on.
                    Rectangle {
                        width: 2
                        height: root.widgetCardHeight - 28
                        radius: 1
                        color: root.accentA(0.95)
                        visible: root.dragKind === "widget"
                            && root.dropSlot >= 0
                            && root.dropSlot !== root.dragSlot
                        x: Math.max(0, root.dropSlot > root.dragSlot
                            ? (root.dropSlot + 1) * root.widgetStep - 6
                            : root.dropSlot * root.widgetStep - 4)
                        y: Math.round((widgetViewport.height - height) / 2)
                        z: 200
                    }
                }
            }

            // --- The card layout ---------------------------------------------
            // Notchy's home: a rail on the left picks the page, and the
            // panel shows one card at a time. The same widgets and the same
            // tiles are used -- only the arrangement changes -- so the
            // columns layout stays the default and can be switched back.
            RowLayout {
                id: cardsMode
                anchors.fill: parent
                spacing: 0
                visible: root.layoutMode === "cards"

                // The rail.
                ColumnLayout {
                    Layout.preferredWidth: Math.max(56, Math.round(root.width * 0.055))
                    Layout.fillHeight: true
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "widgets", label: I18n.tr("Widgets") },
                            { id: "apps", label: I18n.tr("Programs") },
                            { id: "usage", label: I18n.tr("Screen time") },
                            { id: "displays", label: I18n.tr("Displays") },
                            { id: "actions", label: I18n.tr("Quick actions") },
                            { id: "clipboard", label: I18n.tr("Clipboard") }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            readonly property bool current: root.cardPage === modelData.id

                            Layout.fillWidth: true
                            height: 30
                            radius: 8
                            color: current ? Qt.rgba(1, 1, 1, 0.12)
                                : (railTarget.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: current ? root.ink : root.inkMuted
                                font.pixelSize: 10
                            }

                            IslandPointerTarget {
                                id: railTarget
                                anchors.fill: parent
                                pointerOrigin: root
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.cardPage = modelData.id
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // The card.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 8
                    radius: 18
                    clip: true
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    // Widgets: one card at a time, with the pager arrows.
                    Item {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.cardPage === "widgets"

                        RowLayout {
                            anchors.fill: parent
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 14
                                color: "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    spacing: 4

                                    // Only the current widget's card is
                                    // visible; a layout ignores invisible
                                    // items, so the visible one takes the
                                    // whole card.
                                    Repeater {
                                        model: root.activeWidgets

                                        delegate: IslandWidgetSlot {
                                            required property var modelData
                                            required property int index

                                            visible: index === root.cardWidgetIndex
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true

                                            widgetId: modelData.id
                                            widgetName: modelData.name
                                            onOpenNotesRequested: root.openNotes = true
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 22
                                Layout.fillHeight: true
                                color: "transparent"

                                Column {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                    spacing: 4

                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        visible: root.activeWidgets.length > 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u2039"
                                            color: root.inkMuted
                                            font.pixelSize: 12
                                        }
                                        IslandPointerTarget {
                                            anchors.fill: parent
                                            pointerOrigin: root
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.cardWidgetIndex = Math.max(0, root.cardWidgetIndex - 1)
                                        }
                                    }

                                    Rectangle {
                                        width: 22; height: 22; radius: 11
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        visible: root.activeWidgets.length > 1
                                        Text {
                                            anchors.centerIn: parent
                                            text: "\u203A"
                                            color: root.inkMuted
                                            font.pixelSize: 12
                                        }
                                        IslandPointerTarget {
                                            anchors.fill: parent
                                            pointerOrigin: root
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.cardWidgetIndex = Math.min(root.activeWidgets.length - 1, root.cardWidgetIndex + 1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The three cards Notchy's home carries beside the
                    // launcher. They are the same components the shelf
                    // uses -- the rail is a view switch, not a second
                    // implementation.
                    IslandUsageWidget {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.cardPage === "usage"
                        widgetId: "usage"
                    }

                    IslandDisplaysWidget {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.cardPage === "displays"
                        widgetId: "displays"
                    }

                    IslandActionsWidget {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.cardPage === "actions"
                        widgetId: "actions"
                    }

                    IslandClipboardWidget {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.cardPage === "clipboard"
                        widgetId: "clipboard"
                    }

                    // Nothing to show: the rings breathe instead of an empty
                    // card. The island is never just a hole in the desktop.
                    IslandIdleRings {
                        anchors.centerIn: parent
                        width: 72
                        height: 72
                        visible: root.cardPage === "widgets"
                            && root.activeWidgets.length === 0
                        active: visible
                        ringColor: root.ink
                        ringOpacity: 0.16
                    }

                    // Programs: the tiles in a grid inside the card.
                    Item {
                        anchors.fill: parent
                        anchors.margins: 8
                        visible: root.cardPage === "apps"

                        Grid {
                            id: cardAppGrid
                            columns: Math.max(1, Math.floor(width / (root.appTileWidth + 12)))
                            width: parent.width
                            spacing: 10

                            Repeater {
                                model: root.launchPageEntries

                                delegate: IslandAppTile {
                                    required property var modelData
                                    required property int index

                                    width: root.appTileWidth
                                    height: root.appTileHeight
                                    cornerRadius: Math.round(root.appTileHeight * 0.24)

                                    desktopId: modelData.id
                                    appName: modelData.name || modelData.id
                                    dragOutUri: modelData.kind === "file"
                                        ? root.fileUri(modelData.path) : ""
                                    dragOutEnabled: modelData.kind === "file"
                                    iconSource: modelData.icon

                                    Behavior on x { NumberAnimation { duration: 170 } }
                                }
                            }
                        }
                    }
                }
            }

            // --- The divider -----------------------------------------------
            Rectangle {
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                color: root.accentA(0.30)
            }

            // --- Application column ----------------------------------------
            ColumnLayout {
                id: appColumn
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.preferredWidth: Math.min(
                    Math.max(120, (root.launchPageEntries.length + 1) * root.appStep),
                    root.columnBudget * 0.48)
                spacing: 4

                Item {
                    id: strip
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // The deck can hold more tiles than the column is wide.
                    // Paging alone does not make them reachable: the page size
                    // is a preference (12 by default) and only about five
                    // tiles fit the column at the default geometry, so the
                    // rest would be clipped with no way to reach them. The
                    // strip scrolls as well, like the widget column.
                    property real scrollX: 0
                    readonly property real maxScroll: Math.max(0, launchRow.width - width)
                    onMaxScrollChanged: {
                        if (scrollX > maxScroll)
                            scrollX = maxScroll
                    }

                    Item {
                        id: launchRow
                        x: -strip.scrollX
                        height: strip.height
                        width: Math.max(strip.width,
                            (root.launchPageEntries.length + 1) * root.appStep)

                        Repeater {
                            id: appRepeater
                            model: root.launchPageEntries

                            delegate: IslandAppTile {
                                required property var modelData
                                required property int index

                                readonly property bool isDragSource:
                                    root.dragKind === "app" && root.dragSlot === index

                                x: index * root.appStep
                                    + (isDragSource ? root.dragOffsetX : 0)
                                y: Math.round((strip.height - height) / 2)
                                z: isDragSource ? 100 : 1
                                width: root.appTileWidth
                                height: root.appTileHeight
                                cornerRadius: Math.round(root.appTileHeight * 0.24)

                                desktopId: modelData.id
                                appName: modelData.name || modelData.id
                                // A shelved file gets a grip that can be
                                // dragged out into another application.
                                dragOutUri: modelData.kind === "file"
                                    ? root.fileUri(modelData.path) : ""
                                dragOutEnabled: modelData.kind === "file"
                                iconSource: modelData.icon
                                hovered: root.hoverApp === index
                                dragging: isDragSource
                                tilt: isDragSource ? root.tiltAmount : 0

                                // The page-turn. Staggered by index, so the
                                // deck fans open from the first tile outward
                                // instead of every icon appearing at once.
                                readonly property real entrance: root.appEntrance(index)
                                flipAngle: root.foldFor(root.launchPageStart + index)
                                    - 88 * (1 - entrance)
                                foldLean: (root.launchPageStart + index) % 2 === 0 ? 1 : -1
                                opacity: 0.15 + 0.85 * entrance

                                Behavior on x {
                                    enabled: !isDragSource
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // The landing marker for the application drag.
                        Rectangle {
                            width: 2
                            height: root.appTileHeight - 28
                            radius: 1
                            color: root.accentA(0.95)
                            visible: root.dragKind === "app"
                                && root.dropSlot >= 0
                                && root.dropSlot !== root.dragSlot
                            x: Math.max(0, root.dropSlot > root.dragSlot
                                ? (root.dropSlot + 1) * root.appStep - 6
                                : root.dropSlot * root.appStep - 4)
                            y: Math.round((strip.height - height) / 2)
                            z: 200
                        }

                        // "添加程序" — opens the application picker, which
                        // lists everything installed on the system.
                        IslandCard {
                            x: root.launchPageEntries.length * root.appStep
                            y: Math.round((strip.height - height) / 2)
                            width: root.appTileWidth
                            height: root.appTileHeight
                            cornerRadius: 23
                            depth: 0.7
                            bodyColor: Qt.rgba(1, 1, 1, 0.035)
                            bodyBorderColor: addAppHover.hovered
                                ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.13)
                            lift: addAppHover.hovered ? 0.35 : 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "+"
                                    color: root.inkMuted
                                    font.pixelSize: Math.max(16, Math.round(root.appTileWidth * 0.22))
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: I18n.tr("Add app")
                                    color: root.inkFaint
                                    font.pixelSize: Math.max(10, Math.round(root.appTileWidth * 0.11))
                                }
                            }

                            IslandPointerTarget {
                                id: addAppHover
                                anchors.fill: parent
                                pointerOrigin: root
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.appSearch = ""
                                    root.pickingApps = true
                                }
                            }
                        }
                    }

                    // --- Overflow affordances -----------------------------
                    // With more programs than the column is wide, the last
                    // visible tile looked exactly like the last tile.
                    // These say the deck continues and move it two tiles
                    // at a time -- the part a wheel alone never made
                    // discoverable.
                    Rectangle {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 20
                        height: 20
                        radius: 10
                        z: 300
                        color: Qt.rgba(0, 0, 0, 0.55)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                        visible: strip.maxScroll > 0 && strip.scrollX < strip.maxScroll - 1

                        Text {
                            anchors.centerIn: parent
                            text: "\u203A"
                            color: root.ink
                            font.pixelSize: 13
                        }

                        IslandPointerTarget {
                            anchors.fill: parent
                            pointerOrigin: root
                            cursorShape: Qt.PointingHandCursor
                            onClicked: strip.scrollX = Math.min(strip.maxScroll,
                            strip.scrollX + root.appStep * 2)
                        }
                    }

                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 20
                        height: 20
                        radius: 10
                        z: 300
                        color: Qt.rgba(0, 0, 0, 0.55)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                        visible: strip.scrollX > 1

                        Text {
                            anchors.centerIn: parent
                            text: "\u2039"
                            color: root.ink
                            font.pixelSize: 13
                        }

                        IslandPointerTarget {
                            anchors.fill: parent
                            pointerOrigin: root
                            cursorShape: Qt.PointingHandCursor
                            onClicked: strip.scrollX = Math.max(0,
                            strip.scrollX - root.appStep * 2)
                        }
                    }

                }

                // The page cursor — the original's quick-launch pager.
                Row {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.launchPageCount > 1

                    Text {
                        text: "\u2039"
                        color: root.inkFaint
                        font.pixelSize: 15
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.launchPage = Math.max(0, root.launchPage - 1)
                        }
                    }

                    Text {
                        text: I18n.tr("%1 / %2").arg(root.launchPage + 1).arg(root.launchPageCount)
                        color: root.inkFaint
                        font.pixelSize: 10
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "\u203A"
                        color: root.inkFaint
                        font.pixelSize: 15
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.launchPage = Math.min(
                                root.launchPageCount - 1, root.launchPage + 1)
                        }
                    }
                }
            }

            // The rest of the slab is deliberately empty, exactly like the
            // reference: the panel is far wider than the content it holds.
            Item { Layout.fillWidth: true }
        }
    }

    // ------------------------------------------------------------------
    // Widget editor — the original's "编辑组件" panel.
    // ------------------------------------------------------------------
    Rectangle {
        id: editPanel
        anchors.fill: parent
        visible: root.editingWidgets
        radius: 16
        color: Qt.rgba(0.05, 0.06, 0.09, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        ColumnLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: I18n.tr("Edit components")
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: doneLabel.implicitWidth + 14
                    implicitHeight: 20
                    radius: 10
                    color: Qt.rgba(0.29, 0.87, 0.5, 0.85)

                    Text {
                        id: doneLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: Qt.rgba(0.04, 0.2, 0.12, 1)
                        font.pixelSize: 10
                        font.bold: true
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        onClicked: root.editingWidgets = false
                    }
                }
            }

            // A single column of full-width rows.
            //
            // The two-column grid this replaces made the target ambiguous: a
            // row was half the panel wide, and because the editor re-sorted
            // itself on every toggle, the component under the pointer changed
            // between clicks. One row, one target, one widget -- and the row
            // height is derived from the available height so all seven
            // entries fit without scrolling.
            Item {
                id: editGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                readonly property real rowHeight: Math.max(20, Math.min(34,
                    Math.floor(height / Math.max(1, root.editModel.length))))

                Column {
                    id: editList
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.editModel

                        delegate: Rectangle {
                            required property var modelData

                            readonly property bool widgetOn: root.isWidgetEnabled(modelData.id)

                            width: editList.width
                            height: editGrid.rowHeight
                            radius: 8
                            color: rowTarget.hovered
                                ? Qt.rgba(1, 1, 1, 0.10)
                                : Qt.rgba(1, 1, 1, widgetOn ? 0.07 : 0.03)

                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: widgetOn ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.42)
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                // The switch is a drawing, not a control: the
                                // whole row is the target, so the row can
                                // never disagree with what it toggles.
                                Rectangle {
                                    implicitWidth: 28
                                    implicitHeight: 15
                                    radius: 7.5
                                    color: widgetOn
                                        ? Qt.rgba(0.29, 0.87, 0.5, 0.9)
                                        : Qt.rgba(1, 1, 1, 0.14)

                                    Rectangle {
                                        width: 11
                                        height: 11
                                        radius: 5.5
                                        color: "white"
                                        x: widgetOn ? parent.width - 13 : 2
                                        anchors.verticalCenter: parent.verticalCenter

                                        Behavior on x { NumberAnimation { duration: 120 } }
                                    }
                                }
                            }

                            IslandPointerTarget {
                                id: rowTarget
                                anchors.fill: parent
                                pointerOrigin: root
                                cursorShape: Qt.PointingHandCursor
                                onClicked: config.toggleWidget(modelData.id, !widgetOn)
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Program order — the top-right control's panel.
    //
    // Reordering by dragging inside the deck only works while both tiles are
    // on screen; with more programs than the strip is wide, that is a
    // coin-toss. This lists every pinned program once, full width, with
    // explicit up/down -- the same reasoning as the widget editor: one row,
    // one target, and nothing re-sorts itself underneath the pointer.
    // ------------------------------------------------------------------
    Rectangle {
        id: appOrderPanel
        anchors.fill: parent
        visible: root.editingApps
        radius: 16
        color: Qt.rgba(0.05, 0.06, 0.09, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        readonly property var entries: IslandQuickLaunchModel.entries || []

        ColumnLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: I18n.tr("Edit programs")
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: orderDoneLabel.implicitWidth + 14
                    implicitHeight: 20
                    radius: 10
                    color: Qt.rgba(0.29, 0.87, 0.5, 0.85)

                    Text {
                        id: orderDoneLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: Qt.rgba(0.04, 0.2, 0.12, 1)
                        font.pixelSize: 10
                        font.bold: true
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.editingApps = false
                    }
                }
            }

            Item {
                id: orderArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                readonly property real rowHeight: Math.max(22, Math.min(38,
                    Math.floor(height / Math.max(1, appOrderPanel.entries.length))))

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    visible: appOrderPanel.entries.length === 0
                    text: I18n.tr("No programs pinned yet")
                    color: root.inkFaint
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Column {
                    id: orderList
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: appOrderPanel.entries

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index

                            readonly property int count: appOrderPanel.entries.length
                            readonly property string iconSource:
                                modelData.icon && String(modelData.icon).length > 0
                                    ? modelData.icon : ""

                            width: orderList.width
                            height: orderArea.rowHeight
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.05)

                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 4 }
                                spacing: 6

                                AppIcon {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    source: iconSource
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || modelData.id || ""
                                    color: Qt.rgba(1, 1, 1, 0.88)
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                // Explicit buttons, not drag: the row is
                                // 30px tall and a drag inside a list that
                                // reorders itself is how the widget editor
                                // lost people's clicks.
                                Repeater {
                                    model: [
                                        { glyph: "\u2039", action: "up" },
                                        { glyph: "\u203A", action: "down" },
                                        { glyph: "\u00D7", action: "unpin" }
                                    ]

                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index

                                        readonly property bool available:
                                            modelData.action === "up" ? row.index > 0
                                            : modelData.action === "down"
                                                ? row.index < row.count - 1 : true

                                        implicitWidth: 22
                                        implicitHeight: 22
                                        radius: 11
                                        color: Qt.rgba(1, 1, 1, available ? 0.10 : 0.04)

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.glyph
                                            color: Qt.rgba(1, 1, 1, available ? 0.75 : 0.25)
                                            font.pixelSize: 12
                                        }

                                        IslandPointerTarget {
                                            anchors.fill: parent
                                            pointerOrigin: root
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (!available)
                                                    return
                                                if (modelData.action === "up")
                                                    IslandQuickLaunchModel.moveEntry(row.index, row.index - 1)
                                                else if (modelData.action === "down")
                                                    IslandQuickLaunchModel.moveEntry(row.index, row.index + 1)
                                                else
                                                    IslandQuickLaunchModel.togglePin(row.modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Notes -- the memo store.
    //
    // The card is a preview; this is the application. The panel owns the
    // keyboard, which is why `wantsKeyboard` exists: the island only asks the
    // layer surface for focus while something that can be typed into is open.
    // ------------------------------------------------------------------
    Rectangle {
        id: notesPanel
        anchors.fill: parent
        visible: root.openNotes
        radius: 16
        color: Qt.rgba(0.05, 0.06, 0.09, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        Keys.onEscapePressed: root.openNotes = false

        ColumnLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: I18n.tr("Notes")
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Where the files actually are. It is the one setting a
                // document store cannot hide: a note you cannot find is a note
                // you lost.
                Text {
                    Layout.maximumWidth: Math.round(root.width * 0.42)
                    text: IslandNotesService.folder
                    color: root.inkFaint
                    font.pixelSize: 9
                    elide: Text.ElideMiddle
                }

                Rectangle {
                    implicitWidth: previewLabel.implicitWidth + 12
                    implicitHeight: 18
                    radius: 9
                    color: root.notesPreview ? root.accentA(0.55) : Qt.rgba(1, 1, 1, 0.08)

                    Text {
                        id: previewLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Preview")
                        color: root.notesPreview ? Qt.rgba(0.04, 0.2, 0.12, 1) : root.inkMuted
                        font.pixelSize: 9
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.notesPreview = !root.notesPreview
                    }
                }

                Rectangle {
                    implicitWidth: notesDoneLabel.implicitWidth + 14
                    implicitHeight: 18
                    radius: 9
                    color: Qt.rgba(0.29, 0.87, 0.5, 0.85)

                    Text {
                        id: notesDoneLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: Qt.rgba(0.04, 0.2, 0.12, 1)
                        font.pixelSize: 9
                        font.bold: true
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openNotes = false
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                // --- the list ---------------------------------------------
                Rectangle {
                    Layout.preferredWidth: Math.round(root.width * 0.30)
                    Layout.fillHeight: true
                    radius: 10
                    clip: true
                    color: Qt.rgba(1, 1, 1, 0.04)

                    Column {
                        anchors { fill: parent; topMargin: 4 }
                        spacing: 2

                        Repeater {
                            model: IslandNotesService.sorted

                            delegate: Rectangle {
                                required property var modelData

                                readonly property bool active:
                                    modelData.id === IslandNotesService.activeId

                                width: parent.width
                                height: 20
                                color: active ? Qt.rgba(1, 1, 1, 0.10)
                                    : (noteRow.hovered ? Qt.rgba(1, 1, 1, 0.06) : "transparent")

                                Text {
                                    anchors {
                                        left: parent.left
                                        right: removeTarget.anchors.left
                                        leftMargin: 8
                                        rightMargin: 4
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: (modelData.title && String(modelData.title).length > 0)
                                        ? modelData.title : I18n.tr("Untitled note")
                                    color: Qt.rgba(1, 1, 1, 0.85)
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    id: removeTarget
                                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                                    width: 14
                                    height: 14
                                    radius: 7
                                    color: Qt.rgba(1, 1, 1, removeNote.hovered ? 0.18 : 0.06)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u00D7"
                                        color: root.inkMuted
                                        font.pixelSize: 10
                                    }

                                    IslandPointerTarget {
                                        id: removeNote
                                        anchors.fill: parent
                                        pointerOrigin: root
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: IslandNotesService.deleteNote(modelData.id)
                                    }
                                }

                                IslandPointerTarget {
                                    id: noteRow
                                    anchors.fill: parent
                                    pointerOrigin: root
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: IslandNotesService.openNote(modelData.id)
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                        width: 20
                        height: 20
                        radius: 10
                        color: addNote.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: root.ink
                            font.pixelSize: 13
                        }

                        IslandPointerTarget {
                            id: addNote
                            anchors.fill: parent
                            pointerOrigin: root
                            cursorShape: Qt.PointingHandCursor
                            onClicked: IslandNotesService.createNote()
                        }
                    }
                }

                // --- the editor --------------------------------------------
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 10
                    color: Qt.rgba(0, 0, 0, 0.28)

                    // The title. A note is a memo: the title is its own
                    // field, not something the user has to guess is the first
                    // line of the body. It is the first line of the file, so
                    // the note still reads correctly in any other editor.
                    TextInput {
                        id: noteTitle
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            leftMargin: 8
                            rightMargin: 8
                            topMargin: 6
                        }
                        height: 18
                        color: Qt.rgba(1, 1, 1, 0.95)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        clip: true
                        selectByMouse: true

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            visible: !noteTitle.text.length
                            text: I18n.tr("Title")
                            color: Qt.rgba(1, 1, 1, 0.25)
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        onTextEdited: {
                            if (!root.applyingNote)
                                noteSave.restart()
                        }
                    }

                    TextEdit {
                        id: noteEditor
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: noteTitle.bottom
                            bottom: parent.bottom
                            leftMargin: 8
                            rightMargin: 8
                            bottomMargin: 16
                        }
                        visible: !root.notesPreview
                        color: Qt.rgba(1, 1, 1, 0.9)
                        font.pixelSize: 11
                        // A note is source, not prose: the editor is monospaced
                        // so the Markdown reads as Markdown.
                        font.family: "monospace"
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        renderType: TextEdit.Native

                        onTextChanged: {
                            if (!root.applyingNote)
                                noteSave.restart()
                        }
                    }

                    Flickable {
                        anchors { fill: parent; margins: 8 }
                        visible: root.notesPreview
                        contentWidth: width
                        contentHeight: previewText.implicitHeight
                        clip: true

                        Text {
                            id: previewText
                            width: parent.width
                            text: root.markdownToHtml(noteEditor.text)
                            textFormat: Text.RichText
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                  leftMargin: 8; rightMargin: 8; bottomMargin: 3 }
                        text: IslandNotesService.busy ? I18n.tr("Saving…")
                            : (IslandNotesService.lastError.length > 0
                                ? IslandNotesService.lastError : IslandNotesService.folder)
                        color: IslandNotesService.lastError.length > 0
                            ? Qt.rgba(0.95, 0.45, 0.35, 0.95) : root.inkFaint
                        font.pixelSize: 9
                        elide: Text.ElideMiddle
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: noteEditor.text.length === 0 && !root.notesPreview
                        text: I18n.tr("Write in Markdown…")
                        color: Qt.rgba(1, 1, 1, 0.22)
                        font.pixelSize: 11
                    }
                }
            }
        }

        // Debounced write. Typing must not produce one daemon request per
        // keystroke; the note is a file, and a file is written whole.
        Timer {
            id: noteSave
            interval: 400
            onTriggered: {
                if (root.applyingNote || IslandNotesService.activeId.length === 0)
                    return
                IslandNotesService.saveTitle(noteTitle.text)
                IslandNotesService.saveText(noteEditor.text)
            }
        }

        function pull() {
            root.applyingNote = true
            noteTitle.text = IslandNotesService.activeTitle
            noteEditor.text = IslandNotesService.activeText
            root.applyingNote = false
        }

        onVisibleChanged: {
            if (!visible)
                return
            pull()
            // The panel is the island's keyboard owner while it is open, and
            // the caret has to land somewhere the user can type into.
            noteTitle.forceActiveFocus()
        }

        Connections {
            target: IslandNotesService
            // The load signal, not the text property: the text also changes
            // when a save echoes it back, and reloading the editor then would
            // move the caret out from under the user.
            function onLoadRevisionChanged() {
                if (notesPanel.visible)
                    notesPanel.pull()
            }
        }
    }

    // ------------------------------------------------------------------
    // Finder — a search field over the data service's file index.
    //
    // Islet searches with `fd` and `fzf`; this shell may not run external
    // commands from its UI, so the walk and the fuzzy match live in the data
    // service and this is only the surface. The field takes the keyboard
    // while it is open, which is why wantsKeyboard counts it.
    // ------------------------------------------------------------------
    Rectangle {
        id: finderPanel
        anchors.fill: parent
        visible: root.openFinder
        radius: 16
        color: Qt.rgba(0.05, 0.06, 0.09, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        Keys.onEscapePressed: root.openFinder = false

        function openFirst() {
            const list = IslandFinderService.results || []
            if (list.length > 0)
                PlatformClient.request("file.open", { path: list[0].path },
                    function(response) {
                        if (!response || !response.ok)
                            console.warn("[Island] file.open failed")
                    })
        }

        ColumnLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: I18n.tr("Find files")
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }

                // A plain TextInput, not a Controls TextField: the island
                // keeps exactly one hover source and a Control brings its own.
                TextInput {
                    id: finderInput
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    color: "white"
                    font.pixelSize: 12
                    selectionColor: root.accentA(0.5)
                    selectedTextColor: "white"
                    clip: true

                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        visible: !finderInput.text.length
                        text: I18n.tr("Type to search…")
                        color: Qt.rgba(1, 1, 1, 0.28)
                        font.pixelSize: 12
                    }

                    onTextChanged: IslandFinderService.setQuery(text)
                    onAccepted: finderPanel.openFirst()
                }

                Text {
                    text: IslandFinderService.ready
                        ? I18n.tr("%1 files indexed").arg(IslandFinderService.indexed)
                        : I18n.tr("Indexing…")
                    color: root.inkFaint
                    font.pixelSize: 9
                }

                Rectangle {
                    implicitWidth: finderDoneLabel.implicitWidth + 14
                    implicitHeight: 18
                    radius: 9
                    color: Qt.rgba(0.29, 0.87, 0.5, 0.85)

                    Text {
                        id: finderDoneLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: Qt.rgba(0.04, 0.2, 0.12, 1)
                        font.pixelSize: 9
                        font.bold: true
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openFinder = false
                    }
                }
            }

            ListView {
                id: finderList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: IslandFinderService.results

                delegate: Rectangle {
                    required property var modelData

                    width: finderList.width
                    height: 26
                    radius: 6
                    color: resultRow.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                    Column {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: 8
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 0

                        Text {
                            width: parent.width
                            text: modelData.name || modelData.path
                            color: Qt.rgba(1, 1, 1, 0.9)
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }

                        Text {
                            width: parent.width
                            text: modelData.dir || ""
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                        }
                    }

                    IslandPointerTarget {
                        id: resultRow
                        anchors.fill: parent
                        pointerOrigin: root
                        cursorShape: Qt.PointingHandCursor
                        onClicked: PlatformClient.request("file.open", { path: modelData.path },
                            function(response) {
                                if (!response || !response.ok)
                                    console.warn("[Island] file.open failed")
                            })
                    }

                    // Dragging a result out of the island. This is a real
                    // platform drag with a text/uri-list payload, so the file
                    // can be dropped into any application -- the one thing
                    // the island's own pointer model cannot do, because that
                    // model only ever reorders things inside the island.
                    DragHandler {
                        id: resultDrag
                        target: null
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                    }

                    Drag {
                        id: shelfDrag
                        active: resultDrag.active
                        dragType: Drag.Automatic
                        keys: ["text/uri-list"]
                        mimeData: ({ "text/uri-list": root.fileUri(modelData.path) })
                    }
                }
            }
        }

        onVisibleChanged: {
            if (!visible)
                return
            finderInput.text = IslandFinderService.query
            finderInput.forceActiveFocus()
            IslandFinderService.run()
        }
    }

    // ------------------------------------------------------------------
    // App picker — the island-side "添加 App" surface.
    //
    // It covers the widget column only, never the application column: an
    // application is added by dragging it out of the picker and letting it
    // go on the column, and the column has to stay visible for that. The
    // drop lands on the column's own DropArea in IslandWindow.
    // ------------------------------------------------------------------
    Rectangle {
        id: appPicker
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        // Width, not anchors.right: an anchor line is not a number, and a
        // binding that tries to assign one fails silently at run time, which
        // left the panel zero pixels wide while it still held the island
        // open.
        // Covers the widget column and its left margin, not a fraction of the
        // panel: at 0.52 * width the column's right edge stuck out past the
        // picker once the column grew to its cap.
        width: contentArea.sideMargin + widgetViewport.width + 8
        visible: root.pickingApps
        radius: 16
        color: Qt.rgba(0.05, 0.06, 0.09, 0.98)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.10)

        ColumnLayout {
            anchors { fill: parent; margins: 8 }
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: I18n.tr("Add app")
                    color: "white"
                    font.pixelSize: 12
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: pickerDoneLabel.implicitWidth + 14
                    implicitHeight: 20
                    radius: 10
                    color: Qt.rgba(0.29, 0.87, 0.5, 0.85)

                    Text {
                        id: pickerDoneLabel
                        anchors.centerIn: parent
                        text: I18n.tr("Done")
                        color: Qt.rgba(0.04, 0.2, 0.12, 1)
                        font.pixelSize: 10
                        font.bold: true
                    }

                    IslandPointerTarget {
                        anchors.fill: parent
                        onClicked: root.pickingApps = false
                    }
                }
            }

            TextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 26
                placeholderText: I18n.tr("Search apps")
                color: "white"
                font.pixelSize: 11
                // A Control installs its own hover handler when hover is
                // enabled, and a hover handler inside the island takes hover
                // away from the surface -- which is the bounce this port is
                // fixing. The field does not need hover to be usable.
                hoverEnabled: false
                background: Rectangle {
                    radius: 8
                    color: Qt.rgba(1, 1, 1, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.10)
                }
                onTextChanged: root.appSearch = text
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.filteredApps
                spacing: 2

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: 30
                    radius: 8
                    readonly property bool pinned: IslandQuickLaunchModel.isPinned(modelData.id)
                    color: appRowHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 8

                        // Layout.preferred*, not width/height: a RowLayout
                        // owns its children's geometry and sets both itself,
                        // so assigning them is undefined behaviour.
                        AppIcon {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            source: modelData.icon || ""
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name || modelData.id
                            color: Qt.rgba(1, 1, 1, 0.85)
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Text {
                            text: pinned ? "\u2713" : "+"
                            color: pinned ? Qt.rgba(0.29, 0.87, 0.5, 0.95) : Qt.rgba(1, 1, 1, 0.55)
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    // A click pins or unpins; the picker is a toggle list, so
                    // the row needs no drag of its own.
                    IslandPointerTarget {
                        id: appRowHover
                        anchors.fill: parent
                        pointerOrigin: root
                        onClicked: IslandQuickLaunchModel.togglePin(modelData.id)
                    }
                }
            }
        }
    }
}
