import Quickshell
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Effects
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"
import "StatusCollection.mjs" as StatusCollection

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
    readonly property string collectionKey: StatusCollection.toggleKey
    property bool collectionExpanded: false
    property bool collectionKeepOpen: false
    signal collectionCollapseRequested()
    readonly property var collectedKeys: root.orderedKeys.filter(key => SysTrayOrderService.isCollected(key))
    readonly property var pinnedKeys: root.orderedKeys.filter(key => !SysTrayOrderService.isCollected(key))
    // Keep every delegate alive; folding changes positions and visibility only.
    readonly property var arrangedKeys: StatusCollection.visibleKeys(root.orderedKeys,
        SysTrayOrderService.collectedKeys, root.collectionExpanded, !root.dockHosted)
    readonly property var previewKeys: StatusCollection.previewOrder(root.arrangedKeys,
        root.draggedKey, root.dragInsertIndex)

    readonly property int itemCount: root.arrangedKeys.length
    readonly property int twoRowThreshold: itemSize * 2
    readonly property bool twoRows: dockHosted && itemCount > 1
        && availableHeight >= twoRowThreshold
    readonly property int rowCount: twoRows ? 2 : 1
    readonly property real singleRowImplicitWidth: {
        if (root.itemCount <= 0)
            return 0
        let width = 0
        for (let i = 0; i < root.arrangedKeys.length; i++)
            width += root.slotWidth(root.arrangedKeys[i])
        return width + (root.itemCount - 1) * root.iconSpacing
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

    function targetIndexFor(key) {
        const arranged = root.arrangedKeys.indexOf(key)
        if (arranged >= 0)
            return arranged
        return -1
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
    property point dragStartScene: Qt.point(0, 0)
    property bool dragCancelled: false
    readonly property point dragCenter: {
        // Expanding changes the right-anchored strip's width and scene origin.
        const geometry = root.width + root.x
        return root.mapFromItem(null, root.dragStartScene.x + root.dragTranslationX,
            root.dragStartScene.y + root.dragTranslationY)
    }

    function beginDrag(key, item) {
        root.dragCancelled = false
        root.dragStartScene = item.mapToItem(null, item.width / 2, item.height / 2)
        root.dragTranslationX = 0
        root.dragTranslationY = 0
        root.draggedKey = key
        if (!root.dockHosted) root.forceActiveFocus()
    }

    property string pendingDropKey: ""
    Timer {
        id: finishDragTimer
        interval: 0
        onTriggered: {
            const key = root.pendingDropKey
            root.pendingDropKey = ""
            root.finishDrag(key)
        }
    }
    function scheduleDrop(key) {
        root.pendingDropKey = key
        finishDragTimer.restart()
    }
    function cancelDrag() {
        finishDragTimer.stop()
        root.pendingDropKey = ""
        root.dragCancelled = true
        root.draggedKey = ""
    }

    function finishDrag(key) {
        if (root.draggedKey !== key) return
        const destination = root.dragInsertIndex
        const preview = root.previewKeys.slice()
        const target = StatusCollection.destinationSection(preview, key)
        if (!root.dragCancelled && destination >= 0) {
            if (!root.dockHosted) SysTrayOrderService.setCollected(key, target.collected)
            SysTrayOrderService.moveKey(key, target.keys.indexOf(key), target.keys)
        }
        root.draggedKey = ""
        root.dragTranslationX = 0
        root.dragTranslationY = 0
        if (root.dragCancelled) root.collectionExpanded = false
    }

    function toggleCollection() {
        if (root.collectionExpanded) {
            root.collectionCollapseRequested()
            trayMenu.hide()
            root.collectionExpanded = false
        } else {
            root.collectionExpanded = true
            root.forceActiveFocus()
        }
    }

    function closeCollectionOutside(x, y) {
        const point = root.mapFromItem(null, x, y)
        if (!root.contains(point)) root.closeCollection()
    }

    function closeCollection() {
        if (root.draggedKey !== "" || root.collectionKeepOpen || trayMenu.visible)
            return
        root.collectionExpanded = false
    }

    Shortcut {
        sequence: "Escape"
        enabled: (root.collectionExpanded || root.draggedKey !== "")
            && !root.collectionKeepOpen && !trayMenu.visible
        onActivated: {
            root.cancelDrag()
            root.collectionExpanded = false
        }
    }
    HoverHandler { id: collectionHover }
    // No fullscreen input catcher: leaving the strip folds it after a short
    // grace period. Native menus and shell panels retain their live anchors.
    Timer {
        interval: 650
        running: root.collectionExpanded && !collectionHover.hovered
            && root.draggedKey === "" && !root.collectionKeepOpen && !trayMenu.visible
        onTriggered: root.closeCollection()
    }
    Timer {
        interval: 220
        running: !root.dockHosted && !root.collectionExpanded && root.draggedKey !== ""
            && root.dragInsertIndex === root.arrangedKeys.indexOf(root.collectionKey)
        onTriggered: root.collectionExpanded = true
    }

    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            if (WindowService.activeWindowId) root.closeCollection()
        }
    }
    Connections {
        target: ContextMenuCoordinator
        function onActiveMenuChanged() {
            if (ContextMenuCoordinator.activeMenu && !trayMenu.visible)
                root.closeCollection()
        }
    }

    function slotOriginIn(keys, flowIndex) {
        if (flowIndex < 0)
            return Qt.point(0, 0)
        const rows = Math.max(1, root.rowCount)
        const row = flowIndex % rows
        if (rows === 1) {
            // Variable cell widths: a shell cell may request overflow beyond
            // its itemSize square (the network cell hosts the traffic
            // readout), so positions accumulate real slot widths instead of
            // assuming a uniform grid.
            let x = 0
            for (let i = 0; i < flowIndex && i < keys.length; i++)
                x += root.slotWidth(keys[i]) + root.iconSpacing
            return Qt.point(x, 0)
        }
        const column = Math.floor(flowIndex / rows)
        return Qt.point(column * (root.itemSize + root.iconSpacing), row * root.itemSize)
    }

    function slotOrigin(flowIndex) {
        return root.slotOriginIn(root.arrangedKeys, flowIndex)
    }

    function slotCenter(flowIndex) {
        const origin = root.slotOrigin(flowIndex)
        const key = root.arrangedKeys[flowIndex] ?? ""
        return Qt.point(origin.x + root.slotWidth(key) / 2, origin.y + root.itemSize / 2)
    }
    // The visual (Translate) delta from a delegate's fixed declaration slot
    // to wherever it should currently appear.
    function reorderOffsetFor(naturalIndex, key) {
        const from = root.slotOriginIn(root.allKeys, naturalIndex)
        if (key === root.draggedKey) {
            const center = root.dragCenter
            return Qt.point(center.x - root.slotWidth(key) / 2 - from.x,
                center.y - root.itemSize / 2 - from.y)
        }
        const to = root.slotOriginIn(root.previewKeys, root.previewKeys.indexOf(key))
        return Qt.point(to.x - from.x, to.y - from.y)
    }

    readonly property int dragInsertIndex: {
        if (root.draggedKey === "" || root.dragCancelled) return -1
        const center = root.dragCenter
        if (center.x < -root.itemSize / 2 || center.x > root.implicitWidth + root.itemSize / 2
            || center.y < -root.itemSize / 2 || center.y > root.implicitHeight + root.itemSize / 2)
            return -1
        const source = root.arrangedKeys.indexOf(root.draggedKey)
        const boundary = root.arrangedKeys.indexOf(root.collectionKey)
        // Hovering the disclosure is itself a collection target, even if the
        // nearest midpoint belongs to the adjacent icon.
        if (!root.dockHosted) {
            const origin = root.slotOrigin(boundary)
            if (center.x >= origin.x && center.x <= origin.x + root.itemSize)
                return source > boundary ? boundary : Math.max(0, boundary - 1)
        }
        let nearest = source
        let distance = Number.POSITIVE_INFINITY
        for (let i = 0; i < root.arrangedKeys.length; i++) {
            const point = root.slotCenter(i)
            const d = (point.x - center.x) ** 2 + (point.y - center.y) ** 2
            if (d < distance) { nearest = i; distance = d }
        }
        return nearest
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
            visible: !root.dockHosted
            enabled: SysTrayOrderService.ready
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: root.collectionExpanded ? I18n.tr("Collapse collected icons") : I18n.tr("Show collected icons")
            Accessible.onPressAction: root.toggleCollection()
            Keys.onSpacePressed: root.toggleCollection()
            Keys.onReturnPressed: root.toggleCollection()
            readonly property point origin: root.slotOriginIn(root.previewKeys,
                root.previewKeys.indexOf(root.collectionKey))
            x: origin.x; y: origin.y
            width: root.itemSize; height: root.itemSize
            radius: 6
            readonly property bool dropTarget: root.draggedKey !== "" && root.dragInsertIndex >= 0
                && root.previewKeys.indexOf(root.draggedKey) < root.previewKeys.indexOf(root.collectionKey)
            color: dropTarget ? Qt.rgba(0.1, 0.5, 1, 0.22)
                : toggleMouse.containsMouse ? Qt.rgba(ThemeService.barInk.r, ThemeService.barInk.g, ThemeService.barInk.b, 0.10)
                : "transparent"
            border.width: dropTarget ? 1 : 0
            border.color: AppearanceTokens.colors.primary
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            BundledIcon {
                anchors.centerIn: parent
                name: root.collectionExpanded ? "submenu" : "back"
                size: 12
                color: ThemeService.barInk
                opacity: root.collectedKeys.length > 0 || toggleMouse.containsMouse || root.draggedKey !== "" ? 0.9 : 0.5
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
            StatusTooltip {
                anchorItem: collectionToggle
                shown: toggleMouse.containsMouse && root.draggedKey === ""
                primaryText: root.collectionExpanded ? I18n.tr("Collapse collected icons") : I18n.tr("Show collected icons")
                secondaryText: root.collectedKeys.length === 0
                    ? I18n.tr("Alt-drag icons here to collect; drag along the bar to reorder")
                    : I18n.tr("Click to expand · Alt-drag icons to reorder or collect")
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
                    if (root.draggedKey === trayItem.trayKey) root.cancelDrag()
                    if (trayMenu.anchorItem === trayItem) {
                        // hide() alone is a no-op while a show is still
                        // pending (visible is already false), so release
                        // the opener state explicitly.
                        trayMenu.hide()
                        root.closeTrayMenuState()
                    }
                }

                readonly property point reorderOffset: isValid
                    ? root.reorderOffsetFor(naturalIndex, trayKey) : Qt.point(0, 0)
                property real offsetX: reorderOffset.x
                property real offsetY: reorderOffset.y
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

                visible: isValid && targetIndex >= 0
                x: root.slotOriginIn(root.allKeys, naturalIndex).x
                y: root.slotOriginIn(root.allKeys, naturalIndex).y
                width: isValid ? root.itemSize : 0
                height: isValid ? root.itemSize : 0
                readonly property string tooltip: modelData ? SysTrayIdentityService.friendlyName(modelData) : ""
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
                    enabled: SysTrayOrderService.ready && (root.altModifierHeld || active)
                    xAxis.enabled: true
                    yAxis.enabled: !root.dockHosted || root.rowCount > 1
                    onCanceled: root.cancelDrag()
                    onActiveChanged: {
                        if (active) root.beginDrag(trayItem.trayKey, trayItem)
                        else root.scheduleDrop(trayItem.trayKey)
                    }
                    onTranslationChanged: {
                        if (!active || root.draggedKey === "")
                            return
                        root.dragTranslationX = translation.x
                        root.dragTranslationY = translation.y
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

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Qt.rgba(0.18, 0.18, 0.20, 0.95)

                        Text {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: trayItem.tooltip + (!root.dockHosted && SysTrayOrderService.isCollected(trayItem.trayKey)
                                ? " · " + I18n.tr("Alt-drag to the bar to keep visible") : "")
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
                readonly property point reorderOffset: root.reorderOffsetFor(naturalIndex, trayKey)
                property real offsetX: reorderOffset.x
                property real offsetY: reorderOffset.y
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

                visible: targetIndex >= 0
                x: root.slotOriginIn(root.allKeys, naturalIndex).x
                y: root.slotOriginIn(root.allKeys, naturalIndex).y
                width: root.slotWidth(trayKey)
                height: root.itemSize

                Loader {
                    id: trailingLoader
                    anchors.fill: parent
                    sourceComponent: trailingItem.modelData
                }

                HoverHandler { id: collectedCellHover }
                StatusTooltip {
                    anchorItem: trailingItem
                    shown: root.altModifierHeld && !root.dockHosted && SysTrayOrderService.isCollected(trailingItem.trayKey)
                        && collectedCellHover.hovered && !root.collectionKeepOpen && root.draggedKey === ""
                    primaryText: I18n.tr("Alt-drag to the bar to keep visible")
                }
                Component.onDestruction: {
                    if (root.draggedKey === trayKey) root.cancelDrag()
                }

                // Swallows input while a reorder is possible so the loaded
                // control's own click (opening its panel, toggling Wi-Fi...)
                // cannot also fire from the same press that starts a drag.
                MouseArea {
                    anchors.fill: parent
                    visible: root.altModifierHeld && trailingItem.trayKey !== "cell:controlcenter"
                    cursorShape: Qt.SizeAllCursor
                }

                DragHandler {
                    id: trailingReorderDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    enabled: SysTrayOrderService.ready && trailingItem.trayKey !== "cell:controlcenter" && (root.altModifierHeld || active)
                    xAxis.enabled: true
                    yAxis.enabled: !root.dockHosted || root.rowCount > 1
                    onCanceled: root.cancelDrag()
                    onActiveChanged: {
                        if (active) root.beginDrag(trailingItem.trayKey, trailingItem)
                        else root.scheduleDrop(trailingItem.trayKey)
                    }
                    onTranslationChanged: {
                        if (!active || root.draggedKey === "")
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

    // Looks a trailing cell up by its stable key instead of its rendered
    // position. The StatusArea's panels anchor to these cells, and a hidden
    // cell shifts every later index, so an index-based lookup would silently
    // anchor a panel to the wrong icon once visibility is configurable.
    function trailingItemForKey(key) {
        const index = root.trailingKeys.indexOf(String(key))
        return index >= 0 ? trailingItem(index) : null
    }
}
