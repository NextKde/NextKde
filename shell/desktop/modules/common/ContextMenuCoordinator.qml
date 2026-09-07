pragma Singleton

import QtQuick

// All self-drawn context menus are independent PopupWindows. Keep one shared
// owner so a menu from the Dock, desktop, or launcher cannot remain mapped at
// a stale anchor while another surface opens.
QtObject {
    id: coordinator

    property var activeMenu: null
    // KWin's no-reply D-Bus delivery can arrive after the same right click has
    // opened a new menu. Retain the open time so that old input events cannot
    // immediately dismiss that newly opened menu.
    property double activeMenuOpenedAt: 0

    function open(menu) {
        if (!menu)
            return
        if (activeMenu === menu) {
            menu.visible = true
            return
        }

        const previous = activeMenu
        activeMenu = menu
        activeMenuOpenedAt = Date.now()
        if (previous && previous.visible) {
            if (typeof previous.hide === "function")
                previous.hide()
            else
                previous.visible = false
        }
        menu.visible = true
    }

    function release(menu) {
        if (activeMenu === menu) {
            activeMenu = null
            activeMenuOpenedAt = 0
        }
    }

    // Native Qt menus need the active Wayland popup to be unmapped before
    // they calculate their anchor position.
    function closeActive() {
        const menu = activeMenu
        activeMenu = null
        activeMenuOpenedAt = 0

        if (menu && menu.visible) {
            if (typeof menu.hide === "function")
                menu.hide()
            else
                menu.visible = false
        }
    }

    property Connections lifecycleConnections: Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable)
                coordinator.closeActive()
        }
    }

    // The KWin effect has already excluded presses routed to popup surfaces,
    // so every event delivered here is an outside press. Do not compare QML
    // PopupWindow coordinates: they are anchor-local rather than compositor
    // global coordinates.
    function dismissForGlobalPointerPress(x, y, timestamp) {
        const menu = activeMenu
        if (!menu || !menu.visible)
            return
        if (!menu.dismissOnGlobalPointerPress)
            return

        const eventTimestamp = Number(timestamp)
        if (Number.isFinite(eventTimestamp)
                && eventTimestamp <= activeMenuOpenedAt)
            return
        const grace = Number(menu.globalDismissGraceMs || 0)
        if (Number.isFinite(grace) && Date.now() < activeMenuOpenedAt + grace)
            return
        console.info("[ContextMenu] dismissed by global press")
        closeActive()
    }
}
