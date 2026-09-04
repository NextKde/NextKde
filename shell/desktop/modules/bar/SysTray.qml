import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
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
    // UntypedObjectModel intentionally has no length/get API; Repeater.count
    // is the supported reactive item count for layout calculations.
    readonly property int itemCount: trayRepeater.count
        + (trailingComponents ? trailingComponents.length : 0)
    readonly property int twoRowThreshold: itemSize * 2
    readonly property bool twoRows: dockHosted && itemCount > 1
        && availableHeight >= twoRowThreshold
    readonly property int rowCount: twoRows ? 2 : 1
    readonly property real singleRowImplicitWidth: itemCount > 0
        ? itemCount * itemSize + (itemCount - 1) * iconSpacing : 0

    // ═══════════════════════════════════════════════════════════════
    // Alt+drag reorder
    //
    // Native tray items and the trailing shell cells come from two
    // different, differently-owned models (SystemTray.items has no array
    // API to resort; trailingComponents is a fixed literal). Rather than
    // merging them into one sorted model, every delegate keeps its natural
    // declaration-order slot for layout purposes and a persisted, purely
    // visual `transform: Translate` offset carries it to its preferred
    // slot — at rest as much as while another item is being dragged past
    // it. Only the actively dragged item ever changes its own base slot,
    // and only on release, once the reorder is committed.
    // ═══════════════════════════════════════════════════════════════

    // Native tray items have no stable index of their own outside the
    // Repeater; a fallback slot key keeps a still-unresolved item from
    // breaking the key list rather than crashing on a missing id.
    readonly property var nativeKeys: {
        const keys = []
        for (let i = 0; i < trayRepeater.count; i++) {
            const item = trayRepeater.itemAt(i)
            const id = item?.modelData?.id
            keys.push("tray:" + (id && id.length > 0 ? id : ("#" + i)))
        }
        return keys
    }
    readonly property var trailingCellKeys: (root.trailingKeys || []).map(key => "cell:" + key)
    readonly property var allKeys: root.nativeKeys.concat(root.trailingCellKeys)
    readonly property var arrangedKeys: SysTrayOrderService.arrange(root.allKeys)

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
                readonly property string trayKey: root.nativeKeys[index] ?? ("tray:#" + index)
                readonly property int naturalIndex: index
                readonly property int targetIndex: root.targetIndexFor(trayKey)
                readonly property bool isDraggedItem: root.draggedKey !== ""
                    && root.draggedKey === trayKey
                // Shift by exactly one slot when another item's live drag
                // insertion point is passing over this item's resting slot.
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
                readonly property point reorderOffset: isDraggedItem
                    ? Qt.point(0, 0)
                    : root.reorderOffsetFor(naturalIndex, targetIndex + reorderSlots)
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

                x: root.slotOrigin(naturalIndex).x
                y: root.slotOrigin(naturalIndex).y
                width: root.itemSize
                height: root.itemSize
                readonly property string tooltip: modelData.tooltipTitle
                    || modelData.title || modelData.id
                readonly property bool isSymbolicMask: Boolean(modelData.isMask)
                    || (typeof modelData.icon === "string" && (
                        modelData.icon.indexOf("symbolic") !== -1
                        || modelData.icon.indexOf("-mask") !== -1
                    ))

                function openMenu() {
                    if (!modelData.hasMenu)
                        return

                    // QsMenuAnchor owns a native Qt menu. Release any
                    // self-drawn desktop popup first, then let it finish
                    // unmapping before Qt calculates this menu's anchor.
                    ContextMenuCoordinator.closeActive()
                    Qt.callLater(function() {
                        if (trayItem.modelData && trayItem.modelData.hasMenu)
                            trayMenu.open()
                    })
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
                    visible: trayMouse.containsMouse || trayMenu.visible
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

                QsMenuAnchor {
                    id: trayMenu
                    menu: trayItem.modelData.menu
                    anchor {
                        item: trayItem
                        edges: root.popupEdge
                        gravity: root.popupEdge
                        margins.top: root.dockHosted
                            && root.dockEdge === "bottom" ? -4 : 0
                        margins.bottom: root.dockHosted ? 0 : -4
                        margins.left: root.dockHosted
                            && root.dockEdge === "right" ? -4 : 0
                        margins.right: root.dockHosted
                            && root.dockEdge === "left" ? -4 : 0
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
                readonly property int naturalIndex: trayRepeater.count + index
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
                readonly property point reorderOffset: isDraggedItem
                    ? Qt.point(0, 0)
                    : root.reorderOffsetFor(naturalIndex, targetIndex + reorderSlots)
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

    function trailingItem(index) {
        const wrapper = trailingRepeater.itemAt(index)
        return wrapper?.loader?.item ?? null
    }
}
