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
    property bool macosPopupMotion: true
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
    property real menuRadius: AppearanceTokens.surface.pick(AppearanceTokens.shape.large, 16)
    readonly property color effectiveForegroundColor: {
        if (!root.adaptiveForeground)
            return root.foregroundColor
        return (AppearanceTokens.surface.paintInQml || ThemeService.isDark)
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
    readonly property var displayedPage: pageMotion.displayedPage || root.page

    PageMotion {
        id: pageMotion
        page: root.page
        enabled: root.visible && (!root.macosPopupMotion || popupMotion.requestedOpen)
    }

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
            root.show()
        else
            root.hide()
    }
    function dismissDockPopupImmediately() { root.visible = false }

    // Column.implicitHeight does not include these dynamically repeated rows
    // reliably in this PopupWindow, so derive the surface height from the same
    // menu data that drives the Repeater.
    readonly property real menuContentHeight: {
        const items = root.displayedPage.items || []
        let total = 0
        let visibleRows = 0
        function addRow(height) {
            if (visibleRows > 0)
                total += 2
            total += height
            visibleRows++
        }
        if (root.displayedPage.parents.length > 0)
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

    // Vertical clamp. Without it a menu with many entries asked for a surface
    // taller than the output, and PopupAdjustment.Slide/Flip cannot move a
    // window that does not fit anywhere -- both ends simply ran off screen.
    // The list below scrolls instead, capped at a fraction of the output so a
    // long menu never has to reach the very bottom edge to start scrolling.
    // 0.8 is a deliberate breathing margin, not an accident: the menu tops out
    // at 80% of the screen height on every output.
    readonly property real menuHeightFraction: 0.8
    readonly property real menuMinHeight: 160
    // Per-caller override, e.g. a menu that must stay clear of another surface.
    // Zero means "use the screen fraction".
    property real menuMaxHeightOverride: 0
    // Declarative on purpose. An imperative measurement pass used to rewrite
    // this from the screen height, which silently won over the fraction and
    // made the cap depend on which value happened to be smaller.
    readonly property var menuScreen: root.screen
        || (root.anchorItem ? root.anchorItem.window?.screen : null)
    readonly property real menuMaxHeight: {
        if (root.menuMaxHeightOverride > 0)
            return root.menuMaxHeightOverride
        const screenHeight = root.menuScreen?.height || 0
        // The 1000 fallback only covers the frame before the popup is mapped to
        // an output; it is never the steady-state cap.
        return Math.max(root.menuMinHeight, Math.round(
            (screenHeight > 0 ? screenHeight : 1000)
                * root.menuHeightFraction))
    }
    readonly property real menuSurfaceHeight: Math.min(root.menuContentHeight,
        root.menuMaxHeight)

    implicitWidth: 240
    implicitHeight: root.menuSurfaceHeight + 12
    color: "transparent"
    grabFocus: !root.macosPopupMotion || popupMotion.interactive
    mask: root.macosPopupMotion && !popupMotion.interactive ? emptyInputRegion : null
    Region { id: emptyInputRegion }

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
            pageMotion.reset(root.page)
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

    // Both forms publish this. A tonal menu wants the same backdrop frost a
    // glass one does, and gets it without a SurfaceShape -- so there is nothing
    // to exclude here.
    BackgroundEffect.blurRegion: root.visible && glass.opacity > 0 ? glass.blurRegion : null

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
        opacity: (root.macosPopupMotion ? popupMotion.progress : 1) * pageMotion.progress
        enabled: (!root.macosPopupMotion || popupMotion.interactive) && pageMotion.interactive
        transform: Translate {
            y: (root.macosPopupMotion && popupMotion.progress < 0.999)
                ? Math.round((1 - popupMotion.progress) * AppearanceTokens.motion.popupAnchorOffset)
                : 0
        }

        // Viewport for the menu rows. It never grows past root.menuSurfaceHeight,
        // so the surface stays on the output; anything beyond that scrolls.
        // Non-interactive while the list fits, which keeps the pre-scroll
        // click-through behaviour for short menus untouched.
        Flickable {
            id: view
            x: 6
            y: 6
            width: parent.width - 12
            height: root.menuSurfaceHeight
            contentWidth: width
            // Same hand-computed source as the surface height above, for the
            // reason given on menuContentHeight: Column.implicitHeight is not
            // reliable for these dynamically repeated rows in a PopupWindow.
            // Mixing the two sources desynchronised viewport and content.
            contentHeight: root.menuContentHeight
            // The rows keep their own hover and click handling; this view only
            // adds wheel scrolling and a drag gesture it does not have to win.
            interactive: view.overflowing
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 2400
            maximumFlickVelocity: 2600
            clip: true

            readonly property bool overflowing: contentHeight > height + 1

            Column {
                id: list
                // Fills the viewport width; its implicitHeight is the whole
                // menu, so the window still opens at the natural size when the
                // list is short.
                width: view.width
                spacing: 2

                MenuItemRow {
                    width: parent.width
                    visible: root.displayedPage.parents.length > 0
                    icon: "back"
                    label: "返回"
                    foregroundColor: root.effectiveForegroundColor
                    onClicked: root.back()
                }

                Repeater {
                    id: menuRepeater
                    model: root.displayedPage.items
                    delegate: MenuItemRow {
                        required property int index
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

            // The menu is one column of rows: give its wheel the same glide the
            // rest of the shell has. interactive:false (a menu that fits) disables
            // this with it.
            KosKineticScroll { flickable: view }
        }

        // A new page always starts at its first row; without this a menu opened
        // after a deep submenu page kept the previous page's scroll offset.
        Connections {
            target: root
            function onPageChanged() {
                view.contentY = 0
                view.returnToBounds()
            }
        }

        // Minimal scroll affordance, drawn over the glass at the trailing edge.
        // It never takes pointer input (no MouseArea, and the Flickable above
        // still receives the wheel), it only shows that rows continue.
        Rectangle {
            id: scrollIndicator
            readonly property real trackTop: 12
            readonly property real trackHeight: Math.max(0, view.height - 24)
            readonly property real thumbHeight: Math.max(24,
                trackHeight * (view.height / Math.max(1, view.contentHeight)))
            x: 6 + view.width - 10
            y: 6 + trackTop + (trackHeight - thumbHeight)
                * (view.contentY / Math.max(1, view.contentHeight - view.height))
            width: 4
            height: thumbHeight
            radius: 2
            visible: view.overflowing
            color: Qt.rgba(root.effectiveForegroundColor.r,
                root.effectiveForegroundColor.g,
                root.effectiveForegroundColor.b, 0.32)
        }
    }
}
