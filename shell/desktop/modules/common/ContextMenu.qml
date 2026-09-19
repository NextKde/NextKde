import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../Kos/Ui"

// Shared self-drawn context menu. Submenus deliberately reuse this one popup
// as a page stack: only a click enters a child page, and hover is visual only.
PopupWindow {
    id: root

    property Item anchorItem: null
    property string position: "bottom"
    property bool placeBelow: false
    // Global AppMenu uses the same macOS motion as Control Center and anchors
    // the popup to the clicked item's horizontal centre.
    property bool macosPopupMotion: false
    property bool centerBelowAnchor: false
    property real centerBelowOffset: 0
    property var customAnchorEdges: null
    property var customGravity: null
    property var customMarginsTop: null
    // Full margin override ({top, bottom, left, right}) for anchors that
    // open in a direction the `position` shorthand cannot express, e.g.
    // tray popups attached to a side dock.
    property var customMargins: null
    property color baseColor: ThemeService.backgroundColor
    property color foregroundColor: ThemeService.foregroundColor
    property bool adaptiveForeground: true
    property color ambientPrimary: WallpaperColorSource.primary
    property color ambientSecondary: WallpaperColorSource.secondary
    property real ambientStrength: 0.25 * AppearanceTokens.glass.ambientMultiplier
    // Context menus need more separation from a busy desktop than the Dock.
    // Compositor blur is declared below; these QML layers make it read as a
    // denser, slightly darker frosted surface on every shared context menu.
    property real surfaceOpacity: 0.98
    property real menuRadius: AppearanceTokens.isMaterial
        ? AppearanceTokens.shape.large : 16
    readonly property color effectiveForegroundColor: {
        if (!root.adaptiveForeground)
            return root.foregroundColor
        return (AppearanceTokens.isMaterial || ThemeService.isDark)
            ? glass.foregroundColor : ThemeService.foregroundColor
    }
    // Some anchors receive their opening press through the compositor's
    // global-pointer bridge slightly after this popup is mapped.
    property int globalDismissGraceMs: 0
    // Set by popup types whose compositor surface is not reported as a KWin
    // popup window. Their own controls still close the menu after an action.
    property bool dismissOnGlobalPointerPress: true

    signal action(string cmd, var item)

    property var rootItems: []
    // One atomic navigation snapshot. Keeping items and parents in separate
    // properties caused two consecutive PopupWindow relayouts per click:
    // first the back row appeared over the old page, then the page changed.
    property var page: ({ items: [], parents: [] })
    readonly property bool atRoot: root.page.parents.length === 0

    function setItems(items) {
        root.rootItems = items || []
        root.page = ({ items: root.rootItems, parents: [] })
    }
    function clear() { root.setItems([]) }
    function addItem(icon, label, cmd, enabled) {
        root.rootItems = root.rootItems.concat([{
            icon: icon || "", label: label || "", cmd: cmd || "",
            enabled: enabled !== false
        }])
        root.page = ({ items: root.rootItems, parents: [] })
    }

    // QML Repeaters can expose an array in a QJSValue wrapper. Normalize it
    // once so the chevron and click route always agree on whether children
    // exist and on the exact child list to show.
    function childrenFor(item) {
        const children = item ? item.children : null
        if (!children)
            return []
        if (Array.isArray(children))
            return children.slice()
        const count = Number(children.length)
        if (!Number.isFinite(count) || count <= 0)
            return []
        const result = []
        for (let i = 0; i < count; ++i)
            result.push(children[i])
        return result
    }
    function enter(children) {
        root.page = ({
            items: children,
            parents: root.page.parents.concat([root.page.items])
        })
    }
    function back() {
        const parents = root.page.parents
        if (parents.length === 0)
            return
        root.page = ({
            items: parents[parents.length - 1],
            parents: parents.slice(0, -1)
        })
    }
    function show() {
        ContextMenuCoordinator.open(root)
        if (root.macosPopupMotion)
            popupMotion.open()
    }
    function hide() {
        if (root.macosPopupMotion && root.visible) {
            popupMotion.close()
            return
        }
        root.visible = false
    }
    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen)
            ContextMenuCoordinator.open(root)
        else
            root.hide()
    }
    function dismissDockPopupImmediately() { root.visible = false }

    // Column.implicitHeight does not include these dynamically repeated rows
    // reliably in this PopupWindow, so derive the surface height from the same
    // menu data that drives the Repeater.
    readonly property real menuContentHeight: {
        const items = root.page.items || []
        let total = 0
        let visibleRows = 0
        function addRow(height) {
            if (visibleRows > 0)
                total += 2
            total += height
            visibleRows++
        }
        if (root.page.parents.length > 0)
            addRow(38)
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            // Items may carry a live QsMenuEntry handle; read through it so
            // height follows in-place property updates (e.g. separators).
            const entry = item?.entry ?? null
            const isSeparator = entry ? entry.isSeparator : !!item?.separator
            const label = entry ? (entry.text || "") : (item?.label || "")
            if (isSeparator)
                addRow(1)
            else if (label.length > 0)
                addRow(38)
        }
        return total
    }

    implicitWidth: 240
    implicitHeight: root.menuContentHeight + 12
    color: "transparent"
    grabFocus: true

    anchor {
        item: root.anchorItem
        rect.x: root.centerBelowAnchor && root.anchorItem
            ? root.anchorItem.width / 2 - root.implicitWidth / 2 : 0
        rect.y: (root.centerBelowAnchor || root.centerBelowOffset > 0) ? root.centerBelowOffset : 0
        rect.width: root.centerBelowAnchor ? root.implicitWidth : (root.anchorItem ? root.anchorItem.width : 0)
        rect.height: (root.centerBelowAnchor || root.centerBelowOffset > 0) ? 1 : (root.anchorItem ? root.anchorItem.height : 0)
        edges: root.customAnchorEdges !== null ? root.customAnchorEdges : (root.centerBelowAnchor ? (Edges.Top | Edges.Left)
            : root.position === "bottom"
            ? (root.placeBelow ? (Edges.Top | Edges.Left) : Edges.Top)
            : Edges.Right)
        gravity: root.customGravity !== null ? root.customGravity : (root.centerBelowAnchor ? (Edges.Bottom | Edges.Right)
            : root.position === "bottom"
            ? (root.placeBelow ? (Edges.Bottom | Edges.Right) : Edges.Top)
            : Edges.Right)
        adjustment: root.centerBelowAnchor ? PopupAdjustment.Slide
            : (PopupAdjustment.Flip | PopupAdjustment.Slide)
        margins.top: root.customMargins !== null ? (root.customMargins.top ?? 0)
            : (root.customMarginsTop !== null ? root.customMarginsTop : (root.centerBelowAnchor ? 0
            : (root.position === "bottom" ? -8 : 0)))
        margins.bottom: root.customMargins !== null ? (root.customMargins.bottom ?? 0) : 0
        margins.right: root.customMargins !== null ? (root.customMargins.right ?? 0)
            : (root.position === "right" ? -8 : 8)
        margins.left: root.customMargins !== null ? (root.customMargins.left ?? 0)
            : (root.position === "left" ? 8 : 0)
    }

    onVisibleChanged: {
        if (root.visible) {
            // Support the few callers that set visible directly as well as
            // the normal show()/setDockPopupVisible() entry points.
            if (!root.macosPopupMotion)
                ContextMenuCoordinator.open(root)
            root.page = ({ items: root.rootItems, parents: [] })
            root.aboutToShow()
            if (root.macosPopupMotion && !popupMotion.mapped)
                popupMotion.open()
        } else {
            if (root.macosPopupMotion)
                popupMotion.reset()
            ContextMenuCoordinator.release(root)
            root.aboutToHide()
        }
    }

    signal aboutToShow()
    signal aboutToHide()

    PopupMotion {
        id: popupMotion
        onClosed: {
            if (!popupMotion.requestedOpen)
                root.visible = false
        }
    }

    BackgroundEffect.blurRegion: (!AppearanceTokens.isMaterial && root.visible)
        ? glass.blurRegion : null

    LiquidGlassPanel {
        id: glass
        anchors.fill: parent
        radius: root.menuRadius
        cornerExponent: AppearanceTokens.shape.cornerExponent
        baseColor: root.baseColor
        ambientPrimary: root.ambientPrimary
        ambientSecondary: root.ambientSecondary
        ambientStrength: root.ambientStrength
        surfaceOpacity: root.surfaceOpacity
        // Menu text sits on this surface, so it carries the same balanced
        // readability scrim as notification cards.
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: "balanced"
        scale: (root.macosPopupMotion && popupMotion.progress < 0.999)
            ? AppearanceTokens.motion.popupStartScale
                + (1 - AppearanceTokens.motion.popupStartScale) * popupMotion.progress
            : 1
        transformOrigin: Item.Top
        opacity: root.macosPopupMotion ? popupMotion.progress : 1
        enabled: !root.macosPopupMotion || popupMotion.interactive
        transform: Translate {
            y: (root.macosPopupMotion && popupMotion.progress < 0.999)
                ? Math.round((1 - popupMotion.progress) * AppearanceTokens.motion.popupAnchorOffset)
                : 0
        }

        Column {
            id: list
            // Do not fill the PopupWindow: the window derives its height from
            // this Column's implicitHeight. Anchoring both dimensions formed a
            // size loop that left every child page at the previous page height.
            x: 6
            y: 6
            width: parent.width - 12
            height: root.menuContentHeight
            spacing: 2

            MenuItemRow {
                width: parent.width
                visible: root.page.parents.length > 0
                icon: "back"
                label: "返回"
                foregroundColor: root.effectiveForegroundColor
                onClicked: root.back()
            }

            Repeater {
                id: menuRepeater
                model: root.page.items
                delegate: MenuItemRow {
                    required property var modelData
                    // Items may carry a live QsMenuEntry (DBusMenu tray
                    // menus). Binding through it keeps label/icon/check
                    // state current while the menu is open.
                    readonly property var entry: modelData.entry ?? null
                    readonly property var submenuItems: root.childrenFor(modelData)
                    width: parent.width
                    foregroundColor: root.effectiveForegroundColor
                    icon: modelData.icon || ""
                    iconSource: entry ? (entry.icon || "") : (modelData.iconSource || "")
                    label: entry ? (entry.text || "") : (modelData.label || "")
                    separator: entry ? entry.isSeparator : !!modelData.separator
                    hasSubmenu: submenuItems.length > 0
                    checkable: entry ? (entry.buttonType !== QsMenuButtonType.None)
                        : !!modelData.checkable
                    checked: entry ? (entry.checkState !== Qt.Unchecked)
                        : !!modelData.checked
                    itemEnabled: entry ? entry.enabled : modelData.enabled !== false
                    onClicked: {
                        if (submenuItems.length > 0)
                            root.enter(submenuItems)
                        else {
                            root.action(modelData.cmd || "", modelData)
                            root.hide()
                        }
                    }
                }
            }
        }
    }
}
