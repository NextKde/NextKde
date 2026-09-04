import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common

// Shared self-drawn context menu. Submenus deliberately reuse this one popup
// as a page stack: only a click enters a child page, and hover is visual only.
PopupWindow {
    id: root

    property Item anchorItem: null
    property string position: "bottom"
    property bool placeBelow: false
    property color baseColor: Qt.rgba(0, 0, 0, 0.55)
    property color foregroundColor: "#ffffff"
    property bool adaptiveForeground: true
    property color ambientPrimary: "transparent"
    property color ambientSecondary: "transparent"
    property real ambientStrength: 0.0
    // Context menus need more separation from a busy desktop than the Dock.
    // Compositor blur is declared below; these QML layers make it read as a
    // denser, slightly darker frosted surface on every shared context menu.
    property real surfaceOpacity: 0.98
    property real darkOverlayOpacity: 0.27
    property real menuRadius: 16

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
    function show() { ContextMenuCoordinator.open(root) }
    function hide() { root.visible = false }
    function setDockPopupVisible(shouldOpen) {
        if (shouldOpen)
            ContextMenuCoordinator.open(root)
        else
            root.visible = false
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
            if (item?.separator)
                addRow(1)
            else if ((item?.label || "").length > 0)
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
        edges: root.position === "bottom"
            ? (root.placeBelow ? (Edges.Top | Edges.Left) : Edges.Top)
            : Edges.Right
        gravity: root.position === "bottom"
            ? (root.placeBelow ? (Edges.Bottom | Edges.Right) : Edges.Top)
            : Edges.Right
        adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
        margins.top: root.position === "bottom" ? -8 : 0
        margins.right: root.position === "right" ? -8 : 8
        margins.left: root.position === "left" ? 8 : 0
    }

    onVisibleChanged: {
        if (root.visible) {
            // Support the few callers that set visible directly as well as
            // the normal show()/setDockPopupVisible() entry points.
            if (ContextMenuCoordinator.activeMenu !== root)
                ContextMenuCoordinator.open(root)
            root.page = ({ items: root.rootItems, parents: [] })
            root.aboutToShow()
        } else {
            ContextMenuCoordinator.release(root)
            root.aboutToHide()
        }
    }

    signal aboutToShow()
    signal aboutToHide()

    BackgroundEffect.blurRegion: root.visible ? contextMenuBlurHolder : null

    Region {
        id: contextMenuBlurHolder
        RoundedBlurRegion {
            item: glass
            radius: root.menuRadius
        }
    }

    LiquidGlassSurface {
        id: glass
        anchors.fill: parent
        radius: root.menuRadius
        baseColor: root.baseColor
        ambientPrimary: root.ambientPrimary
        ambientSecondary: root.ambientSecondary
        ambientStrength: root.ambientStrength
        surfaceOpacity: root.surfaceOpacity
        materialDepth: 0.6
        material: "thick"
        adaptiveDarkScrim: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, root.darkOverlayOpacity)
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
                icon: "←"
                label: "返回"
                foregroundColor: root.adaptiveForeground ? glass.foregroundColor : root.foregroundColor
                onClicked: root.back()
            }

            Repeater {
                id: menuRepeater
                model: root.page.items
                delegate: MenuItemRow {
                    required property var modelData
                    readonly property var submenuItems: root.childrenFor(modelData)
                    width: parent.width
                    foregroundColor: root.adaptiveForeground ? glass.foregroundColor : root.foregroundColor
                    icon: modelData.icon || ""
                    label: modelData.label || ""
                    separator: !!modelData.separator
                    hasSubmenu: submenuItems.length > 0
                    checkable: !!modelData.checkable
                    checked: !!modelData.checked
                    itemEnabled: modelData.enabled !== false
                    onClicked: {
                        if (submenuItems.length > 0)
                            root.enter(submenuItems)
                        else {
                            root.action(modelData.cmd, modelData)
                            root.hide()
                        }
                    }
                }
            }
        }
    }
}
