import QtQuick
import QtQuick.Window
import QtQuick.Controls as Controls
import QtQml.Models
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../../../shared/qml/i18n"
import qs.desktop.modules.applauncher
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.platform
import qs.desktop.modules.wallpaper
import qs.desktop.modules.dock
import qs.desktop.modules.stage
import "../../../Kos/Ui"
import "WidgetLayout.mjs" as WidgetLayout
import "DesktopGridMetrics.mjs" as DesktopGridMetrics
import "bundled-clock" as Clock

// iPadOS-inspired desktop widgets. Stays on the Bottom layer: Plasma's desktop
// surface shares the Desktop/Background layer and would cover it if moved down.
// Application windows remain above it; it reserves no usable desktop area.
PanelWindow {
    id: root

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    // 2026-10-18 层序：留在 Bottom。降到 Background（KWin DesktopLayer）
    // 会被同在 DesktopLayer 的 Plasma 桌面表面盖住——实测重登后组件全部
    // 消失。与台前调度条带的层内先后由 KWin 脚本重排，见
    // kwin/window-bridge.js。
    // KWin protects both Desktop and Dock windows from ordinary close/move
    // shortcuts and Show Desktop hiding. Only the wallpaper may be Desktop:
    // native Overview's DesktopBackground captures one Desktop window, so
    // typing this transparent widget surface as Desktop loses the wallpaper.
    // Bottom still puts widgets below applications; the bridge orders them
    // above the separate wallpaper. Native Overview fades Dock thumbnails;
    // Glass supplies the composed desktop texture so widgets scale with it.
    WlrLayershell.namespace: "dock"
    WlrLayershell.layer: WlrLayer.Bottom
    // A desktop needs shortcuts only after the user explicitly clicks it.
    // OnDemand keeps active applications' Ctrl+C/V untouched otherwise.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; left: true; right: true; bottom: true }
    implicitWidth: screen?.width ?? 1920
    implicitHeight: screen?.height ?? 1080

    // Coordinates shared with the separate Top-layer foreground surface.
    Item {
        id: desktopCoordinates
        anchors.fill: parent
    }

    // Passive pointer handlers observe the whole desktop, including cards,
    // while existing controls retain their clicks and drags.
    HoverHandler {
        id: wallpaperHover
        enabled: ThemeWallpaperService.active
        onPointChanged: ThemeWallpaperService.pointerMoved(root.screen?.name,
            point.position.x, point.position.y, hovered)
        onHoveredChanged: ThemeWallpaperService.pointerMoved(root.screen?.name,
            point.position.x, point.position.y, hovered)
    }
    TapHandler {
        enabled: ThemeWallpaperService.active
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.DragThreshold
        onPressedChanged: if (pressed) ThemeWallpaperService.pointerPressed(root.screen?.name,
            point.position.x, point.position.y)
    }

    property var spatialWidgetRects: []

    // Publish current visual positions, including drag transforms. Both
    // wallpaper surfaces use these coordinates for a visible crossing orbit.
    Timer {
        interval: 250
        repeat: true
        running: (ThemeWallpaperService.active || SpatialWallpaperService.layeredReady) && root.visible
        triggeredOnStart: true
        onTriggered: {
            const rectangles = []
            for (let i = 0; i < widgetRepeater.count; ++i) {
                const card = widgetRepeater.itemAt(i)
                if (!card || !card.visible) continue
                const point = card.mapToItem(desktopCoordinates, 0, 0)
                rectangles.push({x: Math.round(point.x), y: Math.round(point.y),
                    width: Math.round(card.width * card.scale), height: Math.round(card.height * card.scale)})
            }
            if (JSON.stringify(root.spatialWidgetRects) !== JSON.stringify(rectangles))
                root.spatialWidgetRects = rectangles
            ThemeWallpaperService.setWidgetRects(root.screen?.name, rectangles)
        }
    }

    SpatialWidgetForeground {
        objectName: "spatial-widget-foreground"
        anchors.fill: parent
        z: 2
        targetScreen: root.screen
        pointerX: root.depthPointerX
        pointerY: root.depthPointerY
        widgetRects: root.spatialWidgetRects
        suspended: root.editMode || WallpaperPreviewService.active
    }

    // Ten square units are derived exclusively from screen width. Every
    // widget uses integer spans, giving desktop cards the intentional, large
    // iPadOS scale rather than a collection of small floating macOS tiles.
    readonly property int columns: 10
    readonly property real sideMargin: 20
    // Keep card sizing tied to the original grid metrics. The larger visual
    // insets should consume the flexible desktop-file field on the right,
    // rather than shrinking or reflowing the established widget layout.
    readonly property real layoutBaseSideMargin: 8
    readonly property real layoutBaseGap: 10
    // The standalone Bar needs its 35px strip plus breathing room. Once Bar
    // content is hosted by Dock, reclaim that strip for widgets and desktop
    // files regardless of which edge hosts the Dock.
    readonly property bool barIntegratedWithDock:
        AppearanceConfigService.barIntegratedWithDock
    readonly property real topInset: barIntegratedWithDock
        ? 24 : Math.max(56, ConfigService.barHeight + 21)
    readonly property real bottomInset: Math.max(96, AppLauncherService.dockHeight + 24)
    // A side dock reserves its own strip on the left/right edge; shift the
    // grid and the desktop file field inward so the dock never covers them.
    // AppLauncherService.dockHeight is the dock's short edge, which is
    // exactly its width when the dock is docked to a side.
    // Only "always" mode actually reserves that strip (the dock also sets a
    // non-zero exclusiveZone only then); hidden/auto modes float over content,
    // so reserving would leave an empty gap next to the collapsed bar.
    readonly property real leftInset: ConfigService.position === "left"
        && ConfigService.visibilityMode === "always"
        ? AppLauncherService.dockHeight + 24 : root.sideMargin
    readonly property real rightInset: ConfigService.position === "right"
        && ConfigService.visibilityMode === "always"
        ? AppLauncherService.dockHeight + 24 : root.sideMargin
    readonly property real gap: AppearanceTokens.widget.gap
    readonly property real cellSize: Math.max(1,
        (width - layoutBaseSideMargin * 2
            - layoutBaseGap * (columns - 1)) / columns)
    readonly property int usableRows: Math.max(0, Math.floor(
        (height - topInset - bottomInset + gap) / (cellSize + gap)))
    property bool editMode: false
    // The gallery panel lives in its own Overlay-layer window
    // (WidgetGalleryWindow) so it can float above the Dock instead of
    // sharing this window's Bottom-layer stacking plane; this window only
    // ever hosts the desktop grid, placement logic and drop-preview, and
    // mirrors/drives the panel's state through WidgetGalleryService.
    // Only the active screen's instance drives the gallery (matches
    // DeskCenter.qml's own screen.name === ScreenLifecycle.activeScreen
    // gate on entering edit mode), so geometry/catalog publishing and drag
    // signal consumption both need to be restricted to it -- otherwise every
    // monitor's DeskCenterWindow would fight over the one shared singleton.
    readonly property bool isGalleryHost:
        root.screen?.name === ScreenLifecycle.activeScreen?.name
    // Same bottom-center-floating geometry the panel used while embedded
    // here, now published for WidgetGalleryWindow to consume instead of
    // being read directly off a child item.
    readonly property real galleryWidth: Math.max(1, Math.min(940, root.width - root.leftInset - root.rightInset))
    readonly property real galleryHeight: Math.max(180, Math.min(510, root.height - root.topInset - 44))
    readonly property real galleryX: root.leftInset + (root.width - root.leftInset - root.rightInset - galleryWidth) / 2
    readonly property real galleryY: Math.max(root.topInset + 44, root.height - galleryHeight)
    property var activeDragCard: null
    // Self-clearing: without this, a one-off "added"/"no room" message from
    // addGalleryWidget()/resizeNamedWidget() would sit in the gallery footer
    // forever, since nothing else routinely overwrites it back to "".
    property string widgetFeedback: ""
    onWidgetFeedbackChanged: if (widgetFeedback) widgetFeedbackTimer.restart()
    Timer {
        id: widgetFeedbackTimer
        interval: 3000
        onTriggered: root.widgetFeedback = ""
    }
    property string contextWidgetId: ""
    readonly property var contextWidget:
        widgetDefinitions.find(widget => widget.id === contextWidgetId) ?? null

    // Every call creates a brand-new placed instance, even for a package ID
    // that is already on the desktop (e.g. an icon-aggregation widget added
    // twice with two different groupings, or the same clock added at two
    // sizes). The instance ID is the per-placement key threaded through
    // placements/positions/sizes/content resolution; entry.id (the package
    // ID) stays a separate field (widget.packageId below) only used to
    // resolve which package a given instance renders.
    property int _nextInstanceSeq: 1
    function addGalleryWidget(entry, size, requestedPosition) {
        const span = WidgetLayout.namedGallerySpan(size)
        const instanceId = entry.id + "#" + (root._nextInstanceSeq++)
        let position = requestedPosition
        if (!position) {
            for (let row = 0; row <= usableRows - span[1] && !position; ++row)
                for (let column = 0; column <= maximumWidgetColumns - span[0] && !position; ++column)
                    if (WidgetLayout.canPlace(placements, instanceId, column, row, span[0], span[1], maximumWidgetColumns, usableRows))
                        position = {column, row}
        }
        if (!position || !WidgetLayout.canPlace(placements, instanceId, position.column, position.row,
            span[0], span[1], maximumWidgetColumns, usableRows)) {
            widgetFeedback = I18n.tr("There is no room for this size. Move or remove another widget first.")
            return
        }
        if (!DeskCenterConfigService.savePosition(desktopOutput, placements,
                instanceId, position.column, position.row, widgetGeometry))
            return
        DeskCenterConfigService.setSpan(instanceId, span[0], span[1])
        widgetInstances = widgetInstances.concat([Object.assign({}, entry, { id: instanceId, packageId: entry.id })])
        widgetFeedback = I18n.tr("Widget added to the desktop.")
    }
    function resizeNamedWidget(id, size) {
        const span = WidgetLayout.namedGallerySpan(size)
        if (!resizeWidget(id, span[0], span[1]))
            widgetFeedback = I18n.tr("There is no room for this size. Move or remove another widget first.")
    }
    function removeWidget(id) {
        widgetInstances = widgetInstances.filter(widget => widget.id !== id)
    }
    function showWidgetMenu(id, point) {
        contextWidgetId = id
        widgetContextMenu.x = Math.max(8, Math.min(point.x, root.width - widgetContextMenu.width - 8))
        widgetContextMenu.y = Math.max(8, Math.min(point.y, root.height - widgetContextMenu.height - 8))
        widgetContextMenu.open()
    }
    // Edit mode and the gallery are one state now: there is no toolbar step
    // in between, and no way to be "in edit mode" with the gallery closed.
    function enterWidgetEditMode() {
        desktopFileGrid.clearDesktopSelection()
        desktopFileGrid.activateKeyboard()
        root.widgetFeedback = ""
        WidgetGalleryService.show(root.screen)
        root.editMode = true
    }

    function leaveWidgetEditMode() {
        root.activeDragCard = null
        WidgetGalleryService.hide()
        root.editMode = false
        desktopFileGrid.activateKeyboard()
    }

    // Mirrors WidgetGallery.qml's own sizeName(): that panel now lives in a
    // separate window (WidgetGalleryWindow), so the context menu here needs
    // its own copy rather than reaching across windows for it.
    function sizeName(size) {
        if (Array.isArray(size)) return size[0] + "×" + size[1]
        return I18n.tr(size === "small" ? "Small" : size === "large" ? "Large" : "Medium")
    }

    // Widget editing is modal: the gesture that entered it also leaves it.
    // Nothing is ever pending at this point -- a moved card is persisted when
    // its drag ends and a resized card when the handle commits -- so leaving
    // only drops the editing chrome, it never has to flush state.
    function toggleWidgetEditMode() {
        if (root.editMode)
            root.leaveWidgetEditMode()
        else
            root.enterWidgetEditMode()
    }
    // File metadata is supplied by kos-data-service; this surface only
    // lays it out as a right-aligned desktop grid.
    readonly property var desktopFiles: DesktopFilesService
    readonly property string desktopOutput: screen?.name ?? ""
    property real depthPointerX: 0
    property real depthPointerY: 0
    property bool spatialWallpaperActive: false
    HoverHandler {
        enabled: root.spatialWallpaperActive && !WallpaperPreviewService.active
        onPointChanged: {
            root.depthPointerX = Math.max(-1, Math.min(1,
                (point.position.x / Math.max(1, root.width) - 0.5) * 2))
            root.depthPointerY = Math.max(-1, Math.min(1,
                (point.position.y / Math.max(1, root.height) - 0.5) * 2))
        }
        onHoveredChanged: if (!hovered) {
            root.depthPointerX = 0
            root.depthPointerY = 0
        }
    }
    // Package metadata feeds the gallery. Runtime instances remain separately
    // owned and empty until package loading and placement persistence are wired.
    property var widgetCatalog: WidgetPackageService.packages
    property var widgetInstances: []
    readonly property var widgetDefinitions: {
        const revision = DeskCenterConfigService.revision
        const sizes = DeskCenterConfigService.parsedSizes()
        const positions = DeskCenterConfigService.displayPositionsForOutput(desktopOutput, widgetGeometry)
        return widgetInstances.map(widget => {
            const position = positions[widget.id]
            const span = sizes[widget.id] === undefined
                ? [widget.columns ?? 1, widget.rows ?? 1]
                : DeskCenterConfigService.spanFor(widget.id)
            return Object.assign({}, widget, {
                columns: span[0], rows: span[1],
                column: position?.column ?? widget.column,
                row: position?.row ?? widget.row
            })
        })
    }

    // Resolves which content view a placed widget instance renders. Catalog
    // entries (root.widgetCatalog, sourced from the platform daemon's JSON
    // package index) never carry a QML Component themselves, so this is the
    // one seam that maps a package ID to the actual view -- today that is
    // only the bundled SDK example; see docs/plugins/WidgetGalleryPreviewPlan
    // .zh-CN.md R10 for the rest of the real third-party host wiring this
    // still needs (per-package data authorization, isolation, etc.).
    function resolveContentComponent(def) {
        if (def.packageId === "org.nextkde.example.clock") return clockWidgetContent
        return null
    }
    Component {
        id: clockWidgetContent
        Item {
            id: clockHost
            anchors.fill: parent
            // Exposed so the settings affordance below can edit the exact
            // running instance's config instead of creating a second,
            // out-of-sync ClockWidgetDataService.
            readonly property var dataService: clockData
            // Forwarded up so the card delegate (widgetCardComponent below)
            // can feed the component's own backgroundSpec into the card's
            // startColor/endColor instead of the legacy static gradient --
            // see WidgetSDK.zh-CN.md section 4.
            readonly property var backgroundSpec: clockWidget.backgroundSpec
            ClockWidgetDataService { id: clockData }
            Clock.Widget {
                id: clockWidget
                anchors.fill: parent
                data: clockData.data
                widgetSize: DeskCenterConfigService.spanFor(clockData.instanceId)
                appearance: ({
                    isDark: AppearanceTokens.isDarkTheme,
                    foreground: AppearanceTokens.surface.widgetForeground,
                    // "Transparent mode" in this Shell is the glass card
                    // finish: the host already suppresses backgroundSpec for
                    // it (usesColorArtwork below gates on the same flag), but
                    // the component itself gets told too, so content that
                    // wants to adapt beyond just losing its background (e.g.
                    // dialing back its own internal fills) can.
                    transparent: AppearanceConfigService.widgetStyle === "glass"
                })
            }
        }
    }

    // A package's optional Settings.qml (SDK draft, WidgetSDK.zh-CN.md
    // section 6) -- same per-package seam as resolveContentComponent above,
    // wired only for the bundled example. Returns null when the package has
    // no settings surface, which hides the gear affordance entirely.
    function resolveSettingsComponent(def) {
        if (def.packageId === "org.nextkde.example.clock") return clockSettingsContent
        return null
    }
    Component {
        id: clockSettingsContent
        Controls.Popup {
            id: settingsPopup
            // Set by the Loader right after creation (see widgetCardComponent
            // below); this Component is declared at window scope so it has no
            // compile-time visibility into any one card's ids.
            property var dataService: null
            modal: false
            focus: true
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
            contentItem: Clock.Settings {
                data: ({ format24h: settingsPopup.dataService?.format24h ?? true })
                onApply: next => settingsPopup.dataService?.setFormat24h(next.format24h)
            }
        }
    }

    FontMetrics { id: desktopFileFontMetrics }
    readonly property var reservedFileMetrics: DesktopGridMetrics.metrics(
        desktopFiles.layout.iconSize + 72, desktopFiles.layout.iconSize + 58,
        desktopFiles.layout.iconSize + 12, desktopFiles.layout.iconSpacing, desktopFileFontMetrics.height)
    readonly property int maximumWidgetColumns: WidgetLayout.widgetColumnLimit(
        width - leftInset - rightInset, cellSize, gap,
        reservedFileMetrics.cellWidth + reservedFileMetrics.gap,
        desktopFiles.entriesForOutput(desktopOutput).length,
        Math.floor((height - topInset - bottomInset + reservedFileMetrics.gap)
            / (reservedFileMetrics.cellHeight + reservedFileMetrics.gap)))
    readonly property string widgetGeometry: maximumWidgetColumns + ":" + usableRows

    readonly property var widgetLayout: WidgetLayout.fitWidgets(
        widgetDefinitions, 4, maximumWidgetColumns, usableRows)
    readonly property var placements: widgetLayout.placements
    readonly property int widgetColumns: widgetLayout.columns

    function resizeWidget(widgetId, columns, rows) {
        const placement = placementFor(widgetId)
        // A package instance's own declared sizes (metadata.json's `sizes`,
        // threaded through widgetDefinitions as `sizes`) set its real
        // ceiling/floor -- e.g. the example clock's [[2,2],[3,2]] means a
        // 3-wide drag/menu choice must not be clamped to the legacy 2x2
        // default below.
        const definition = widgetDefinitions.find(widget => widget.id === widgetId)
        const limit = WidgetLayout.declaredSizeCeiling(definition?.sizes) ?? WidgetLayout.maxSpanFor(widgetId)
        const minimum = WidgetLayout.declaredSizeFloor(definition?.sizes) ?? WidgetLayout.minSpanFor(widgetId)
        if (!WidgetLayout.isValidSize(widgetId, columns + "x" + rows)
                || columns < minimum[0] || rows < minimum[1] || columns > limit[0]
                || rows > limit[1] || !placement
                || !WidgetLayout.canPlace(placements, widgetId,
                placement.column, placement.row, columns, rows,
                maximumWidgetColumns, usableRows)) return false
        if (!DeskCenterConfigService.savePosition(desktopOutput, placements,
                widgetId, placement.column, placement.row, widgetGeometry))
            return false
        DeskCenterConfigService.setSpan(widgetId, columns, rows)
        return true
    }

    function placementFor(widgetId) {
        for (let i = 0; i < placements.length; i++)
            if (placements[i].id === widgetId)
                return placements[i]
        return null
    }
    function spanSize(span) { return span * cellSize + (span - 1) * gap }

    // Combine the visible cards' compositor blur regions in window coordinates.
    BackgroundEffect.blurRegion: (AppearanceTokens.surface.usesKwinBlur
        && root.visible) ? widgetBlurHolder : null

    Region {
        id: widgetBlurHolder
        regions: {
            const arr = []
            for (let i = 0; i < widgetRepeater.count; ++i) {
                const card = widgetRepeater.itemAt(i)
                if (card && card.visible && card.blurRegion)
                    arr.push(card.blurRegion)
            }
            return arr
        }
    }

    MouseArea {
        id: globalDesktopBackgroundArea
        objectName: "desktop-background-catcher"
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // A long press enters widget editing, and releasing it must not be read
        // as a plain click: a plain click on this surface either toggles
        // show-desktop or leaves editing, and neither may happen from the hold
        // that just started editing.
        property bool holdEnteredEditing: false

        onPressed: function(mouse) {
            holdEnteredEditing = false
            if (mouse.button === Qt.RightButton) {
                // While editing, bare desktop dismisses the session instead of
                // opening the menu. That menu is the way *into* editing (Edit
                // Widgets), so it belongs to the non-editing desktop; outside
                // editing the next right click opens it.
                if (root.editMode) {
                    root.leaveWidgetEditMode()
                    return
                }
                desktopFileGrid.setSelectedPaths([])
                desktopFileGrid.contextEntry = null
                desktopFileGrid.showMenu(null,
                    Qt.point(mouse.x - desktopFileGrid.x, mouse.y - desktopFileGrid.y))
                return
            }
            desktopFileGrid.clearDesktopSelection()
        }
        // 空桌面左键：编辑模式下退出编辑（改动先在各自手势里落盘，这里只
        // 收尾），否则＝显示桌面开关：台前侧栏把桌面应用全部带动画收进卡，
        // 再点一次整组放出来。⚠️ 不能在 onPressAndHold 里吞事件来防误触
        // ——按住超 800ms 的"慢点击"会被一起吞掉（点击全部失效，实测踩
        // 过）；改用 holdEnteredEditing 守卫：长按进了挂件编辑模式，
        // release 的 clicked 自然跳过。
        onClicked: function(mouse) {
            if (mouse.button !== Qt.LeftButton)
                return
            if (holdEnteredEditing) {
                holdEnteredEditing = false
                return
            }
            if (root.editMode) {
                // Leaving is the click's job while a widget is being placed;
                // modifier clicks stay selection-only, as below.
                if (mouse.modifiers === Qt.NoModifier)
                    root.leaveWidgetEditMode()
                return
            }
            // 修饰键守卫与网格入口（FreeSlotDesktopDemo）同款：Ctrl/Shift+
            // 点击是选择语义，不该翻转显示桌面
            if (mouse.modifiers === Qt.NoModifier)
                StageModeService.deskRevealToggleRequested()
        }
        onPressAndHold: function(mouse) {
            if (mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier) {
                holdEnteredEditing = true
                root.enterWidgetEditMode()
            }
        }
    }

    // Publishes geometry/catalog/feedback into the singleton the gallery's
    // own Overlay-layer window reads from, and consumes its drag/placement
    // signals back. Both directions are gated on isGalleryHost so the
    // background screen in a multi-monitor setup never fights the active
    // one over the shared WidgetGalleryService state.
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "galleryX"; value: root.galleryX
    }
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "galleryY"; value: root.galleryY
    }
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "galleryWidth"; value: root.galleryWidth
    }
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "galleryHeight"; value: root.galleryHeight
    }
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "catalog"; value: root.widgetCatalog
    }
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "loading"; value: WidgetPackageService.loading
    }
    Binding {
        target: WidgetGalleryService
        when: root.isGalleryHost
        property: "feedback"; value: root.widgetFeedback || WidgetPackageService.error
    }
    Connections {
        target: WidgetGalleryService
        enabled: root.isGalleryHost
        function onDone() { root.leaveWidgetEditMode() }
        function onAddRequested(entry, size) { root.addGalleryWidget(entry, size, null) }
    }

    Controls.Menu {
        id: widgetContextMenu
        width: 220
        Controls.MenuItem {
            text: root.contextWidget?.name ?? I18n.tr("Widget")
            enabled: false
        }
        Controls.MenuSeparator {}
        Instantiator {
            model: root.contextWidget?.sizes ?? []
            onObjectAdded: (index, object) => widgetContextMenu.insertItem(index + 2, object)
            onObjectRemoved: (index, object) => widgetContextMenu.removeItem(object)
            delegate: Controls.MenuItem {
                // Package sizes arrive as [cols, rows] pairs, not the legacy
                // named strings ("small"/"2x2"/...) this menu was written
                // for. A `string`-typed required property force-coerces an
                // array value to e.g. "2,2", which namedGallerySpan() below
                // cannot parse, so every package widget silently resized to
                // 1x1. Both sizeName() and namedGallerySpan() already accept
                // either shape -- only the property's declared type was wrong.
                required property var modelData
                text: root.sizeName(modelData)
                checkable: true
                checked: {
                    const target = WidgetLayout.namedGallerySpan(modelData)
                    return root.contextWidget?.columns === target[0] && root.contextWidget?.rows === target[1]
                }
                onTriggered: root.resizeNamedWidget(root.contextWidgetId, modelData)
            }
        }
    }

    Rectangle {
        id: widgetDropPreview
        objectName: "widget-drop-preview"
        z: 110
        readonly property var dragged: root.activeDragCard
        // The highlight marks the cell the pointer is over, so it jumps from
        // cell to cell: only ever one cell is lit. Sliding it across the cells
        // in between read as several cells lighting up in a row.
        // Snapshot only live drag updates. Once the drag is gone, keep the
        // last target geometry and colour for the entire fade-out.
        property rect lastGeometry: Qt.rect(0, 0, 0, 0)
        readonly property rect previewGeometry: dragged !== null
            ? Qt.rect(WidgetLayout.insetRightEdge(
                    root.leftInset + dragged.dropPosition.column * (root.cellSize + root.gap),
                    root.spanSize(dragged.displayColumns), root.width, root.rightInset),
                root.topInset + dragged.dropPosition.row * (root.cellSize + root.gap),
                root.spanSize(dragged.displayColumns), root.spanSize(dragged.displayRows))
            : lastGeometry
        onPreviewGeometryChanged: if (dragged !== null) lastGeometry = previewGeometry
        property bool lastAllowed: false
        readonly property bool allowed: dragged !== null ? dragged.dropAllowed : lastAllowed
        onAllowedChanged: if (dragged !== null) lastAllowed = allowed
        x: previewGeometry.x
        y: previewGeometry.y
        width: previewGeometry.width
        height: previewGeometry.height
        radius: AppearanceTokens.widget.radius
        color: allowed ? "#2434c759" : "#30ff453a"
        border.width: 2
        border.color: allowed ? "#34c759" : "#ff453a"
        opacity: dragged !== null ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            enabled: !AppTheme.reduceMotion
            NumberAnimation {
                // Appear promptly, leave a little faster: the highlight should
                // never trail the card that is landing.
                // motion-exception: Drop-preview fade follows the landing card; retain its shortened release.
                duration: widgetDropPreview.dragged !== null
                    ? AppearanceTokens.motion.fastDuration
                    : AppearanceTokens.motion.fastDuration * 0.6
                easing.type: Easing.OutCubic
            }
        }
    }

    // Position/size saves replace widgetDefinitions. Keep delegate identity
    // Keep delegates keyed by instance ID across placement and size changes.
    readonly property var visibleWidgetIds:
        root.screen?.name === ScreenLifecycle.activeScreen?.name
            ? root.widgetDefinitions.map(widget => widget.id) : []
    onVisibleWidgetIdsChanged: syncWidgetModel()

    ListModel {
        id: desktopWidgetModel
        Component.onCompleted: root.syncWidgetModel()
    }

    function syncWidgetModel() {
        if (!desktopWidgetModel) return
        const ids = root.visibleWidgetIds
        for (let index = desktopWidgetModel.count - 1; index >= 0; --index) {
            if (ids.indexOf(desktopWidgetModel.get(index).widgetId) < 0)
                desktopWidgetModel.remove(index)
        }
        for (let target = 0; target < ids.length; ++target) {
            let current = -1
            for (let index = target; index < desktopWidgetModel.count; ++index) {
                if (desktopWidgetModel.get(index).widgetId === ids[target]) {
                    current = index
                    break
                }
            }
            if (current < 0)
                desktopWidgetModel.insert(target, { widgetId: ids[target] })
            else if (current !== target)
                desktopWidgetModel.move(current, target, 1)
        }
    }

    Repeater {
        id: widgetRepeater
        objectName: "desktop-widget-repeater"
        model: desktopWidgetModel

        delegate: widgetCardComponent
    }

    Component {
        id: widgetCardComponent
        DeskWidgetCard {
            id: card
            property string widgetId: model.widgetId
            objectName: "desktop-widget-" + widgetId
            readonly property var modelData:
                root.widgetDefinitions.find(widget => widget.id === widgetId) ?? {id: widgetId}
            // Each placed instance of a package (e.g. two clocks at
            // different sizes) shares the same Clock.Widget Component but
            // needs its own settings/size key -- resolveContentComponent is
            // keyed by packageId, not this card's instance id, so poke the
            // instance id onto the loaded content's data service once it
            // exists. See ClockWidgetDataService's instanceId property.
            onLoadedContentChanged: {
                if (card.loadedContent && card.loadedContent.dataService)
                    card.loadedContent.dataService.instanceId = card.widgetId
            }
            property real dragOffsetX: 0
            property real dragOffsetY: 0
            readonly property var placement: root.placementFor(modelData.id)
            // 2026-10-18 用户改判：台前调度与桌面组件共存（台前调度在
            // 组件之上），组件不再随台前调度开启而隐藏
            // Release clears this before committing the position so the spring
            // carries the pointer's momentum into the destination cell.
            property bool pointerHeld: false
            // A package's own declared sizes (e.g. the example clock's
            // [[2,2],[3,2]]) set the real resize ceiling/floor; only widgets
            // with no such declaration (the legacy named ids) fall back to
            // WidgetLayout's generic bounds.
            readonly property var sizeLimit:
                WidgetLayout.declaredSizeCeiling(modelData.sizes) ?? WidgetLayout.maxSpanFor(widgetId)
            readonly property var sizeFloor:
                WidgetLayout.declaredSizeFloor(modelData.sizes) ?? WidgetLayout.minSpanFor(widgetId)
            readonly property int maxDropColumns: root.maximumWidgetColumns
            readonly property var dropPosition: WidgetLayout.snappedPosition(
                x - root.leftInset, y - root.topInset,
                displayColumns, displayRows, root.cellSize, root.gap,
                maxDropColumns, root.usableRows)
            readonly property bool dropAllowed: WidgetLayout.canPlace(root.placements,
                modelData.id, dropPosition.column, dropPosition.row,
                displayColumns, displayRows, maxDropColumns, root.usableRows)
            visible: placement !== null
            // Desktop widgets are part of the login arrival, not a static
            // layer that appears before the wallpaper, bar and dock.
            opacity: StartupReveal.widgetProgress
            enabled: StartupReveal.widgetProgress > 0
            z: widgetDrag.active || resizeHandle.resizing ? 120 : (root.editMode ? 20 : 1)
            title: modelData.title ?? ""
            // A resolved content instance's own backgroundSpec (SDK draft,
            // WidgetSDK.zh-CN.md section 4) takes over from the legacy
            // per-id static gradient the moment one is published. Glass mode
            // still wins: usesColorArtwork below already gates on
            // AppearanceConfigService.widgetStyle === "color", so a
            // component's backgroundSpec never fights the user's
            // transparent-card setting.
            startColor: loadedContent?.backgroundSpec?.startColor ?? modelData.startColor ?? "#536783"
            endColor: loadedContent?.backgroundSpec?.endColor ?? modelData.endColor ?? "#35465f"
            showSurface: loadedContent?.backgroundSpec ? true : (modelData.surface ?? false)
            materialSurfaceColor: AppearanceTokens.colors.layer1
            // SurfaceShape listens to Item geometry and scale changes, not
            // Translate.x/y. Move the anchor itself so the native glass and
            // the QML content publish the same position on every drag frame.
            //
            // Geometry runs through frame-synchronised springs instead of
            // Behaviors on these bindings: Qt's SpringAnimation integrates at a
            // fixed 16 ms step, so on a 240 Hz output a released card moved in
            // ~60 Hz quanta while the compositor kept presenting every frame.
            // The grid is laid out from the left inset but still sized with the
            // original 8 px layout margins, so its rightmost column overflows
            // the right inset. Cap the committed cell here so the resize
            // preview does not move the card's left edge.
            readonly property real targetX: WidgetLayout.insetRightEdge(
                root.leftInset + (placement?.column ?? 0) * (root.cellSize + root.gap),
                root.spanSize(displayColumns), root.width, root.rightInset) + dragOffsetX
            readonly property real targetY: root.topInset
                + (placement?.row ?? 0) * (root.cellSize + root.gap) + dragOffsetY
            // The card and every widget inside it lay themselves out for the
            // cell size they have committed to, never for the mid-drag preview:
            // switching a widget to its other layout at the halfway point made
            // the contents jump while the corner was still moving. The preview
            // span only drives the resize readout and the corner itself.
            readonly property int displayColumns: placement?.columns ?? 1
            readonly property int displayRows: placement?.rows ?? 1
            // While the corner is held, the card follows the magnetised
            // pointer position; the moment it is released the size switches to
            // the committed cell and the spring takes it there.
            readonly property real targetWidth: resizeHandle.resizing
                ? resizeHandle.previewWidth : root.spanSize(displayColumns)
            readonly property real targetHeight: resizeHandle.resizing
                ? resizeHandle.previewHeight : root.spanSize(displayRows)
            // The lift belongs to the same motion family as the drop, so the
            // card does not land while it is still shrinking on another curve.
            readonly property real targetScale: widgetDrag.active ? 1.035 : 1

            x: springX.value
            y: springY.value
            width: springWidth.value
            height: springHeight.value
            // Keep the login arrival scale independent of the drag spring.
            // SurfaceShape follows this scale together with the QML content.
            scale: springScale.value * (0.97 + 0.03 * StartupReveal.widgetProgress)

            // A held pointer owns the value one-to-one (follow) and the same
            // spring keeps its last velocity when the card is released, so the
            // momentum of the drag carries into the cell instead of stopping
            // dead. The move spring is critically damped: a long drop must not
            // overshoot past the screen edge.
            MotionSpring {
                id: springX
                target: card.targetX
                follow: card.pointerHeld
                enabled: !AppTheme.reduceMotion
                angularFrequency: AppearanceTokens.motion.widgetMoveAngularFrequency
                dampingRatio: AppearanceTokens.motion.widgetMoveDampingRatio
                epsilon: AppearanceTokens.motion.widgetMoveEpsilon
            }
            MotionSpring {
                id: springY
                target: card.targetY
                follow: card.pointerHeld
                enabled: !AppTheme.reduceMotion
                angularFrequency: AppearanceTokens.motion.widgetMoveAngularFrequency
                dampingRatio: AppearanceTokens.motion.widgetMoveDampingRatio
                epsilon: AppearanceTokens.motion.widgetMoveEpsilon
            }
            MotionSpring {
                id: springWidth
                target: card.targetWidth
                follow: resizeHandle.resizing
                enabled: !AppTheme.reduceMotion
                angularFrequency: AppearanceTokens.motion.widgetResizeAngularFrequency
                dampingRatio: AppearanceTokens.motion.widgetResizeDampingRatio
                epsilon: AppearanceTokens.motion.widgetResizeEpsilon
            }
            MotionSpring {
                id: springHeight
                target: card.targetHeight
                follow: resizeHandle.resizing
                enabled: !AppTheme.reduceMotion
                angularFrequency: AppearanceTokens.motion.widgetResizeAngularFrequency
                dampingRatio: AppearanceTokens.motion.widgetResizeDampingRatio
                epsilon: AppearanceTokens.motion.widgetResizeEpsilon
            }
            MotionSpring {
                id: springScale
                target: card.targetScale
                enabled: !AppTheme.reduceMotion
                angularFrequency: AppearanceTokens.motion.widgetMoveAngularFrequency
                dampingRatio: AppearanceTokens.motion.widgetMoveDampingRatio
                epsilon: AppearanceTokens.motion.widgetGripEpsilon
            }
            // The resize readout lifts with the grab on the same frame clock.
            MotionSpring {
                id: springReadoutScale
                target: readout.visible ? 1.0 : 0.86
                enabled: !AppTheme.reduceMotion
                angularFrequency: AppearanceTokens.motion.widgetGripAngularFrequency
                dampingRatio: AppearanceTokens.motion.widgetGripDampingRatio
                epsilon: AppearanceTokens.motion.widgetGripEpsilon
            }
            // One frame callback advances every channel, and it stops as soon
            // as all of them have settled, so idle cards cost nothing.
            FrameAnimation {
                running: springX.animating || springY.animating
                    || springWidth.animating || springHeight.animating
                    || springScale.animating || springReadoutScale.animating
                onTriggered: {
                    springX.advance(frameTime)
                    springY.advance(frameTime)
                    springWidth.advance(frameTime)
                    springHeight.advance(frameTime)
                    springScale.advance(frameTime)
                    springReadoutScale.advance(frameTime)
                }
            }
            // Placement arrives asynchronously at startup and whenever a widget
            // is shown again: prime to the cell there instead of springing in
            // from the window origin.
            onVisibleChanged: {
                springX.snap()
                springY.snap()
                springWidth.snap()
                springHeight.snap()
                springScale.snap()
                springReadoutScale.snap()
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: eventPoint => root.showWidgetMenu(card.widgetId,
                    card.mapToItem(desktopCoordinates, eventPoint.position.x, eventPoint.position.y))
            }

            DragHandler {
                id: widgetDrag
                target: null
                enabled: root.editMode && !resizeHandle.resizing
                acceptedButtons: Qt.LeftButton
                onActiveTranslationChanged: {
                    if (!active)
                        return
                    card.dragOffsetX = activeTranslation.x
                    card.dragOffsetY = activeTranslation.y
                }
                onActiveChanged: {
                    if (active) {
                        card.pointerHeld = true
                        root.activeDragCard = card
                        return
                    }
                    card.pointerHeld = false
                    const allowed = root.editMode && card.dropAllowed
                    const destination = card.dropPosition
                    const id = card.modelData.id
                    const placements = root.placements
                    root.activeDragCard = null
                    card.dragOffsetX = 0
                    card.dragOffsetY = 0
                    if (allowed)
                        DeskCenterConfigService.savePosition(root.desktopOutput, placements,
                            id, destination.column, destination.row, root.widgetGeometry)
                }
            }

            HoverHandler { id: widgetHover }

            Rectangle {
                z: 50
                visible: widgetHover.hovered && !root.editMode
                anchors { right: parent.right; bottom: parent.bottom; margins: 8 }
                width: Math.min(sizeLabelMetrics.advanceWidth + 14, parent.width - 16)
                height: Math.max(24, sizeLabel.implicitHeight + 10)
                radius: 12
                color: AppearanceTokens.surface.pick(AppearanceTokens.colors.layer4, Qt.rgba(0, 0, 0, 0.52))
                border.width: 1
                border.color: AppearanceTokens.surface.pick(AppearanceTokens.colors.outlineVariant, Qt.rgba(1, 1, 1, 0.18))
                TextMetrics {
                    id: sizeLabelMetrics
                    font: sizeLabel.font
                    text: sizeLabel.text
                }
                Text {
                    id: sizeLabel
                    anchors.centerIn: parent
                    width: parent.width - 14
                    text: card.displayColumns + "×" + card.displayRows
                        + " · " + I18n.tr("Right-click to edit")
                    color: AppearanceTokens.surface.pick(AppearanceTokens.colors.surfaceForeground, "white")
                    font { pixelSize: 9; weight: Font.DemiBold }
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                z: 80
                visible: root.editMode
                // Overlaps the card's own top-left corner by the same 4px
                // the gallery's add badge (WidgetGallery.qml's addBadge)
                // hangs off its preview box's corner, so both badges read
                // as the same affordance instead of one flush/inset and
                // one floating.
                anchors { top: parent.top; left: parent.left; margins: -4 }
                width: 26; height: 26; radius: 13
                color: "#ff453a"
                BundledIcon {
                    anchors.centerIn: parent
                    name: "desktop.widget.remove"
                    color: "white"
                    size: 18
                }
                TapHandler {
                    onTapped: root.removeWidget(card.widgetId)
                }
            }

            Rectangle {
                id: settingsAffordance
                z: 80
                visible: root.editMode && root.resolveSettingsComponent(card.modelData) !== null
                anchors { top: parent.top; right: parent.right; margins: 8 }
                width: 26; height: 26; radius: 13
                color: AppearanceTokens.surface.pick(Qt.rgba(0, 0, 0, 0.4), Qt.rgba(1, 1, 1, 0.25))
                BundledIcon {
                    anchors.centerIn: parent
                    name: "desktop.widget.settings"
                    color: "white"
                    size: 16
                }
                TapHandler {
                    onTapped: {
                        settingsPopupLoader.active = false
                        settingsPopupLoader.active = true
                    }
                }
            }

            Loader {
                id: settingsPopupLoader
                active: false
                sourceComponent: root.resolveSettingsComponent(card.modelData)
                onLoaded: {
                    item.dataService = card.loadedContent?.dataService ?? null
                    item.parent = Controls.Overlay.overlay
                    const target = card.mapToItem(Controls.Overlay.overlay,
                        card.width - item.implicitWidth - 8, 36)
                    item.x = target.x
                    item.y = target.y
                    item.closed.connect(() => settingsPopupLoader.active = false)
                    item.open()
                }
            }

            WidgetResizeHandle {
                id: resizeHandle
                z: 80
                visible: root.editMode
                anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
                cellSize: root.cellSize
                gap: root.gap
                maximumColumns: card.sizeLimit[0]
                maximumRows: card.sizeLimit[1]
                minimumColumns: card.sizeFloor[0]
                minimumRows: card.sizeFloor[1]
                // card.modelData.sizes has crossed this Repeater's model:
                // boundary, which boxes a plain JS array field into a Qt
                // sequence wrapper -- still indexable, but Array.isArray()
                // on it is false. Duck-type on `.length` instead.
                declaredSizes: (card.modelData.sizes && card.modelData.sizes.length > 0)
                    ? card.modelData.sizes : null
                animate: !AppTheme.reduceMotion
                previewAllowed: card.placement !== null && WidgetLayout.canPlace(
                    root.placements, card.modelData.id, card.placement.column, card.placement.row,
                    previewColumns, previewRows, card.maxDropColumns, root.usableRows)
                onCommitted: function(columns, rows) {
                    root.resizeWidget(card.modelData.id, columns, rows)
                }
            }

            Rectangle {
                id: readout
                z: 81
                visible: resizeHandle.resizing
                anchors.centerIn: parent
                width: resizePreview.implicitWidth + 24
                height: 32
                radius: 12
                color: resizeHandle.previewAllowed ? "#b0000000" : "#c0a02020"
                // The readout lands with the grab instead of blinking on, so the
                // eye is already on the corner when the size starts to change.
                scale: springReadoutScale.value
                Text {
                    id: resizePreview
                    text: resizeHandle.previewColumns + " × " + resizeHandle.previewRows
                    color: "white"
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
            }

            contentComponent: root.resolveContentComponent(modelData)
            contentEnabled: !root.editMode
        }
    }

    // The file area intentionally has no panel background. It uses the empty
    // right side of the desktop as a calm, macOS-like icon field, filling
    // columns from right to left and rows from top to bottom.
    Item {
        id: desktopFileGrid
        objectName: "desktop-file-grid"
        // Files and their labels always stay above wallpaper subjects, even
        // while a widget or file is being rearranged near the shared boundary.
        z: 3
        x: root.leftInset + (root.screen?.name === ScreenLifecycle.activeScreen?.name && root.placements.length > 0 ? root.widgetColumns * (root.cellSize + root.gap) : 0)
        y: root.topInset
        width: Math.max(0, root.width - x - root.rightInset)
        height: root.height - y - root.bottomInset
        clip: false
        readonly property int iconSize: desktopLayout.iconSize
        // Reserve real gutters around every icon.  The gaps are not merely
        // visual: they belong to the desktop background so users can start a
        // rubber-band selection between neighbouring files.
        readonly property int preferredItemWidth: iconSize + 72
        readonly property int columnCount: Math.max(1, Math.floor(width / preferredItemWidth))
        readonly property real itemWidth: width / columnCount
        readonly property real itemHeight: iconSize + 58
        readonly property int rowCount: Math.max(1, Math.floor(height / itemHeight))
        property var selectedPaths: []
        property var contextEntry: null
        property string renamingPath: ""
        property string pendingRenamePath: ""
        property string folderDropCandidatePath: ""
        property string dropFolderPath: ""
        property real folderDropProgress: 0
        property string draggingPath: ""
        property real groupDragOffsetX: 0
        property real groupDragOffsetY: 0
        property var reorderSettleFrom: ({})
        property bool reorderSettleActive: false
        property string reorderDragSourcePath: ""
        property string reorderPreviewSourcePath: ""
        property int reorderInsertionIndex: -1
        property bool reorderDragging: false
        property real reorderPressPointerX: 0
        property real reorderPressPointerY: 0
        property real reorderDragOffsetX: 0
        property real reorderDragOffsetY: 0
        property real reorderPointerX: 0
        property real reorderPointerY: 0
        property int reorderDragEntryCount: 0
        property var reorderActiveHandler: null
        property var reorderPreviewOffsets: ({})
        property bool selectionBoxActive: false
        property real selectionStartX: 0
        property real selectionStartY: 0
        property real selectionEndX: 0
        property real selectionEndY: 0
        property var selectionBase: []
        readonly property var screenEntries: root.desktopFiles.entriesForOutput(root.desktopOutput)
        readonly property var orderedEntries: ordered(screenEntries)
        readonly property var desktopLayout: root.desktopFiles.layout

        // Parsed cache of folderCustomJson, rebuilt only when the raw string
        // changes so delegates don't re-parse on every paint.
        readonly property var _folderCustomCache: {
            try { return JSON.parse(desktopLayout.folderCustomJson) } catch (_) { return {} }
        }

        function folderCustomFor(path) {
            const map = desktopFileGrid._folderCustomCache
            return map && map[path] ? map[path] : null
        }

        function _writeFolderCustom(path, color, emoji) {
            let map
            try { map = JSON.parse(desktopLayout.folderCustomJson) } catch (_) { map = {} }
            if (!color && !emoji)
                delete map[path]
            else
                map[path] = { "color": color || "", "emoji": emoji || "" }
            desktopLayout.folderCustomJson = JSON.stringify(map)
            desktopLayout.sync()
        }

        function setFolderColor(path, color) {
            const existing = folderCustomFor(path)
            _writeFolderCustom(path, color, existing ? existing.emoji : "")
        }

        function setFolderEmoji(path, emoji) {
            const existing = folderCustomFor(path)
            _writeFolderCustom(path, existing ? existing.color : "", emoji)
        }

        function removeFolderCustom(path) {
            _writeFolderCustom(path, "", "")
        }

        function migrateFolderCustom(oldPath, newPath) {
            if (oldPath === newPath)
                return
            const existing = folderCustomFor(oldPath)
            if (!existing)
                return
            _writeFolderCustom(oldPath, "", "")
            _writeFolderCustom(newPath, existing.color, existing.emoji)
        }


        // A visible hold-to-drop progress, mirroring the App Launcher folder
        // interaction. Only a completed bar arms the actual file operation.
        NumberAnimation {
            id: folderDropProgressAnimation
            target: desktopFileGrid
            property: "folderDropProgress"
            from: 0
            to: 1
            // motion-exception: Folder-drop progress is the drag acceptance dwell timer.
            duration: 380
            easing.type: Easing.Linear
            onFinished: {
                if (desktopFileGrid.folderDropCandidatePath !== "") {
                    desktopFileGrid.dropFolderPath = desktopFileGrid.folderDropCandidatePath
                }
            }
        }

        function updateFolderDropTarget(pointX, pointY, sourcePath) {
            const target = folderAtDropPoint(pointX, pointY, sourcePath)
            const path = target?.path ?? ""
            if (folderDropCandidatePath === path)
                return
            folderDropCandidatePath = path
            dropFolderPath = ""
            folderDropProgressAnimation.stop()
            folderDropProgress = 0
            if (path)
                folderDropProgressAnimation.restart()
        }

        function clearFolderDropTarget() {
            folderDropProgressAnimation.stop()
            folderDropCandidatePath = ""
            dropFolderPath = ""
            folderDropProgress = 0
        }

        function clearGroupDrag() {
            draggingPath = ""
            groupDragOffsetX = 0
            groupDragOffsetY = 0
        }

        Timer {
            id: reorderSettleTimer
            interval: 16
            repeat: false
            onTriggered: desktopFileGrid.reorderSettleActive = false
        }

        function clearReorderSettle() {
            reorderSettleTimer.stop()
            reorderSettleActive = false
            reorderSettleFrom = ({})
        }

        function updateReorderInsertion(path, destinationIndex) {
            const sourceIndex = orderedEntries.findIndex(function(entry) {
                return entry.path === path
            })
            const targetIndex = Math.max(0,
                Math.min(orderedEntries.length - 1, destinationIndex))
            if (sourceIndex === targetIndex) {
                clearReorderInsertion()
                return
            }
            if (reorderPreviewSourcePath === path && reorderInsertionIndex === targetIndex)
                return
            reorderPreviewSourcePath = path
            reorderInsertionIndex = targetIndex
            const offsets = ({})
            for (let index = 0; index < orderedEntries.length; ++index) {
                const entry = orderedEntries[index]
                const offset = reorderPreviewOffsetFor(index, entry.path, path, targetIndex)
                if (offset.x !== 0 || offset.y !== 0)
                    offsets[entry.path] = offset
            }
            reorderPreviewOffsets = offsets
        }

        function clearReorderInsertion() {
            reorderInsertionIndex = -1
            reorderPreviewSourcePath = ""
            reorderPreviewOffsets = ({})
        }

        // Pointer translation feeds the dragged icon directly.  Reordering
        // and folder hit-testing are semantic updates, so cap them to the
        // display cadence instead of doing JS work for every raw motion event.
        Timer {
            id: reorderSemanticTimer
            interval: 16
            repeat: true
            running: desktopFileGrid.reorderDragging
            onTriggered: {
                const sourcePath = desktopFileGrid.reorderDragSourcePath
                const handler = desktopFileGrid.reorderActiveHandler
                if (sourcePath === "" || !handler)
                    return
                const offsetX = handler.activeTranslation.x
                const offsetY = handler.activeTranslation.y
                desktopFileGrid.reorderPointerX = desktopFileGrid.reorderPressPointerX + offsetX
                desktopFileGrid.reorderPointerY = desktopFileGrid.reorderPressPointerY + offsetY
                if (desktopFileGrid.reorderDragEntryCount > 1) {
                    desktopFileGrid.draggingPath = sourcePath
                    desktopFileGrid.groupDragOffsetX = offsetX
                    desktopFileGrid.groupDragOffsetY = offsetY
                }
                desktopFileGrid.updateFolderDropTarget(
                    desktopFileGrid.reorderPointerX, desktopFileGrid.reorderPointerY, sourcePath)
                if (desktopFileGrid.reorderDragEntryCount === 1
                        && desktopFileGrid.folderDropCandidatePath === "")
                    desktopFileGrid.updateReorderInsertion(sourcePath,
                        desktopFileGrid.indexAt(desktopFileGrid.reorderPointerX,
                            desktopFileGrid.reorderPointerY))
            }
        }

        function gridPositionForIndex(index) {
            return {
                x: columnForIndex(index) * itemWidth,
                y: (index % rowCount) * itemHeight
            }
        }

        // This is deliberately only a visual translation. Delegates retain
        // their unique grid coordinates until the drop commits the order,
        // so a transient preview can never assign two entries to one slot.
        function reorderPreviewOffsetFor(index, path, sourcePath, targetIndex) {
            if (targetIndex < 0 || path === sourcePath)
                return ({ x: 0, y: 0 })
            const sourceIndex = orderedEntries.findIndex(function(entry) {
                return entry.path === sourcePath
            })
            if (sourceIndex < 0)
                return ({ x: 0, y: 0 })
            let previewIndex = index
            if (sourceIndex < targetIndex && index > sourceIndex && index <= targetIndex)
                previewIndex = index - 1
            else if (sourceIndex > targetIndex
                    && index >= targetIndex && index < sourceIndex)
                previewIndex = index + 1
            if (previewIndex === index)
                return ({ x: 0, y: 0 })
            const from = gridPositionForIndex(index)
            const to = gridPositionForIndex(previewIndex)
            return ({ x: to.x - from.x, y: to.y - from.y })
        }

        function ordered(source) {
            let saved = []
            try { saved = JSON.parse(desktopLayout.orderJson) } catch (_) {}
            const positions = ({})
            for (let index = 0; index < saved.length; ++index)
                positions[saved[index]] = index
            return source.slice().sort(function(left, right) {
                const leftIndex = positions[left.path]
                const rightIndex = positions[right.path]
                // Manually placed icons always stay put. New paths have no
                // saved slot yet, so append them in a stable, visible order
                // instead of relying on an ambiguous comparator result.
                if (leftIndex === undefined && rightIndex === undefined) {
                    const leftTime = Number(left.modifiedAt) || 0
                    const rightTime = Number(right.modifiedAt) || 0
                    if (leftTime !== rightTime)
                        return leftTime - rightTime
                    return (left.name || "").localeCompare(right.name || "")
                }
                if (leftIndex === undefined) return 1
                if (rightIndex === undefined) return -1
                return leftIndex - rightIndex
            })
        }

        function reorder(path, destinationIndex, wasPreviewed) {
            const next = orderedEntries.slice()
            const sourceIndex = next.findIndex(function(entry) { return entry.path === path })
            if (sourceIndex < 0)
                return
            const targetIndex = Math.max(0, Math.min(next.length - 1, destinationIndex))
            if (sourceIndex === targetIndex)
                return
            const previousPositions = ({})
            for (let index = 0; index < next.length; ++index) {
                previousPositions[next[index].path] = ({
                    x: columnForIndex(index) * itemWidth,
                    y: (index % rowCount) * itemHeight
                })
            }
            const entry = next.splice(sourceIndex, 1)[0]
            next.splice(targetIndex, 0, entry)
            // The dragged item itself is already under the pointer. Only the
            // displaced neighbours animate into their new positions after a
            // successful drop, never while the user is still deciding.
            const sourceNewIndex = next.findIndex(function(candidate) {
                return candidate.path === path
            })
            previousPositions[path] = ({
                x: columnForIndex(sourceNewIndex) * itemWidth,
                y: (sourceNewIndex % rowCount) * itemHeight
            })
            if (!wasPreviewed) {
                reorderSettleFrom = previousPositions
                reorderSettleActive = true
            }
            saveOrder(next)
            if (!wasPreviewed)
                reorderSettleTimer.restart()
        }

        function saveOrder(entries) {
            const paths = entries.map(function(item) { return item.path })
            let saved = []
            try { saved = JSON.parse(desktopLayout.orderJson) } catch (_) {}
            // Preserve the other screens' relative order in the shared file.
            desktopLayout.orderJson = JSON.stringify(saved.filter(function(path) {
                return paths.indexOf(path) < 0
            }).concat(paths))
            desktopLayout.sync()
        }

        function arrange(compare) {
            const next = screenEntries.slice().sort(function(left, right) {
                const leftIsFolder = left.kind === "folder"
                const rightIsFolder = right.kind === "folder"
                if (leftIsFolder !== rightIsFolder)
                    return leftIsFolder ? -1 : 1
                const result = compare(left, right)
                return result || (left.name || "").localeCompare(right.name || "")
            })
            saveOrder(next)
            freeSlotDesktop.resetLayout(next)
        }

        function arrangeByName() {
            arrange(function(left, right) {
                return (left.name || "").localeCompare(right.name || "")
            })
        }

        function arrangeByType() {
            arrange(function(left, right) {
                return (left.kind || "").localeCompare(right.kind || "")
            })
        }

        function arrangeByModified(newestFirst) {
            arrange(function(left, right) {
                const leftTime = Number(left.modifiedAt) || 0
                const rightTime = Number(right.modifiedAt) || 0
                return newestFirst ? rightTime - leftTime : leftTime - rightTime
            })
        }

        function resetLayout() {
            let saved = []
            try { saved = JSON.parse(desktopLayout.orderJson) } catch (_) {}
            const paths = screenEntries.map(function(entry) { return entry.path })
            desktopLayout.orderJson = JSON.stringify(saved.filter(function(path) { return paths.indexOf(path) < 0 }))
            desktopLayout.sync()
            clearDesktopSelection()
            freeSlotDesktop.resetLayout(ordered(screenEntries))
        }

        function setIconSize(size) {
            if (size !== 32 && size !== 40 && size !== 56 && size !== 72)
                return
            desktopLayout.iconSize = size
            desktopLayout.sync()
        }

        function setIconSpacing(spacing) {
            if (["comfortable", "compact", "dense"].indexOf(spacing) < 0)
                return
            desktopLayout.iconSpacing = spacing
            desktopLayout.sync()
        }

        function setShortcutAlignment(alignment) {
            if (alignment !== "left" && alignment !== "right")
                return
            desktopLayout.shortcutAlignment = alignment
            desktopLayout.sync()
        }

        function columnForIndex(index) {
            return DesktopGridMetrics.columnForSlot(index, rowCount,
                columnCount, desktopLayout.shortcutAlignment)
        }
        function indexForCell(column, row) {
            return DesktopGridMetrics.slotForCell(column, row, rowCount,
                columnCount, desktopLayout.shortcutAlignment)
        }

        function displayName(entry) {
            const name = entry?.title || entry?.name || ""
            if (desktopLayout.showExtensions || entry?.kind === "folder")
                return name
            const extensionIndex = name.lastIndexOf(".")
            return extensionIndex > 0 ? name.slice(0, extensionIndex) : name
        }

        function beginInlineRename(entry) {
            if (!entry?.path)
                return
            root.desktopFiles.lastError = ""
            const path = entry.path
            // Platform.Menu owns focus while it is closing. Defer editor
            // activation by one event-loop turn so the menu cannot immediately
            // steal focus back and trigger the editor's focus-loss commit.
            Qt.callLater(function() {
                freeSlotDesktop.beginRename(path)
            })
        }

        function commitRename(entry, name) {
            const newName = (name ?? "").trim()
            if (!entry?.path || !root.desktopFiles.validName(newName)) {
                root.desktopFiles.lastError = I18n.tr("Name cannot be empty and cannot contain /")
                return false
            }
            const newPath = root.desktopFiles.directory + "/" + newName
            if (newPath !== entry.path) {
                const clash = root.desktopFiles.entries.some(function(candidate) {
                    return candidate.path === newPath
                })
                if (clash) {
                    root.desktopFiles.lastError = I18n.tr("That name is already in use")
                    return false
                }
            }
            const oldPath = entry.path
            return root.desktopFiles.renameEntry(entry, newName, function() {
                if (newPath !== oldPath)
                    desktopFileGrid.migrateFolderCustom(oldPath, newPath)
            })
        }

        function createNewFolder() {
            pendingRenamePath = ""
            root.desktopFiles.createUntitledFolder(function(path) {
                desktopFileGrid.pendingRenamePath = path
                Qt.callLater(function() { desktopFileGrid.startPendingRename() })
            }, root.desktopOutput)
        }

        function createNewFile() {
            pendingRenamePath = ""
            root.desktopFiles.createUntitledFile(function(path) {
                desktopFileGrid.pendingRenamePath = path
                Qt.callLater(function() { desktopFileGrid.startPendingRename() })
            }, root.desktopOutput)
        }

        function startPendingRename() {
            if (!pendingRenamePath)
                return
            const entry = orderedEntries.find(function(candidate) {
                return candidate.path === pendingRenamePath
            })
            if (!entry)
                return
            pendingRenamePath = ""
            selectOnly(entry.path)
            beginInlineRename(entry)
        }

        function renameSelectionEnd(entry) {
            const name = entry?.name ?? ""
            if (entry?.kind === "folder")
                return name.length
            const extensionIndex = name.lastIndexOf(".")
            // Finder keeps the suffix in the editor but initially selects
            // only the base name, so typing does not accidentally change the
            // file type.
            return extensionIndex > 0 ? extensionIndex : name.length
        }

        function isSelected(path) {
            return selectedPaths.indexOf(path) >= 0
        }

        function selectedEntries() {
            return orderedEntries.filter(function(entry) {
                return isSelected(entry.path)
            })
        }

        function activateKeyboard() {
            desktopKeyboard.forceActiveFocus()
        }

        function handleClipboardShortcut(event) {
            if (!(event.modifiers & Qt.ControlModifier))
                return false
            if (event.key === Qt.Key_C) {
                root.desktopFiles.copyEntries(selectedEntries(), "copy")
            } else if (event.key === Qt.Key_X) {
                root.desktopFiles.copyEntries(selectedEntries(), "cut")
            } else if (event.key === Qt.Key_V) {
                root.desktopFiles.pasteIntoDesktop(root.desktopOutput)
            } else {
                return false
            }
            event.accepted = true
            return true
        }

        function setSelectedPaths(paths) {
            selectedPaths = paths.slice()
        }

        function selectOnly(path) {
            setSelectedPaths(path ? [path] : [])
        }

        function toggleSelection(path) {
            const next = selectedPaths.slice()
            const index = next.indexOf(path)
            if (index >= 0)
                next.splice(index, 1)
            else
                next.push(path)
            setSelectedPaths(next)
        }

        function selectInBox(left, top, right, bottom, additive) {
            const minX = Math.min(left, right)
            const maxX = Math.max(left, right)
            const minY = Math.min(top, bottom)
            const maxY = Math.max(top, bottom)
            const next = additive ? selectionBase.slice() : []
            for (let index = 0; index < orderedEntries.length; ++index) {
                const entry = orderedEntries[index]
                const column = columnForIndex(index)
                const row = index % rowCount
                if (column < 0)
                    continue
                const itemX = column * itemWidth
                const itemY = row * itemHeight
                const intersects = itemX < maxX && itemX + itemWidth > minX
                    && itemY < maxY && itemY + itemHeight > minY
                if (intersects && next.indexOf(entry.path) < 0)
                    next.push(entry.path)
            }
            setSelectedPaths(next)
        }

        function gridPoint(pointer, mouse) {
            return pointer.mapToItem(desktopFileGrid, mouse.x, mouse.y)
        }

        function iconFor(kind) {
            const type = ["folder", "image", "pdf", "code", "text", "launcher"].indexOf(kind) >= 0 ? kind : "text"
            return "desktop.file." + type
        }

        function canChooseOpenWith(entry) {
            // Background menus have no entry.  Treating undefined as a
            // non-folder used to make showMenu() dereference entry.path.
            return !!entry && entry.kind !== "folder" && entry.kind !== "launcher"
        }

        function applicationName(id) {
            // Resolve through the same desktop-entry identity layer used by
            // the Dock.  gio returns filenames (for example nvim.desktop),
            // while the visible label must be the entry's Name field.
            try { return AppIdentityService.resolve(id)?.name || id } catch (_) { return id || I18n.tr("Default app") }
        }

        function openWithIdAt(index) {
            return root.desktopFiles.openWith.handlers[index] || ""
        }

        function defaultOpenText() {
            const handler = root.desktopFiles.openWith.defaultId
            return handler ? I18n.tr("Open with %1").arg(applicationName(handler)) : I18n.tr("Open")
        }

        function showMenu(entry, windowPoint) {
            contextEntry = entry || null
            // Build and show immediately - never block the right click on the
            // async gio open-with query (a slow/failed query must not make a
            // right click appear to do nothing).
            //
            // Do not use a timed rebuild here: setItems() intentionally resets
            // ContextMenu's navigation path, which made a folder's appearance
            // submenu disappear while it was being browsed.
            if (entry && canChooseOpenWith(entry)) {
                const entryPath = entry.path
                root.desktopFiles.queryOpenWith(entry, function() {
                    // A result may arrive after another item was right-clicked.
                    // Refresh only the still-open root menu; once the user has
                    // entered a submenu, keep that interaction stable and show
                    // the refreshed open-with list on the next invocation.
                    if (desktopContextMenu.visible
                            && contextEntry?.path === entryPath
                            && desktopContextMenu.atRoot)
                        desktopFileGrid.setContextMenuItems()
                })
            }
            desktopFileGrid.setContextMenuItems()
            const pt = windowPoint && windowPoint.x !== undefined
                ? windowPoint : Qt.point(desktopFileGrid.width - 12, 12)
            desktopContextAnchor.x = pt.x
            desktopContextAnchor.y = pt.y
            desktopContextMenu.show()
        }

        function clearDesktopSelection() {
            selectedPaths = []
            freeSlotDesktop.selectedIds = []
            desktopContextMenu.hide()
            contextEntry = null
        }

        function triggerContextAction(kind) {
            const entry = contextEntry
            desktopContextMenu.hide()
            contextEntry = null
            if (kind === "folder")
                createNewFolder()
            else if (kind === "file")
                createNewFile()
            else if (kind === "openEntry")
                root.desktopFiles.openEntry(entry)
            else if (kind === "rename")
                beginInlineRename(entry)
            else if (kind === "openWithMore")
                openWithDialog.show(entry)
            else if (kind === "trash") {
                const entries = selectedEntries()
                selectedPaths = []
                freeSlotDesktop.selectedIds = []
                root.desktopFiles.trashEntries(entries, function() {
                    DockTrashService.celebrateDeposit()
                })
            }
            else if (kind === "copy")
                root.desktopFiles.copyEntries(selectedEntries(), "copy")
            else if (kind === "cut")
                root.desktopFiles.copyEntries(selectedEntries(), "cut")
            else if (kind === "paste")
                root.desktopFiles.pasteIntoDesktop(root.desktopOutput)
            else if (kind === "open")
                root.desktopFiles.openDirectory()
            else if (kind === "arrange")
                arrangeByName()
            else if (kind === "resetLayout")
                resetLayout()
            else if (["lock", "suspend", "switch", "logout", "reboot", "poweroff"]
                     .indexOf(kind) >= 0)
                // Routed through the control center so the destructive
                // entries reuse its shared confirmation dialog.
                ControlCenterService.requestSessionAction(kind)
        }

        // ── Liquid context-menu data + builder ──

        function _ctxSub(label, children, role) {
            return { icon: "desktop.menu." + role, label: label, children: children }
        }
        function _ctxAct(label, cmd) {
            return { icon: "desktop.menu." + cmd, label: label, cmd: cmd, enabled: true }
        }
        function _ctxCheck(label, cmd, value, checked) {
            return { icon: "desktop.menu." + cmd, label: label, cmd: cmd,
                checkable: true, checked: checked, value: value, enabled: true }
        }

        function buildContextItems() {
        const FOLDER_COLORS = [
            [I18n.tr("Default"), ""], [I18n.tr("🔴 Red"), "#FF6B6B"], [I18n.tr("🟠 Orange"), "#FFA94D"],
            [I18n.tr("🟡 Yellow"), "#FFD43B"], [I18n.tr("🟢 Green"), "#69DB7C"],
            [I18n.tr("🔵 Blue"), "#4DABF7"], [I18n.tr("🟣 Purple"), "#9775FA"],
            [I18n.tr("🩷 Pink"), "#F783AC"], [I18n.tr("⚫ Gray"), "#868E96"]
            ]
            const EMOJI_CATS = [
            { id: "frequent", label: I18n.tr("Frequent"), rows: [
                ["📁 " + I18n.tr("Folder"), "📁"], ["📂 " + I18n.tr("Open folder"), "📂"],
                ["🗂️ " + I18n.tr("Organized folder"), "🗂️"], ["📦 " + I18n.tr("Package"), "📦"],
                ["⭐ " + I18n.tr("Star"), "⭐"], ["🔥 " + I18n.tr("Hot"), "🔥"],
                ["💡 " + I18n.tr("Idea"), "💡"], ["❤️ " + I18n.tr("Favorites"), "❤️"],
                ["✨ " + I18n.tr("Curated"), "✨"], [I18n.tr("📌 Pinned"), "📌"],
                ["🎯 " + I18n.tr("Goal"), "🎯"], ["💎 " + I18n.tr("Collection"), "💎"]
            ] },
            { id: "study", label: I18n.tr("Study"), rows: [
                ["📚 " + I18n.tr("Books"), "📚"], ["📖 " + I18n.tr("Reading"), "📖"],
                ["✏️ " + I18n.tr("Notes"), "✏️"], ["📝 " + I18n.tr("Memo"), "📝"],
                ["🎓 " + I18n.tr("Academic"), "🎓"], ["🔬 " + I18n.tr("Research"), "🔬"],
                ["🧪 " + I18n.tr("Experiment"), "🧪"], ["💻 " + I18n.tr("Coding"), "💻"],
                ["🖥️ " + I18n.tr("Workstation"), "🖥️"], ["📐 " + I18n.tr("Design"), "📐"],
                ["🎨 " + I18n.tr("Creative"), "🎨"], ["🎵 " + I18n.tr("Music"), "🎵"]
            ] },
            { id: "life", label: I18n.tr("Life"), rows: [
                ["🏠 " + I18n.tr("Home"), "🏠"], ["🏡 " + I18n.tr("Homestead"), "🏡"],
                ["🛒 " + I18n.tr("Shopping"), "🛒"], ["🍳 " + I18n.tr("Cooking"), "🍳"],
                ["☕ " + I18n.tr("Coffee"), "☕"], ["🌿 " + I18n.tr("Plants"), "🌿"],
                ["🎮 " + I18n.tr("Games"), "🎮"], ["🎬 " + I18n.tr("Movies"), "🎬"],
                ["📷 " + I18n.tr("Photos"), "📷"], ["✈️ " + I18n.tr("Travel"), "✈️"],
                ["🚗 " + I18n.tr("Commute"), "🚗"], ["💰 " + I18n.tr("Finance"), "💰"]
            ] },
            { id: "symbols", label: I18n.tr("Symbols"), rows: [
                ["🔵 " + I18n.tr("Blue dot"), "🔵"], ["🟢 " + I18n.tr("Green dot"), "🟢"],
                ["🟡 " + I18n.tr("Yellow dot"), "🟡"], ["🟠 " + I18n.tr("Orange dot"), "🟠"],
                ["🔴 " + I18n.tr("Red dot"), "🔴"], ["🟣 " + I18n.tr("Purple dot"), "🟣"],
                ["⚫ " + I18n.tr("Black dot"), "⚫"], ["⚪ " + I18n.tr("White dot"), "⚪"],
                ["⬛ " + I18n.tr("Square"), "⬛"], ["🔶 " + I18n.tr("Diamond"), "🔶"],
                ["⚡ " + I18n.tr("Lightning"), "⚡"], ["🌈 " + I18n.tr("Rainbow"), "🌈"]
            ] }
            ]
            const e = contextEntry
            const path = e?.path ?? ""
            const custom = folderCustomFor(path)
            const curColor = custom?.color ?? ""
            const curEmoji = custom?.emoji ?? ""
            const items = []

            if (e) {
                items.push(_ctxAct(defaultOpenText(), "openEntry"))
                if (selectedEntries().length === 1)
                    items.push(_ctxAct(I18n.tr("Rename"), "rename"))

                // 自定义外观 applies to every desktop entry. The path-based
                // storage retains the setting across filesystem snapshots.
                const colorKids = FOLDER_COLORS.map(([label, val]) =>
                    _ctxCheck(label, "setColor", val, curColor === val))
                const appearKids = [ _ctxSub(I18n.tr("Color"), colorKids, "color") ]
                for (const cat of EMOJI_CATS) {
                    const rows = [_ctxCheck(I18n.tr("None"), "setEmoji", "", curEmoji === "")]
                        .concat(cat.rows.map(([label, em]) =>
                            _ctxCheck(label, "setEmoji", em, curEmoji === em)))
                    appearKids.push(_ctxSub(cat.label, rows, "emoji." + cat.id))
                }
                appearKids.push(_ctxAct(I18n.tr("Remove customization"), "removeCustom"))
                items.push(_ctxSub(I18n.tr("Customize Appearance"), appearKids, "appearance"))

                // 打开方式（动态）
                if (canChooseOpenWith(e)) {
                    const owKids = []
                    for (let i = 0; i < 6; i++) {
                        const id = openWithIdAt(i)
                        if (id)
                            owKids.push({ icon: "desktop.menu.openWith", label: applicationName(id), cmd: "openWith", value: id, enabled: true })
                    }
                    owKids.push(_ctxAct(I18n.tr("Other applications…"), "openWithMore"))
                    items.push(_ctxSub(I18n.tr("Open With"), owKids, "openWith"))
                }

                items.push(_ctxAct(I18n.tr("Copy"), "copy"))
                items.push(_ctxAct(I18n.tr("Cut"), "cut"))
                items.push(_ctxAct(I18n.tr("Move to Trash"), "trash"))
                items.push(_ctxAct(I18n.tr("Open in File Manager"), "open"))
            } else {
                // desktop background
                items.push(_ctxAct(I18n.tr("Edit Widgets"), "editWidgets"))
                items.push(_ctxAct(I18n.tr("New File"), "newFile"))
                items.push(_ctxAct(I18n.tr("New Folder"), "newFolder"))
                items.push(_ctxAct(I18n.tr("Paste"), "paste"))
                items.push({ separator: true })
                const arrange = [
                    _ctxAct(I18n.tr("By Name"), "arrangeByName"),
                    _ctxAct(I18n.tr("By Type"), "arrangeByType"),
                    _ctxAct(I18n.tr("By Modified (newest)"), "arrangeModifiedNew"),
                    _ctxAct(I18n.tr("By Modified (oldest)"), "arrangeModifiedOld"),
                    { separator: true },
                    _ctxCheck(I18n.tr("Align Left"), "setShortcutAlignment", "left",
                        desktopLayout.shortcutAlignment === "left"),
                    _ctxCheck(I18n.tr("Align Right"), "setShortcutAlignment", "right",
                        desktopLayout.shortcutAlignment === "right")
                ]
                items.push(_ctxSub(I18n.tr("Arrange"), arrange, "arrange"))
                items.push(_ctxAct(I18n.tr("Reset icon order"), "resetLayout"))
                items.push(_ctxCheck(I18n.tr("Show file extensions"), "toggleExtensions", null,
                    desktopLayout.showExtensions))
                const sizeKids = [[32, I18n.tr("Extra Small")],
                    [40, I18n.tr("Small")], [56, I18n.tr("Medium")],
                    [72, I18n.tr("Large")]]
                    .map(([px, l]) => _ctxCheck(l, "setIconSize", px,
                        iconSize === px))
                items.push(_ctxSub(I18n.tr("Icon Size"), sizeKids, "iconSize"))
                const spacingKids = [
                    ["comfortable", I18n.tr("Comfortable")], ["compact", I18n.tr("Compact")],
                    ["dense", I18n.tr("Dense")]]
                    .map(([value, label]) => _ctxCheck(label, "setIconSpacing", value,
                        desktopLayout.iconSpacing === value))
                items.push(_ctxSub(I18n.tr("Icon Spacing"), spacingKids, "iconSpacing"))
                // Same entries as the control center's session list, routed
                // through it so the destructive ones reuse its confirm dialog.
                items.push(_ctxSub(I18n.tr("Power Off or Log Out"), [
                    _ctxAct(I18n.tr("Lock Screen"), "lock"),
                    _ctxAct(I18n.tr("Sleep"), "suspend"),
                    _ctxAct(I18n.tr("Switch User"), "switch"),
                    _ctxAct(I18n.tr("Log Out"), "logout"),
                    _ctxAct(I18n.tr("Restart"), "reboot"),
                    _ctxAct(I18n.tr("Power Off"), "poweroff")
                ], "session"))
            }
            return items
        }

        function setContextMenuItems() {
            desktopContextMenu.setItems(buildContextItems())
        }

        function runContextCmd(cmd, item) {
            const e = contextEntry
            const path = e?.path ?? ""
            const v = item?.value
            switch (cmd) {
            case "editWidgets": root.enterWidgetEditMode(); break
            case "openEntry": triggerContextAction("openEntry"); break
            case "rename": triggerContextAction("rename"); break
            case "setColor": setFolderColor(path, v); break
            case "setEmoji": setFolderEmoji(path, v); break
            case "removeCustom": removeFolderCustom(path); break
            case "openWith": root.desktopFiles.launchWith(e, v); break
            case "openWithMore": root.desktopFiles.showKdeOpenWith(e); break
            case "copy": triggerContextAction("copy"); break
            case "cut": triggerContextAction("cut"); break
            case "trash": triggerContextAction("trash"); break
            case "open": triggerContextAction("open"); break
            case "newFile": triggerContextAction("file"); break
            case "newFolder": triggerContextAction("folder"); break
            case "paste": triggerContextAction("paste"); break
            case "arrangeByName": arrangeByName(); break
            case "arrangeByType": arrangeByType(); break
            case "arrangeModifiedNew": arrangeByModified(true); break
            case "arrangeModifiedOld": arrangeByModified(false); break
            case "resetLayout": triggerContextAction("resetLayout"); break
            case "toggleExtensions":
                desktopLayout.showExtensions = !desktopLayout.showExtensions
                desktopLayout.sync()
                break
            case "setIconSize": setIconSize(v); break
            case "setIconSpacing": setIconSpacing(v); break
            case "setShortcutAlignment": setShortcutAlignment(v); break
            case "refresh": triggerContextAction("refresh"); break
            // Session entries live in a submenu; without these the menu closes
            // and the command is dropped.
            case "lock":
            case "suspend":
            case "switch":
            case "logout":
            case "reboot":
            case "poweroff":
                triggerContextAction(cmd); break
            }
        }

        function indexAt(pointX, pointY) {
            const column = Math.max(0, Math.min(columnCount - 1, Math.floor(pointX / itemWidth)))
            const row = Math.max(0, Math.min(rowCount - 1, Math.floor(pointY / itemHeight)))
            const index = indexForCell(column, row)
            return Math.max(0, Math.min(orderedEntries.length - 1, index))
        }

        function folderAtDropPoint(pointX, pointY, sourcePath) {
            if (!Number.isFinite(pointX) || !Number.isFinite(pointY)
                    || pointX < 0 || pointY < 0
                    || pointX >= width || pointY >= height)
                return null
            // Check the folder's rendered position rather than its original
            // grid cell: a neighbour may currently be shifted by the live
            // reorder preview. The hit area includes the icon and filename,
            // but deliberately leaves the cell gutters free for sorting.
            for (let index = 0; index < orderedEntries.length; ++index) {
                const entry = orderedEntries[index]
                if (entry?.kind !== "folder" || entry.path === sourcePath)
                    continue
                const base = gridPositionForIndex(index)
                const offset = reorderPreviewOffsets[entry.path] ?? ({ x: 0, y: 0 })
                const hitWidth = Math.min(itemWidth - 16, iconSize + 40)
                const hitLeft = base.x + offset.x + (itemWidth - hitWidth) / 2
                const hitTop = base.y + offset.y + 5
                const hitHeight = Math.min(itemHeight - 10, iconSize + 42)
                if (pointX >= hitLeft && pointX <= hitLeft + hitWidth
                        && pointY >= hitTop && pointY <= hitTop + hitHeight)
                    return entry
            }
            return null
        }

        Item {
            id: desktopKeyboard
            anchors.fill: parent
            focus: true
            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape && root.editMode) {
                    root.leaveWidgetEditMode()
                    event.accepted = true
                    return
                }
                if (desktopFileGrid.handleClipboardShortcut(event))
                    return
                if (event.key === Qt.Key_Return && !desktopFileGrid.renamingPath
                        && desktopFileGrid.selectedEntries().length === 1) {
                    desktopFileGrid.beginInlineRename(desktopFileGrid.selectedEntries()[0])
                    event.accepted = true
                }
            }
        }

        Connections {
            target: root.desktopFiles
            function onEntriesChanged() {
                // Let orderedEntries and the free-slot surface consume the new
                // service snapshot before focusing the newly-created item.
                Qt.callLater(function() {
                    desktopFileGrid.startPendingRename()
                })
            }
            function onLastErrorChanged() {
                if (root.desktopFiles.lastError && root.desktopOutput === root.desktopFiles.defaultOutput)
                    root.sendTimerNotification(I18n.tr("Desktop Files"), root.desktopFiles.lastError)
            }
        }

        MouseArea {
            id: desktopBackgroundPointer
            anchors.fill: parent
            acceptedButtons: Qt.RightButton | Qt.LeftButton
            enabled: false
            onPressed: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    // Right-click is pointer-only: requesting focus here can
                    // interfere with the platform menu's dismissal path.
                    desktopFileGrid.setSelectedPaths([])
                    desktopFileGrid.contextEntry = null
                    desktopFileGrid.showMenu(null,
                        desktopBackgroundPointer.mapToItem(root, mouse.x, mouse.y))
                    return
                }
                desktopContextMenu.hide()
                desktopFileGrid.contextEntry = null
                const point = desktopFileGrid.gridPoint(desktopBackgroundPointer, mouse)
                desktopFileGrid.selectionStartX = point.x
                desktopFileGrid.selectionStartY = point.y
                desktopFileGrid.selectionEndX = point.x
                desktopFileGrid.selectionEndY = point.y
                desktopFileGrid.selectionBoxActive = false
                desktopFileGrid.selectionBase = (mouse.modifiers & Qt.ControlModifier)
                    ? desktopFileGrid.selectedPaths.slice() : []
                desktopFileGrid.activateKeyboard()
            }
            onPositionChanged: function(mouse) {
                if (!pressed || !(mouse.buttons & Qt.LeftButton))
                    return
                const point = desktopFileGrid.gridPoint(desktopBackgroundPointer, mouse)
                desktopFileGrid.selectionEndX = point.x
                desktopFileGrid.selectionEndY = point.y
                if (!desktopFileGrid.selectionBoxActive
                        && (Math.abs(point.x - desktopFileGrid.selectionStartX) > 4
                            || Math.abs(point.y - desktopFileGrid.selectionStartY) > 4))
                    desktopFileGrid.selectionBoxActive = true
                if (desktopFileGrid.selectionBoxActive)
                    desktopFileGrid.selectInBox(
                        desktopFileGrid.selectionStartX, desktopFileGrid.selectionStartY,
                        point.x, point.y, !!(mouse.modifiers & Qt.ControlModifier))
            }
            onReleased: function(mouse) {
                if (mouse.button !== Qt.LeftButton)
                    return
                const wasBoxSelection = desktopFileGrid.selectionBoxActive
                desktopFileGrid.selectionBoxActive = false
                // A plain empty click clears the selection only after it is
                // known not to have become a drag-selection gesture.
                if (!wasBoxSelection && !(mouse.modifiers & Qt.ControlModifier))
                    desktopFileGrid.setSelectedPaths([])
            }
        }

        Rectangle {
            x: Math.min(desktopFileGrid.selectionStartX, desktopFileGrid.selectionEndX)
            y: Math.min(desktopFileGrid.selectionStartY, desktopFileGrid.selectionEndY)
            width: Math.abs(desktopFileGrid.selectionEndX - desktopFileGrid.selectionStartX)
            height: Math.abs(desktopFileGrid.selectionEndY - desktopFileGrid.selectionStartY)
            opacity: desktopFileGrid.selectionBoxActive ? 1 : 0
            visible: false
            color: Qt.rgba(0, 0, 0, 0.20)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.34) }
            z: 1
            Behavior on opacity {
                NumberAnimation { duration: AppearanceTokens.motion.fast.duration; easing.type: AppearanceTokens.motion.enterCurve }
            }
        }


        FreeSlotDesktopDemo {
            id: freeSlotDesktop
            x: -desktopFileGrid.x
            y: -desktopFileGrid.y
            width: root.width
            height: root.height
            validX: desktopFileGrid.x
            validY: desktopFileGrid.y
            validWidth: desktopFileGrid.width
            validHeight: desktopFileGrid.height
            baseCellWidth: desktopFileGrid.preferredItemWidth
            baseCellHeight: desktopFileGrid.itemHeight
            density: desktopFileGrid.desktopLayout.iconSpacing
            alignment: desktopFileGrid.desktopLayout.shortcutAlignment
            iconVisualSize: desktopFileGrid.iconSize + 12
            showExtensions: desktopFileGrid.desktopLayout.showExtensions
            folderCustomizations: desktopFileGrid._folderCustomCache
            renameCallback: function(entry, name) {
                return desktopFileGrid.commitRename(entry, name)
            }
            // Reuse the existing notify-backed service snapshot together with
            // the persisted desktop order. The drag demo only replaces the
            // layout algorithm, not the desktop's data pipeline.
            entries: desktopFileGrid.orderedEntries
            savedSlots: root.desktopFiles.slotsForOutput(root.desktopOutput)
            onLayoutCommitted: function(slots) {
                root.desktopFiles.saveSlots(root.desktopOutput, slots)
            }
            onMoveIntoFolderRequested: function(sourceEntries, targetFolder) {
                root.desktopFiles.moveEntriesToFolder(sourceEntries, targetFolder)
            }
            onSelectedIdsChanged: {
                desktopFileGrid.setSelectedPaths(selectedIds)
            }
            onContextMenuRequested: function(entry, pos) {
                // Bare desktop while editing: dismiss the session instead of
                // opening the menu that re-enters it. A file keeps its own
                // menu, it acts on that file rather than on the desktop.
                if (entry === null && root.editMode) {
                    root.leaveWidgetEditMode()
                    return
                }
                desktopFileGrid.setSelectedPaths(freeSlotDesktop.selectedIds)
                desktopFileGrid.contextEntry = entry
                // freeSlotDesktop is offset by (-gridX,-gridY); translate its
                // local click point back into window coords for the anchor.
                desktopFileGrid.showMenu(entry,
                    Qt.point(pos.x + freeSlotDesktop.x, pos.y + freeSlotDesktop.y))
            }
            onOpenRequested: function(entry) {
                root.desktopFiles.openEntry(entry)
            }
            onActivityRequested: desktopFileGrid.activateKeyboard()
            onBackgroundPressAndHold: root.enterWidgetEditMode()
            // 空桌面普通单击：编辑模式下退出编辑（只收尾，位置/尺寸各自
            // 手势里已落盘），否则＝显示桌面开关。这个 MouseArea 盖住绝大
            // 部分桌面，是比背景捕获器更主要的入口。
            onBackgroundPlainClicked: {
                if (root.editMode)
                    root.leaveWidgetEditMode()
                else
                    StageModeService.deskRevealToggleRequested()
            }
            onExternalUrlsDropped: function(urls, action) {
                root.desktopFiles.importExternalUrls(urls, action, root.desktopOutput)
            }
            z: 30
        }

        // A quiet icon-sized placeholder marks the future slot without
        // moving neighbours, keeping ordering distinct from a folder drop.
        Rectangle {
            id: reorderInsertionMarker
            readonly property int markerColumn: desktopFileGrid.reorderInsertionIndex < 0 ? 0
                : desktopFileGrid.columnForIndex(desktopFileGrid.reorderInsertionIndex)
            readonly property int markerRow: desktopFileGrid.reorderInsertionIndex < 0 ? 0
                : desktopFileGrid.reorderInsertionIndex % desktopFileGrid.rowCount
            x: markerColumn * desktopFileGrid.itemWidth + 7
            y: markerRow * desktopFileGrid.itemHeight + 4
            width: Math.max(36, desktopFileGrid.itemWidth - 14)
            height: Math.max(40, desktopFileGrid.itemHeight - 8)
            radius: 11
            visible: false
            opacity: visible ? 0.42 : 0
            color: Qt.rgba(1, 1, 1, 0.055)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.48) }
            z: 8
            Behavior on opacity {
                NumberAnimation { duration: AppearanceTokens.motion.instant.duration; easing.type: AppearanceTokens.motion.enterCurve }
            }
        }

        ContextMenu {
            id: desktopContextMenu
            capsuleReveal: true
            // The anchor is only a 4px cursor marker; use the Wi-Fi pill size.
            capsuleSourceWidth: 137
            anchorItem: desktopContextAnchor
            position: "bottom"
            placeBelow: true
            baseColor: ThemeService.backgroundColor
            foregroundColor: ThemeService.foregroundColor
            onAction: function(cmd, item) {
                desktopFileGrid.runContextCmd(cmd, item)
            }
        }

        // Kept mapped but invisible (opacity 0 - NOT visible:false, which the
        // compositor window-anchor ignores and falls back to the window corner).
        // It follows the right-click point so the menu opens beside the cursor.
        Item {
            id: desktopContextAnchor
            opacity: 0
            width: 4
            height: 4
        }

        // Desktop-wide dismissal scrim: active only while the context menu is
        // open, so any click on the empty desktop closes it. It does not steal
        // selection/drag events when the menu is closed.
        MouseArea {
            anchors.fill: parent
            z: 999
            enabled: desktopContextMenu.visible
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: desktopContextMenu.hide()
        }

        Rectangle {
            id: desktopDialogScrim
            anchors.fill: parent
            visible: openWithMotion.mapped
            opacity: openWithMotion.progress
            color: Qt.rgba(0, 0, 0, 0.22)
            z: 29
            // Modal prompts should never let an outside click activate or
            // rearrange a desktop icon underneath them.
            MouseArea { anchors.fill: parent; enabled: openWithMotion.interactive }
        }

        PopupMotion { id: openWithMotion }

        Rectangle {
            id: openWithDialog
            anchors.centerIn: parent
            width: 340
            height: 250
            radius: 16
            visible: openWithMotion.mapped
            opacity: openWithMotion.progress
            scale: 0.96 + 0.04 * openWithMotion.geometryProgress
            enabled: openWithMotion.interactive
            color: Qt.rgba(0.12, 0.12, 0.15, 0.98)
            border { width: 1; color: Qt.rgba(1, 1, 1, 0.18) }
            z: 31
            property var entry: null
            property string selectedHandler: ""
            function appName(id) {
                try { return AppIdentityService.resolve(id)?.name || id } catch (_) { return id }
            }
            function show(target) {
                entry = target
                openWithMotion.close()
                root.desktopFiles.queryOpenWith(target, function(info) {
                    if (openWithDialog.entry?.path !== target?.path)
                        return
                    openWithDialog.selectedHandler = info.defaultId || info.handlers[0] || ""
                    openWithMotion.open()
                })
            }
            Text {
                anchors { left: parent.left; top: parent.top; leftMargin: 16; topMargin: 14 }
                text: I18n.tr("Open With")
                color: "white"
                font { pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 36 }
                text: "“" + (openWithDialog.entry?.name ?? "") + "”"
                color: Qt.rgba(1, 1, 1, 0.54)
                elide: Text.ElideRight
                font.pixelSize: 10
            }
            Text {
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 57 }
                text: root.desktopFiles.openWith.mime || I18n.tr("Unrecognized file type")
                color: Qt.rgba(1, 1, 1, 0.42)
                font.pixelSize: 9
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; topMargin: 78; bottomMargin: 46 }
                spacing: 4
                Repeater {
                    model: root.desktopFiles.openWith.handlers
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 28
                        radius: 7
                        color: openWithDialog.selectedHandler === modelData
                            ? Qt.rgba(0, 0, 0, 0.54) : Qt.rgba(1, 1, 1, 0.07)
                        Text {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 9; rightMargin: 9 }
                            text: openWithDialog.appName(modelData)
                            color: "white"
                            elide: Text.ElideRight
                            font.pixelSize: 10
                        }
                        MouseArea { anchors.fill: parent; onClicked: openWithDialog.selectedHandler = modelData }
                    }
                }
                Text {
                    visible: root.desktopFiles.openWith.handlers.length === 0
                    text: I18n.tr("No associated applications found on the system.")
                    color: Qt.rgba(1, 1, 1, 0.52)
                    font.pixelSize: 10
                }
            }
            Row {
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 12 }
                spacing: 8
                Repeater {
                    model: [
                        { id: "cancel", label: I18n.tr("Cancel") },
                        { id: "once", label: I18n.tr("Just Once") },
                        { id: "default", label: I18n.tr("Set as Default") }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: modelData.id === "default" ? 64 : modelData.id === "once" ? 64 : 52
                        height: 26
                        radius: 7
                        color: modelData.id === "default" ? "#4385dc" : Qt.rgba(1, 1, 1, 0.10)
                        opacity: modelData.id === "cancel" || openWithDialog.selectedHandler ? 1 : 0.45
                        Text { anchors.centerIn: parent; text: modelData.label; color: "white"; font.pixelSize: 10 }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (modelData.id === "cancel") openWithMotion.close()
                                else if (openWithDialog.selectedHandler) {
                                    if (modelData.id === "once")
                                        root.desktopFiles.launchWith(openWithDialog.entry, openWithDialog.selectedHandler)
                                    else
                                        root.desktopFiles.setDefaultOpenWith(root.desktopFiles.openWith.mime, openWithDialog.selectedHandler)
                                    openWithMotion.close()
                                }
                            }
                        }
                    }
                }
            }
            Keys.onEscapePressed: openWithMotion.close()
        }

    }
}
