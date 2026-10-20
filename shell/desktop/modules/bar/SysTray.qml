import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"
import "StatusCollection.mjs" as StatusCollection

// StatusNotifierItem host. Referencing SystemTray claims and tracks tray items.
Item {
    id: root
    objectName: "status-tray"

    property int iconSize: 18
    property int iconSpacing: 6
    // Visual-only adjustment; transforms preserve the item's input region
    // and the menu anchor follows the transformed icon position.
    property int visualYOffset: 0
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
    required property Item collectionToggleHost
    readonly property int popupEdge: !dockHosted ? Edges.Bottom
        : dockEdge === "left" ? Edges.Right
        : dockEdge === "right" ? Edges.Left : Edges.Top
    // BarStatusArea appends Wi-Fi, battery, settings and control-centre cells
    // here so native tray items and shell controls share one continuous grid.
    property var trailingComponents: []
    // Parallel to trailingComponents: a stable key per cell, used both for
    // Alt+drag reorder persistence and to look up the matching component.
    property var trailingKeys: []
    // Supplied by BarStatusArea. Keeping this separate from the tray's own
    // implicitHeight avoids a height/row-count binding cycle.
    property real availableHeight: 24
    readonly property int itemSize: iconSize + 8

    // Width of one grid slot. Shell cells whose loaded root declares a
    // `cellExtraWidth` property overflow their square by that amount; native
    // tray items are always plain itemSize squares. Extra width only applies
    // in single-row layouts: the dock's two-row fold never hosts the wide
    // readout, so its uniform grid math stays intact.
    function slotWidth(key) {
        if (root.rowCount > 1)
            return root.itemSize
        const index = root.trailingCellKeys.indexOf(key)
        if (index < 0)
            return root.itemSize
        const extra = root.trailingItem(index)?.cellExtraWidth ?? 0
        return root.itemSize + Math.max(0, extra)
    }

    property int trayRevision: 0
    function notifyTrayChanged() { trayRevision++ }

    // Native tray keys are collected only from valid, active delegates so
    // dead or crashed StatusNotifierItems do not allocate phantom slots.
    readonly property var nativeKeys: {
        const _rev = root.trayRevision
        const keys = []
        for (let i = 0; i < trayRepeater.count; i++) {
            const item = trayRepeater.itemAt(i)
            if (!item || !item.isValid || !item.trayKey)
                continue
            // duplicateOrdinal already makes every live delegate's key unique;
            // this stays only so a stray collision can never push itemCount
            // past the number of slots the delegates actually occupy.
            if (keys.indexOf(item.trayKey) < 0)
                keys.push(item.trayKey)
        }
        return keys
    }
    readonly property var trailingCellKeys: (root.trailingKeys || []).map(key => "cell:" + key)
    readonly property var allKeys: root.nativeKeys.concat(root.trailingCellKeys)
    readonly property var orderedKeys: SysTrayOrderService.arrange(root.allKeys)
    property bool collectionExpanded: false
    property bool collectionKeepOpen: false
    property double collectionOpenedAt: 0
    signal collectionCollapseRequested()
    readonly property var sectionKeys: StatusCollection.sections(root.orderedKeys, SysTrayOrderService.collectedKeys)
    readonly property var collectedKeys: root.sectionKeys.collection
    readonly property var pinnedKeys: root.sectionKeys.strip
    readonly property var previewKeys: root.dragTarget === "strip"
        ? StatusCollection.previewOrder(root.pinnedKeys, root.draggedKey, root.dragInsertIndex)
        : root.pinnedKeys
    readonly property var previewCollectionKeys: root.dragTarget === "collection"
        ? StatusCollection.previewOrder(root.collectedKeys, root.draggedKey, root.dragInsertIndex)
        : root.collectedKeys
    readonly property int itemCount: root.pinnedKeys.length
    readonly property int twoRowThreshold: itemSize * 2
    readonly property bool twoRows: dockHosted && itemCount > 1
        && availableHeight >= twoRowThreshold
    readonly property int rowCount: twoRows ? 2 : 1
    readonly property real singleRowImplicitWidth: {
        let width = 0
        for (const key of root.pinnedKeys) width += root.slotWidth(key)
        return width + Math.max(0, root.itemCount - 1) * root.iconSpacing
    }

    // Let the order service see every key as it appears, so an icon that
    // shows up later is recognisably new and lands at the head of the row
    // instead of sorting with the other never-reordered items.
    onAllKeysChanged: SysTrayOrderService.register(root.allKeys)
    Connections {
        target: SysTrayOrderService
        // The saved order arrives asynchronously; keys seen before it does
        // are registered once it has loaded.
        function onReadyChanged() { SysTrayOrderService.register(root.allKeys) }
    }

    // Handler-level modifier filtering sees the actual press, including Alt
    // pressed after the pointer stopped moving. Hover state is cosmetic only.
    HoverHandler { id: modifierTracker }
    readonly property bool altModifierHeld:
        (modifierTracker.point.modifiers & Qt.AltModifier) !== 0
    property string draggedKey: ""
    property Item dragSourceItem: null
    property bool nativeDragStarted: false
    property int dragSerial: 0
    property var dragImage: null
    property string dragTarget: ""
    property int dragInsertIndex: -1
    property Item dragArea: null
    property point dragDropPoint: Qt.point(0, 0)
    property int dragScrollDirection: 0
    property var pendingDrop: null

    function beginDrag(key, item, handler) {
        if (root.draggedKey !== "") return
        root.draggedKey = key
        root.dragSourceItem = item
        root.pendingDrop = null
        root.nativeDragStarted = false
        root.dragSerial++
        const serial = root.dragSerial
        item.Drag.hotSpot = Qt.point(item.width / 2, item.height / 2)
        item.Drag.mimeData = ({ [StatusCollection.dragMimeType]: key })
        item.grabToImage(function(result) {
            if (serial !== root.dragSerial || !handler.active || root.dragSourceItem !== item)
                return
            root.dragImage = result
            item.Drag.imageSource = result.url
            root.nativeDragStarted = true
            root.collectionExpanded = true
            item.Drag.active = true
        })
    }

    function pointerDragEnded(key) {
        const serial = root.dragSerial
        Qt.callLater(function() {
            // Automatic DnD takes over the pointer grab. Its dragFinished,
            // rather than the handler's deactivation, owns the final drop.
            if (serial === root.dragSerial && root.draggedKey === key && !root.nativeDragStarted)
                root.cancelDrag()
        })
    }

    function clearDrag() {
        root.dragSerial++
        root.draggedKey = ""
        root.dragSourceItem = null
        root.nativeDragStarted = false
        root.dragImage = null
        root.dragTarget = ""
        root.dragInsertIndex = -1
        root.dragArea = null
        root.dragScrollDirection = 0
        root.pendingDrop = null
    }

    function cancelDrag() {
        const item = root.dragSourceItem
        root.clearDrag()
        if (item) item.Drag.cancel()
    }

    function nativeDragFinished(key, action) {
        if (key !== root.draggedKey) return
        const plan = action === Qt.MoveAction ? root.pendingDrop : null
        const item = root.dragSourceItem
        // Reparent only after the native drag has returned, so the source
        // surface and its event grab remain valid for the entire gesture.
        Qt.callLater(function() {
            if (root.draggedKey !== key || root.dragSourceItem !== item) return
            root.clearDrag()
            if (item) {
                item.Drag.active = false
                item.Drag.mimeData = ({})
                item.Drag.imageSource = ""
            }
            if (plan) {
                SysTrayOrderService.setCollected(key, plan.collected)
                SysTrayOrderService.moveKey(key, plan.keys.indexOf(key), plan.keys)
            }
        })
    }

    function slotOriginIn(keys, index) {
        if (index < 0) return Qt.point(0, 0)
        if (root.rowCount === 1) {
            let x = 0
            for (let i = 0; i < index; i++) x += root.slotWidth(keys[i]) + root.iconSpacing
            return Qt.point(x, 0)
        }
        return Qt.point(Math.floor(index / root.rowCount) * (root.itemSize + root.iconSpacing),
            (index % root.rowCount) * root.itemSize)
    }

    function collectionOrigin(index) {
        const layout = collectionPopup.layoutMetrics
        const point = StatusCollection.gridOrigin(Math.max(0, index), layout.columns,
            layout.cellSize, layout.spacing)
        return Qt.point(point.x, point.y)
    }

    function delegateOrigin(key, collected) {
        return collected ? root.collectionOrigin(root.previewCollectionKeys.indexOf(key))
            : root.slotOriginIn(root.previewKeys, root.previewKeys.indexOf(key))
    }

    function dropIndex(section, point) {
        const keys = section === "collection" ? root.collectedKeys : root.pinnedKeys
        if (section === "collection") {
            const layout = collectionPopup.layoutMetrics
            const column = Math.max(0, Math.min(layout.columns - 1,
                Math.floor(point.x / (layout.cellSize + layout.spacing))))
            const row = Math.max(0, Math.floor(point.y / (layout.cellSize + layout.spacing)))
            return Math.min(keys.length, row * layout.columns + column)
        }
        let closest = keys.length, distance = Number.POSITIVE_INFINITY
        for (let i = 0; i < keys.length; i++) {
            const origin = root.slotOriginIn(keys, i)
            const d = (origin.x + root.slotWidth(keys[i]) / 2 - point.x) ** 2
                + (origin.y + root.itemSize / 2 - point.y) ** 2
            if (d < distance) { closest = i; distance = d }
        }
        if (keys.length > 0) {
            const last = root.slotOriginIn(keys, keys.length - 1)
            if (point.x > last.x + root.slotWidth(keys[keys.length - 1])) return keys.length
        }
        return closest
    }

    function updateDropTarget(area, event, section, disclosure) {
        if (!root.nativeDragStarted || root.draggedKey === ""
            || (event.source !== root.dragSourceItem
                && event.formats.indexOf(StatusCollection.dragMimeType) < 0)) {
            event.accepted = false
            return false
        }
        root.dragArea = area
        root.dragDropPoint = Qt.point(event.x, event.y)
        root.dragTarget = section
        if (disclosure) {
            root.collectionExpanded = true
            root.dragInsertIndex = root.collectedKeys.length
            root.dragScrollDirection = 0
        } else {
            root.refreshDropIndex()
        }
        event.accept(Qt.MoveAction)
        return true
    }

    function refreshDropIndex() {
        if (!root.dragArea || root.dragTarget === "") return
        const target = root.dragTarget === "collection" ? collectionPopup.grid : trayFlow
        const point = target.mapFromItem(root.dragArea, root.dragDropPoint.x, root.dragDropPoint.y)
        root.dragInsertIndex = root.dropIndex(root.dragTarget, point)
        if (root.dragTarget === "collection") {
            const y = root.dragDropPoint.y
            root.dragScrollDirection = y < 32 ? -1
                : y > collectionPopup.height - 62 ? 1 : 0
        } else root.dragScrollDirection = 0
    }
    function refreshCollectionDrop() {
        if (root.dragTarget === "collection" && root.dragArea && !root.dragArea.disclosure)
            root.refreshDropIndex()
    }
    function leaveDropTarget(area) {
        if (root.dragArea !== area) return
        root.dragArea = null
        root.dragTarget = ""
        root.dragInsertIndex = -1
        root.dragScrollDirection = 0
    }
    function stageDrop() {
        root.pendingDrop = StatusCollection.dropPlan(root.orderedKeys, SysTrayOrderService.collectedKeys,
            root.draggedKey, root.dragTarget, root.dragInsertIndex)
    }

    function toggleCollection() {
        if (root.collectionExpanded) {
            root.collectionCollapseRequested()
            trayMenu.hide()
            root.collectionExpanded = false
        } else {
            root.collectionExpanded = true
        }
    }
    onCollectionExpandedChanged: if (collectionExpanded) collectionOpenedAt = Date.now()

    function closeCollectionOutside(x, y) {
        const point = root.mapFromItem(null, x, y)
        const togglePoint = collectionToggle.mapFromItem(null, x, y)
        if (!root.contains(point) && !collectionToggle.contains(togglePoint)) root.closeCollection()
    }
    function closeCollection() {
        if (root.draggedKey === "" && !root.collectionKeepOpen && !trayMenu.visible)
            root.collectionExpanded = false
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.collectionExpanded && !root.collectionKeepOpen && !trayMenu.visible
        onActivated: {
            root.cancelDrag()
            root.collectionExpanded = false
        }
    }
    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            if (WindowService.activeWindowId) root.closeCollection()
        }
        function onGlobalPointerPressed(x, y, button, timestamp) {
            // KWin omits presses on popup surfaces. Ignore the entry's own
            // delayed opening press, which belongs to the older timestamp.
            if (Number(timestamp) > root.collectionOpenedAt + 80) root.closeCollection()
        }
    }
    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() {
            if (ContextMenuCoordinator.activeMenu && !trayMenu.visible) root.closeCollection()
        }
    }
    Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable) {
                root.cancelDrag()
                root.collectionExpanded = false
            }
        }
    }

    StatusCollectionPopup {
        id: collectionPopup
        objectName: "status-collection-popup"
        coordinator: root
        anchorItem: collectionToggle
        dockHosted: root.dockHosted
        dockEdge: root.dockEdge
    }

    readonly property int columnCount: itemCount > 0
        ? Math.ceil(itemCount / Math.max(1, rowCount)) : 0
    implicitWidth: rowCount === 1
        ? singleRowImplicitWidth
        : (itemCount > 0
            ? columnCount * itemSize + (columnCount - 1) * iconSpacing : 0)
    implicitHeight: itemCount > 0 ? rowCount * itemSize : 0
    width: implicitWidth
    height: implicitHeight
    transform: Translate { y: root.visualYOffset }

    Item {
        id: trayFlow
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight

        Rectangle {
            id: collectionToggle
            objectName: "status-collection-toggle"
            enabled: SysTrayOrderService.ready
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: root.collectionExpanded ? I18n.tr("Collapse collected icons") : I18n.tr("Show collected icons")
            Accessible.onPressAction: root.toggleCollection()
            Keys.onSpacePressed: root.toggleCollection()
            Keys.onReturnPressed: root.toggleCollection()
            // The host is the first child of BarStatusArea, before CPU and
            // both tray rows. It is never part of the reorderable key list.
            parent: root.collectionToggleHost
            anchors.horizontalCenter: parent.horizontalCenter
            // Side docks rotate the whole cluster clockwise: the lower
            // logical row becomes the physical left column.
            y: (parent.height - root.implicitHeight) / 2
                + (root.verticalDock && root.rowCount > 1 ? root.itemSize : 0)
            width: root.itemSize; height: root.itemSize
            radius: 6
            readonly property bool dropTarget: root.dragTarget === "collection"
            color: dropTarget ? Qt.rgba(0.1, 0.5, 1, 0.22)
                : toggleMouse.containsMouse ? Qt.rgba(ThemeService.barInk.r, ThemeService.barInk.g, ThemeService.barInk.b, 0.10)
                : "transparent"
            border.width: dropTarget ? 1 : 0
            border.color: AppearanceTokens.colors.primary
            BundledIcon {
                anchors.centerIn: parent
                name: root.collectionExpanded ? "status-collection-collapse" : "status-collection-expand"
                size: 18
                color: ThemeService.barInk
            }
            MouseArea {
                id: toggleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.toggleCollection()
                }
            }
            StatusCollectionDropArea {
                anchors.fill: parent
                coordinator: root
                section: "collection"
                disclosure: true
                z: 100
            }
            StatusTooltip {
                anchorItem: collectionToggle
                dockHosted: root.dockHosted
                dockEdge: root.dockEdge
                shown: toggleMouse.containsMouse && !root.collectionExpanded && root.draggedKey === ""
                primaryText: root.collectionExpanded ? I18n.tr("Collapse collected icons") : I18n.tr("Show collected icons")
                secondaryText: root.collectedKeys.length === 0
                    ? I18n.tr("Alt-drag to reorder, collect or keep visible")
                    : I18n.tr("Click to open collection · Alt-drag to reorder")
            }
        }

        Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property var modelData
                required property int index

                readonly property bool isValid: Boolean(modelData && (modelData.icon || modelData.id || modelData.title))
                readonly property string baseTrayKey: {
                    if (!isValid) return ""
                    if (modelData.id && modelData.id.length > 0) {
                        if (modelData.id.indexOf("chrome_status_icon") === 0 && (modelData.tooltipTitle || modelData.title)) {
                            const sub = (modelData.tooltipTitle || modelData.title).trim().split("\n")[0].slice(0, 20)
                            return "tray:" + modelData.id + ":" + sub
                        }
                        return "tray:" + modelData.id
                    }
                    if (modelData.title && modelData.title.length > 0)
                        return "tray:" + modelData.title
                    return "tray:#" + index
                }
                // Chromium numbers tray icons per process, so two Electron apps
                // that set neither Title nor ToolTip (QQ and 飞连 both do) each
                // register the id "chrome_status_icon_1". A delegate's slot is
                // addressed purely by where its key sits in allKeys, so an
                // unqualified duplicate drew both icons into one slot: the lower
                // one hidden and unclickable, and the row one cell too narrow.
                // Qualify each repeat by how many earlier delegates already hold
                // the same base key. Only the siblings' baseTrayKey is read
                // here, never their trayKey, so this cannot close a binding loop.
                readonly property int duplicateOrdinal: {
                    const _rev = root.trayRevision
                    const liveCount = trayRepeater.count
                    if (!isValid)
                        return 0
                    let seen = 0
                    for (let i = 0; i < index && i < liveCount; i++) {
                        const other = trayRepeater.itemAt(i)
                        if (other && other.isValid && other.baseTrayKey === baseTrayKey)
                            seen++
                    }
                    return seen
                }
                readonly property string trayKey: !isValid ? ""
                    : duplicateOrdinal > 0
                        ? baseTrayKey + "#" + (duplicateOrdinal + 1)
                        : baseTrayKey
                readonly property bool inCollection: SysTrayOrderService.isCollected(trayKey)
                readonly property bool isDraggedItem: root.draggedKey !== ""
                    && root.draggedKey === trayKey

                Connections {
                    target: trayItem.modelData
                    function onIdChanged() { root.notifyTrayChanged() }
                    function onIconChanged() { root.notifyTrayChanged() }
                    function onTitleChanged() { root.notifyTrayChanged() }
                    function onTooltipTitleChanged() { root.notifyTrayChanged() }
                }
                Component.onCompleted: root.notifyTrayChanged()
                Component.onDestruction: {
                    root.notifyTrayChanged()
                    if (root.draggedKey === trayItem.trayKey) root.cancelDrag()
                    if (trayMenu.anchorItem === trayItem) {
                        // hide() alone is a no-op while a show is still
                        // pending (visible is already false), so release
                        // the opener state explicitly.
                        trayMenu.hide()
                        root.closeTrayMenuState()
                    }
                }

                parent: inCollection ? collectionPopup.grid : trayFlow
                readonly property point origin: root.delegateOrigin(trayKey, inCollection)
                x: origin.x; y: origin.y
                width: inCollection ? collectionPopup.layoutMetrics.cellSize : root.itemSize
                height: inCollection ? collectionPopup.layoutMetrics.cellSize : root.itemSize
                visible: isValid
                opacity: isDraggedItem && root.nativeDragStarted ? 0.25 : 1
                Behavior on x {
                    enabled: root.draggedKey !== "" && !trayItem.isDraggedItem
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: root.draggedKey !== "" && !trayItem.isDraggedItem
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.onDragFinished: function(action) { root.nativeDragFinished(trayItem.trayKey, action) }
                readonly property string tooltip: modelData ? SysTrayIdentityService.friendlyName(modelData) : ""

                function openMenu() {
                    if (!modelData.hasMenu)
                        return
                    root.openTrayMenu(trayItem)
                }

                function activatePrimary() {
                    if (modelData.onlyMenu)
                        openMenu()
                    else
                        modelData.activate()
                }

                SelectionHighlight {
                    objectName: "tray-item-selection-highlight"
                    anchors.fill: parent
                    cornerRadius: 6
                    enabled: AppearanceTokens.surface.selectionHighlightStyle === "glass" && !root.altModifierHeld
                    hovered: trayMouse.containsMouse
                    selected: trayMenu.visible && trayMenu.anchorItem === trayItem
                    pressed: trayMouse.pressed
                    dark: ThemeService.isDark
                    fillStrength: 0.75
                    z: -1
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    visible: AppearanceTokens.surface.selectionHighlightStyle !== "glass"
                        && (trayMouse.containsMouse || (trayMenu.visible && trayMenu.anchorItem === trayItem))
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
                    z: -1
                }

                TrayIcon {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.centerIn: parent
                    entry: trayItem.modelData
                    applicationId: trayItem.modelData.id || ""
                    applicationName: trayItem.tooltip
                    rotation: root.verticalDock && !trayItem.inCollection ? -90 : 0
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                        if ((mouse.modifiers & Qt.AltModifier) !== 0) return
                        if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate()
                            return
                        }
                        if (mouse.button === Qt.RightButton) {
                            trayItem.openMenu()
                            return
                        }
                        trayItem.activatePrimary()
                    }
                }

                DragHandler {
                    id: trayReorderDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.AltModifier
                    enabled: SysTrayOrderService.ready
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                        | PointerHandler.ApprovesCancellation
                    cursorShape: Qt.ClosedHandCursor
                    onCanceled: root.pointerDragEnded(trayItem.trayKey)
                    onActiveChanged: {
                        if (active) root.beginDrag(trayItem.trayKey, trayItem, trayReorderDrag)
                        else root.pointerDragEnded(trayItem.trayKey)
                    }
                }

                AnimatedPopupWindow {
                    id: trayTooltip
                    objectName: "systray-tooltip"
                    openDuration: 70
                    closeDuration: 70
                    mask: Region { item: null }
                    motionOrigin: !root.dockHosted ? Item.Top
                        : root.dockEdge === "left" ? Item.Left
                        : root.dockEdge === "right" ? Item.Right : Item.Bottom
                    requestedOpen: trayMouse.containsMouse && !trayMenu.visible && root.draggedKey === ""
                        && trayItem.tooltip.length > 0
                    implicitWidth: tooltipText.implicitWidth + 16
                    implicitHeight: tooltipText.implicitHeight + 10
                    color: "transparent"

                    anchor {
                        item: trayItem
                        edges: root.popupEdge
                        gravity: root.popupEdge
                        margins.top: root.dockHosted
                            && root.dockEdge === "bottom" ? -6 : 0
                        margins.bottom: root.dockHosted ? 0 : -6
                        margins.left: root.dockHosted
                            && root.dockEdge === "right" ? -6 : 0
                        margins.right: root.dockHosted
                            && root.dockEdge === "left" ? -6 : 0
                    }

                    BackgroundEffect.blurRegion: trayTooltip.visible && AppearanceTokens.surface.usesBackdrop
                        ? trayTooltipSurface.blurRegion : null

                    ControlCenterGlass {
                        id: trayTooltipSurface
                        anchors.fill: parent
                        radius: 6

                        Text {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: trayItem.tooltip + (SysTrayOrderService.isCollected(trayItem.trayKey)
                                ? " · " + I18n.tr("Alt-drag to the bar to keep visible") : "")
                            color: trayTooltipSurface.foregroundColor
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        Repeater {
            id: trailingRepeater
            model: root.trailingComponents || []

            delegate: Item {
                id: trailingItem
                required property var modelData
                required property int index
                readonly property alias loader: trailingLoader
                readonly property string trayKey: root.trailingCellKeys[index]
                    ?? ("cell:#" + index)
                readonly property bool inCollection: SysTrayOrderService.isCollected(trayKey)
                readonly property bool isDraggedItem: root.draggedKey !== ""
                    && root.draggedKey === trayKey
                parent: inCollection ? collectionPopup.grid : trayFlow
                readonly property point origin: root.delegateOrigin(trayKey, inCollection)
                x: origin.x; y: origin.y
                width: inCollection ? collectionPopup.layoutMetrics.cellSize : root.slotWidth(trayKey)
                height: inCollection ? collectionPopup.layoutMetrics.cellSize : root.itemSize
                opacity: isDraggedItem && root.nativeDragStarted ? 0.25 : 1
                Behavior on x {
                    enabled: root.draggedKey !== "" && !trailingItem.isDraggedItem
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Behavior on y {
                    enabled: root.draggedKey !== "" && !trailingItem.isDraggedItem
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.onDragFinished: function(action) { root.nativeDragFinished(trailingItem.trayKey, action) }

                Loader {
                    id: trailingLoader
                    anchors.fill: parent
                    sourceComponent: trailingItem.modelData
                }

                HoverHandler { id: collectedCellHover }
                StatusTooltip {
                    anchorItem: trailingItem
                    dockHosted: root.dockHosted
                    dockEdge: root.dockEdge
                    shown: root.altModifierHeld && SysTrayOrderService.isCollected(trailingItem.trayKey)
                        && collectedCellHover.hovered && !root.collectionKeepOpen && root.draggedKey === ""
                    primaryText: I18n.tr("Alt-drag to the bar to keep visible")
                }
                Component.onDestruction: {
                    if (root.draggedKey === trayKey) root.cancelDrag()
                }

                // Inspect the press itself; a stale hover-modifier snapshot
                // must never let a loaded control activate on Alt+drag.
                MouseArea {
                    anchors.fill: parent
                    enabled: trailingItem.trayKey !== "cell:controlcenter"
                    acceptedButtons: Qt.LeftButton
                    onPressed: function(mouse) {
                        mouse.accepted = (mouse.modifiers & Qt.AltModifier) !== 0
                    }
                }
                DragHandler {
                    id: trailingReorderDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    acceptedModifiers: Qt.AltModifier
                    enabled: SysTrayOrderService.ready && trailingItem.trayKey !== "cell:controlcenter"
                    grabPermissions: PointerHandler.CanTakeOverFromAnything
                        | PointerHandler.ApprovesCancellation
                    cursorShape: Qt.ClosedHandCursor
                    onCanceled: root.pointerDragEnded(trailingItem.trayKey)
                    onActiveChanged: {
                        if (active) root.beginDrag(trailingItem.trayKey, trailingItem, trailingReorderDrag)
                        else root.pointerDragEnded(trailingItem.trayKey)
                    }
                }
            }
        }
        StatusCollectionDropArea {
            anchors.fill: parent
            coordinator: root
            section: "strip"
            z: 100
        }
    }

    // ── Tray context menu ────────────────────────────────────────────
    // Self-drawn liquid-glass menu instead of QsMenuAnchor's native QMenu:
    // the native path creates its window before the Breeze style polish
    // applies WA_TranslucentBackground, so pixels outside the rounded
    // corners composite as opaque black (same class of bug as KDE 385311).
    // One ContextMenu is shared by every tray icon; a QsMenuOpener bridge
    // exposes the item's DBusMenu tree as rows.
    property var _traySubmenuOpeners: []
    property var _trayMenuEmptyModel: null
    property bool _trayMenuPendingShow: false
    property bool _rebuildingTrayMenu: false

    Component.onCompleted: root._trayMenuEmptyModel = trayMenuOpener.children

    QsMenuOpener {
        id: trayMenuOpener
        onMenuChanged: {
            // The owning StatusNotifierItem dropped its menu handle while
            // the popup was open (or closeTrayMenu released it).
            if (trayMenuOpener.menu === null && trayMenu.visible)
                trayMenu.hide()
        }
        onChildrenChanged: root.rebuildTrayMenu()
    }

    Connections {
        target: trayMenuOpener.children
        function onValuesChanged() { root.rebuildTrayMenu() }
    }

    Component {
        id: traySubmenuOpenerFactory
        QsMenuOpener {
            id: sub
            property Connections _watch: Connections {
                target: sub.children
                function onValuesChanged() { root.rebuildTrayMenu() }
            }
            // children-display can flip on an already-listed entry without
            // a structural change, so follow hasChildrenChanged too.
            property Connections _entryWatch: Connections {
                target: sub.menu
                function onHasChildrenChanged() { root.rebuildTrayMenu() }
            }
            onChildrenChanged: root.rebuildTrayMenu()
        }
    }

    Timer {
        id: trayMenuShowFallback
        interval: 400
        repeat: false
        // The DBusMenu layout normally arrives within a few ms; if it does
        // not, still map the popup so a slow app does not swallow the click.
        onTriggered: {
            if (!root._trayMenuPendingShow)
                return
            root._trayMenuPendingShow = false
            trayMenu.show()
        }
    }

    function openTrayMenu(anchor) {
        if (!anchor || !anchor.modelData || !anchor.modelData.hasMenu)
            return
        if (trayMenu.visible)
            trayMenu.hide()
        closeTrayMenuState()
        trayMenu.anchorItem = anchor
        root._trayMenuPendingShow = true
        trayMenuOpener.menu = anchor.modelData.menu
        if (trayMenuOpener.menu === null) {
            root._trayMenuPendingShow = false
            return
        }
        rebuildTrayMenu()
        trayMenuShowFallback.restart()
    }

    function closeTrayMenuState() {
        trayMenuShowFallback.stop()
        root._trayMenuPendingShow = false
        // Drop the delegates' entry references before the handles release
        // the DBusMenu tree and its entries are deleted.
        trayMenu.clear()
        for (const rec of root._traySubmenuOpeners)
            rec.opener.destroy()
        root._traySubmenuOpeners = []
        trayMenuOpener.menu = null
    }

    function _trayMenuValues(opener) {
        const values = opener.children ? opener.children.values : null
        const out = []
        if (!values)
            return out
        for (let i = 0; i < values.length; ++i)
            out.push(values[i])
        return out
    }

    // Submenu children are enumerated through a dedicated QsMenuOpener per
    // entry: setting its menu refs the entry, which is also what sends the
    // DBusMenu "opened" event to the owning application.
    function _traySubmenuOpenerFor(entry) {
        for (let i = 0; i < root._traySubmenuOpeners.length; ++i) {
            if (root._traySubmenuOpeners[i].entry === entry)
                return root._traySubmenuOpeners[i].opener
        }
        const opener = traySubmenuOpenerFactory.createObject(root, { menu: entry })
        root._traySubmenuOpeners.push({ entry: entry, opener: opener })
        return opener
    }

    function _trayMenuItemFor(entry) {
        const item = { entry: entry }
        if (entry.hasChildren) {
            const opener = _traySubmenuOpenerFor(entry)
            item.children = root._trayMenuValues(opener).map(root._trayMenuItemFor)
        }
        return item
    }

    function _sameEntryList(items, entries) {
        if (items.length !== entries.length)
            return false
        for (let i = 0; i < items.length; ++i)
            if (items[i].entry !== entries[i])
                return false
        return true
    }

    function rebuildTrayMenu() {
        if (root._rebuildingTrayMenu)
            return
        if (trayMenuOpener.menu === null)
            return
        root._rebuildingTrayMenu = true

        try {
            // Snapshot the current navigation so a live layout update
            // re-enters the same submenu instead of kicking the user back
            // to page one.
            const oldPages = trayMenu.page.parents.concat([trayMenu.page.items])
            const oldEntryLists = oldPages.map(list => (list || [])
                .map(item => item ? item.entry : null))

            const rootItems = root._trayMenuValues(trayMenuOpener)
                .map(root._trayMenuItemFor)

            // Release openers whose entry disappeared from the menu tree;
            // destroying the opener unrefs the entry and sends "closed".
            const used = []
            const collect = function(items) {
                for (const item of items) {
                    if (item.entry)
                        used.push(item.entry)
                    if (item.children)
                        collect(item.children)
                }
            }
            collect(rootItems)
            root._traySubmenuOpeners = root._traySubmenuOpeners.filter(rec => {
                if (used.indexOf(rec.entry) >= 0)
                    return true
                rec.opener.destroy()
                return false
            })

            let level = rootItems
            const parents = []
            for (let k = 1; k < oldEntryLists.length; ++k) {
                const wanted = oldEntryLists[k]
                const parentItem = level.find(item => item.children
                    && root._sameEntryList(item.children, wanted))
                if (!parentItem)
                    break
                parents.push(level)
                level = parentItem.children
            }

            trayMenu.rootItems = rootItems
            trayMenu.page = ({ items: level, parents: parents })
        } finally {
            root._rebuildingTrayMenu = false
        }

        // children is the shared empty ObjectModel until the menu's first
        // layout arrives; a different object means the tree is loaded.
        if (root._trayMenuPendingShow
                && trayMenuOpener.children !== root._trayMenuEmptyModel) {
            root._trayMenuPendingShow = false
            trayMenuShowFallback.stop()
            trayMenu.show()
        }
    }

    ContextMenu {
        id: trayMenu
        scrimLevel: AppearanceTokens.bar.popupScrimLevel
        customAnchorEdges: root.popupEdge
        customGravity: root.popupEdge
        customMargins: ({
            top: root.popupEdge === Edges.Top ? -4 : 0,
            bottom: root.popupEdge === Edges.Bottom ? -4 : 0,
            left: root.popupEdge === Edges.Left ? -4 : 0,
            right: root.popupEdge === Edges.Right ? -4 : 0
        })
        baseColor: ThemeService.backgroundColor
        foregroundColor: ThemeService.foregroundColor
        onAction: function(cmd, item) {
            if (item && item.entry)
                item.entry.triggered()
        }
        onAboutToHide: root.closeTrayMenuState()
    }

    function trailingItem(index) {
        const wrapper = trailingRepeater.itemAt(index)
        return wrapper?.loader?.item ?? null
    }

    // Looks a trailing cell up by its stable key instead of its rendered
    // position. The StatusArea's panels anchor to these cells, and a hidden
    // cell shifts every later index, so an index-based lookup would silently
    // anchor a panel to the wrong icon once visibility is configurable.
    function trailingItemForKey(key) {
        const index = root.trailingKeys.indexOf(String(key))
        return index >= 0 ? trailingItem(index) : null
    }
}
