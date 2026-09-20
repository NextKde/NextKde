import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects
import qs.desktop.modules.common
import qs.desktop.modules.dock

// StatusNotifierItem host. Referencing SystemTray claims and tracks tray items.
Item {
    id: root

    property int iconSize: 18
    property int iconSpacing: 6
    // Visual-only adjustment; transforms preserve the item's input region
    // and the menu anchor follows the transformed icon position.
    property int visualYOffset: 0
    property bool dockHosted: false
    property string dockEdge: "bottom"
    property bool verticalDock: false
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
            if (keys.indexOf(item.trayKey) < 0)
                keys.push(item.trayKey)
        }
        return keys
    }
    readonly property var trailingCellKeys: (root.trailingKeys || []).map(key => "cell:" + key)
    readonly property var allKeys: root.nativeKeys.concat(root.trailingCellKeys)
    readonly property var arrangedKeys: SysTrayOrderService.arrange(root.allKeys)

    readonly property int itemCount: root.allKeys.length
    readonly property int twoRowThreshold: itemSize * 2
    readonly property bool twoRows: dockHosted && itemCount > 1
        && availableHeight >= twoRowThreshold
    readonly property int rowCount: twoRows ? 2 : 1
    readonly property real singleRowImplicitWidth: itemCount > 0
        ? itemCount * itemSize + (itemCount - 1) * iconSpacing : 0

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

    function targetIndexFor(key) {
        const arranged = root.arrangedKeys.indexOf(key)
        if (arranged >= 0)
            return arranged
        return root.allKeys.indexOf(key)
    }

    // Alt is the drag modifier (mirroring the desktop convention this shell
    // already uses elsewhere for a deliberate, unlikely-to-misfire hold).
    // Tracked via HoverHandler.point.modifiers, the only reactive way to
    // read a live modifier state in QML without a native event filter.
    HoverHandler {
        id: modifierTracker
    }
    readonly property bool altModifierHeld:
        (modifierTracker.point.modifiers & Qt.AltModifier) !== 0

    property string draggedKey: ""
    property real dragTranslationX: 0
    property real dragTranslationY: 0

    function slotOrigin(flowIndex) {
        if (flowIndex < 0)
            return Qt.point(0, 0)
        const rows = Math.max(1, root.rowCount)
        const column = Math.floor(flowIndex / rows)
        const row = flowIndex % rows
        return Qt.point(column * (root.itemSize + root.iconSpacing), row * root.itemSize)
    }
    function slotCenter(flowIndex) {
        const origin = root.slotOrigin(flowIndex)
        return Qt.point(origin.x + root.itemSize / 2, origin.y + root.itemSize / 2)
    }
    // The visual (Translate) delta from a delegate's fixed declaration slot
    // to wherever it should currently appear.
    function reorderOffsetFor(naturalIndex, displayIndex) {
        const from = root.slotOrigin(naturalIndex)
        const to = root.slotOrigin(displayIndex)
        return Qt.point(to.x - from.x, to.y - from.y)
    }

    // Nearest slot to the dragged item's current pointer-followed centre.
    // Purely arithmetic (no querying of other delegates' actual geometry),
    // since every slot's centre is already a deterministic function of its
    // arranged index.
    readonly property int dragInsertIndex: {
        if (root.draggedKey === "")
            return -1
        const sourceIndex = root.targetIndexFor(root.draggedKey)
        const sourceCenter = root.slotCenter(sourceIndex)
        const pointerCenter = Qt.point(sourceCenter.x + root.dragTranslationX,
                                       sourceCenter.y + root.dragTranslationY)
        let nearest = sourceIndex
        let nearestDistance = Number.POSITIVE_INFINITY
        const count = root.allKeys.length
        for (let i = 0; i < count; i++) {
            const center = root.slotCenter(i)
            const dx = pointerCenter.x - center.x
            const dy = pointerCenter.y - center.y
            const distance = dx * dx + dy * dy
            if (distance < nearestDistance) {
                nearestDistance = distance
                nearest = i
            }
        }
        return nearest
    }

    readonly property int columnCount: itemCount > 0
        ? Math.ceil(itemCount / Math.max(1, rowCount)) : 0
    implicitWidth: itemCount > 0
        ? columnCount * itemSize + (columnCount - 1) * iconSpacing : 0
    implicitHeight: itemCount > 0 ? rowCount * itemSize : 0
    width: implicitWidth
    height: implicitHeight
    transform: Translate { y: root.visualYOffset }

    Item {
        id: trayFlow
        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitHeight

        Repeater {
            id: trayRepeater
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property var modelData
                required property int index

                readonly property bool isValid: Boolean(modelData && (modelData.icon || modelData.id || modelData.title))
                readonly property string trayKey: {
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
                readonly property int naturalIndex: isValid ? root.allKeys.indexOf(trayKey) : -1
                readonly property int targetIndex: isValid ? root.targetIndexFor(trayKey) : -1
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
                    if (trayMenu.anchorItem === trayItem) {
                        // hide() alone is a no-op while a show is still
                        // pending (visible is already false), so release
                        // the opener state explicitly.
                        trayMenu.hide()
                        root.closeTrayMenuState()
                    }
                }

                // Shift by exactly one slot when another item's live drag
                // insertion point is passing over this item's resting slot.
                readonly property int reorderSlots: {
                    if (!isValid || isDraggedItem || root.draggedKey === "" || root.dragInsertIndex < 0)
                        return 0
                    const source = root.targetIndexFor(root.draggedKey)
                    const destination = root.dragInsertIndex
                    if (destination < source && targetIndex >= destination && targetIndex < source)
                        return 1
                    if (destination > source && targetIndex <= destination && targetIndex > source)
                        return -1
                    return 0
                }
                // The drag translation is relative to where the item was
                // actually sitting when it was grabbed — its arranged slot,
                // not its declaration slot — so the resting offset stays
                // applied while dragging (reorderSlots is already 0 here).
                // Dropping it would teleport any item whose arranged slot
                // differs from its natural one, leaving the icon trailing
                // the cursor by exactly that gap.
                readonly property point reorderOffset: isValid
                    ? root.reorderOffsetFor(naturalIndex, targetIndex + reorderSlots)
                    : Qt.point(0, 0)
                property real offsetX: reorderOffset.x + (isDraggedItem ? root.dragTranslationX : 0)
                property real offsetY: reorderOffset.y + (isDraggedItem ? root.dragTranslationY : 0)
                Behavior on offsetX {
                    enabled: !trayItem.isDraggedItem
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on offsetY {
                    enabled: !trayItem.isDraggedItem
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                transform: Translate { x: trayItem.offsetX; y: trayItem.offsetY }
                z: isDraggedItem ? 10 : 0
                scale: isDraggedItem ? 1.08 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                visible: isValid
                x: root.slotOrigin(naturalIndex).x
                y: root.slotOrigin(naturalIndex).y
                width: isValid ? root.itemSize : 0
                height: isValid ? root.itemSize : 0
                readonly property string tooltip: modelData ? (modelData.tooltipTitle
                    || modelData.title || modelData.id || "") : ""
                readonly property bool isSymbolicMask: Boolean(modelData?.isMask)
                    || (typeof modelData?.icon === "string" && (
                        modelData.icon.indexOf("symbolic") !== -1
                        || modelData.icon.indexOf("-mask") !== -1
                    ))

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

                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
                    visible: trayMouse.containsMouse
                        || (trayMenu.visible && trayMenu.anchorItem === trayItem)
                }

                AppIcon {
                    width: root.iconSize
                    height: root.iconSize
                    anchors.centerIn: parent
                    source: trayItem.modelData.icon
                    opacityMultiplier: IconAppearanceService.mode !== "color"
                        ? IconAppearanceService.opacity : 1.0
                    saturation: IconAppearanceService.saturation
                    tintEnabled: IconAppearanceService.tintEnabled
                    tintColor: IconAppearanceService.tintColor
                    rotation: root.verticalDock ? -90 : 0
                    layer.enabled: trayItem.isSymbolicMask && IconAppearanceService.mode === "color"
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: ThemeService.foregroundColor
                    }
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    enabled: !root.altModifierHeld
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
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
                    enabled: root.altModifierHeld
                    xAxis.enabled: true
                    yAxis.enabled: root.rowCount > 1
                    onActiveChanged: {
                        if (active) {
                            root.draggedKey = trayItem.trayKey
                            root.dragTranslationX = 0
                            root.dragTranslationY = 0
                            return
                        }
                        if (root.draggedKey !== trayItem.trayKey)
                            return
                        const destination = root.dragInsertIndex
                        root.draggedKey = ""
                        if (destination >= 0 && destination !== trayItem.targetIndex)
                            SysTrayOrderService.moveKey(trayItem.trayKey, destination, root.allKeys)
                    }
                    onTranslationChanged: {
                        if (!active)
                            return
                        root.dragTranslationX = translation.x
                        root.dragTranslationY = translation.y
                    }
                }

                PopupWindow {
                    id: trayTooltip
                    visible: trayMouse.containsMouse && !trayMenu.visible
                        && trayItem.tooltip.length > 0
                    implicitWidth: tooltipText.implicitWidth + 16
                    implicitHeight: tooltipText.implicitHeight + 10
                    color: "transparent"

                    Connections {
                        target: ScreenLifecycle
                        function onOutputAvailableChanged() {
                            if (!ScreenLifecycle.outputAvailable)
                                trayTooltip.visible = false
                        }
                    }
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

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Qt.rgba(0.18, 0.18, 0.20, 0.95)

                        Text {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: trayItem.tooltip
                            color: "white"
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
                readonly property int naturalIndex: root.allKeys.indexOf(trayKey)
                readonly property int targetIndex: root.targetIndexFor(trayKey)
                readonly property bool isDraggedItem: root.draggedKey !== ""
                    && root.draggedKey === trayKey
                readonly property int reorderSlots: {
                    if (isDraggedItem || root.draggedKey === "" || root.dragInsertIndex < 0)
                        return 0
                    const source = root.targetIndexFor(root.draggedKey)
                    const destination = root.dragInsertIndex
                    if (destination < source && targetIndex >= destination && targetIndex < source)
                        return 1
                    if (destination > source && targetIndex <= destination && targetIndex > source)
                        return -1
                    return 0
                }
                // The drag translation is relative to where the item was
                // actually sitting when it was grabbed — its arranged slot,
                // not its declaration slot — so the resting offset stays
                // applied while dragging (reorderSlots is already 0 here).
                // Dropping it would teleport any item whose arranged slot
                // differs from its natural one, leaving the icon trailing
                // the cursor by exactly that gap.
                readonly property point reorderOffset:
                    root.reorderOffsetFor(naturalIndex, targetIndex + reorderSlots)
                property real offsetX: reorderOffset.x + (isDraggedItem ? root.dragTranslationX : 0)
                property real offsetY: reorderOffset.y + (isDraggedItem ? root.dragTranslationY : 0)
                Behavior on offsetX {
                    enabled: !trailingItem.isDraggedItem
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on offsetY {
                    enabled: !trailingItem.isDraggedItem
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                transform: Translate { x: trailingItem.offsetX; y: trailingItem.offsetY }
                z: isDraggedItem ? 10 : 0
                scale: isDraggedItem ? 1.08 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                x: root.slotOrigin(naturalIndex).x
                y: root.slotOrigin(naturalIndex).y
                width: root.itemSize
                height: root.itemSize

                Loader {
                    id: trailingLoader
                    anchors.fill: parent
                    sourceComponent: trailingItem.modelData
                }

                // Swallows input while a reorder is possible so the loaded
                // control's own click (opening its panel, toggling Wi-Fi...)
                // cannot also fire from the same press that starts a drag.
                MouseArea {
                    anchors.fill: parent
                    visible: root.altModifierHeld
                    cursorShape: Qt.SizeAllCursor
                }

                DragHandler {
                    id: trailingReorderDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    enabled: root.altModifierHeld
                    xAxis.enabled: true
                    yAxis.enabled: root.rowCount > 1
                    onActiveChanged: {
                        if (active) {
                            root.draggedKey = trailingItem.trayKey
                            root.dragTranslationX = 0
                            root.dragTranslationY = 0
                            return
                        }
                        if (root.draggedKey !== trailingItem.trayKey)
                            return
                        const destination = root.dragInsertIndex
                        root.draggedKey = ""
                        if (destination >= 0 && destination !== trailingItem.targetIndex)
                            SysTrayOrderService.moveKey(trailingItem.trayKey, destination, root.allKeys)
                    }
                    onTranslationChanged: {
                        if (!active)
                            return
                        root.dragTranslationX = translation.x
                        root.dragTranslationY = translation.y
                    }
                }
            }
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
}
