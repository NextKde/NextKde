pragma Singleton
import QtQuick
import qs.desktop.modules.common

// DockModelService — compatibility facade for the current Dock UI.
//
// AppIdentityService owns application identity resolution.
// WindowService owns the live Wayland Toplevel model and window actions.
// AppGroupService owns reusable app/window grouping.
// This facade only derives the current Dock presentation and keeps the old
// DockContainer bindings stable while future UIs consume the lower layers.

QtObject {
    id: svc

    // Fired when a non-fullscreen window becomes urgent (§5.8) so the dock
    // controller can do its 2200ms temporary reveal. Detected in the window
    // rebuild by comparing the urgent set against the previous rebuild.
    signal urgentWindowAppeared()

    property variant _lastUrgentIds: []
    property bool _urgentInitDone: false

    property var pinnedItems: []
    property int pinnedCount: 0
    // Presentation-only task list. WindowService keeps every live window;
    // this layer derives the Dock's ordered per-window presentation while
    // other shell surfaces can consume the unmodified live model.
    property ListModel windowModel: ListModel {}
    readonly property int windowCount: windowModel.count

    // DockIcon instances own their PopupWindows, but the Dock presents only
    // one context menu at a time.
    property var activeContextMenu: null
    // Every temporary Dock surface (context menu or preview) goes
    // through this coordinator. PopupWindows are independent Wayland surfaces;
    // without one shared owner, two anchors can remain open and fight over
    // placement and pointer focus.
    property var activeDockPopup: null
    // Some Dock popups (the context menu) need to keep their Wayland surface
    // alive briefly for an exit animation. Other popup types can still use the
    // native `visible` property directly through this shared gateway.
    function setDockPopupVisible(popup, shouldOpen) {
        if (!popup)
            return
        if (typeof popup.setDockPopupVisible === "function")
            popup.setDockPopupVisible(shouldOpen)
        else
            popup.visible = shouldOpen
    }

    // Replacing one anchored popup with another must not leave the old surface
    // animating at a stale anchor. The replacement gets the next frame to map
    // its own icon, which prevents the screen-edge flash during rapid right
    // clicks across Dock items.
    function dismissDockPopupImmediately(popup) {
        if (!popup)
            return
        if (typeof popup.dismissDockPopupImmediately === "function")
            popup.dismissDockPopupImmediately()
        else
            popup.visible = false
    }

    function openDockPopup(popup) {
        if (!popup)
            return;
        if (svc.activeDockPopup && svc.activeDockPopup !== popup)
            svc.dismissDockPopupImmediately(svc.activeDockPopup);
        svc.activeDockPopup = popup;
        svc.setDockPopupVisible(popup, true);
    }

    function releaseDockPopup(popup) {
        if (svc.activeDockPopup === popup)
            svc.activeDockPopup = null;
    }

    property Connections lifecycleConnections: Connections {
        target: ScreenLifecycle
        function onOutputAvailableChanged() {
            if (!ScreenLifecycle.outputAvailable) {
                const popup = svc.activeDockPopup
                svc.activeDockPopup = null
                svc.dismissDockPopupImmediately(popup)
            }
        }
    }

    function _refreshPinned() {
        const isGrouped = ConfigService.windowGrouping === "grouped";
        const dockItems = ConfigService.dockItems || [];
        const items = [];
        for (let i = 0; i < dockItems.length; i++) {
            const dockItem = dockItems[i];

            if (dockItem.type === "app") {
                const identity = AppIdentityService.resolve(dockItem.appId);
                const windows = WindowService.windowsForApp(identity.desktopId);
                // In separate mode: a running pinned application is represented by its live
                // window tasks in the right-hand section.
                // In grouped mode: pinned apps stay in place with running dot & window count.
                if (!isGrouped && windows.length > 0)
                    continue;
                items.push({
                    type: "app",
                    appId: identity.desktopId,
                    desktopId: identity.desktopId,
                    name: identity.name || dockItem.appId,
                    icon: windows[0]?.iconSource ?? identity.iconSource,
                    isRunning: windows.length > 0,
                    isActivated: windows.some(window => window.toplevel.activated),
                    windowCount: windows.length,
                });
                continue;
            }

        }
        // Only replace the model when its content actually changed. The array
        // is the Repeater's model; assigning a new array rebuilds every pinned
        // delegate, and _refreshPinned runs on every window revision (every
        // window open/close), so an unchanged list must not churn the Repeater.
        const same = items.length === svc.pinnedItems.length
            && items.every((item, i) => {
                const prev = svc.pinnedItems[i];
                return prev && item.appId === prev.appId
                    && item.name === prev.name
                    && item.icon === prev.icon
                    && item.isRunning === prev.isRunning
                    && item.isActivated === prev.isActivated
                    && item.windowCount === prev.windowCount;
            });
        if (!same) {
            svc.pinnedItems = items;
            svc.pinnedCount = items.length;
        }
    }

    function _refreshWindowItems() {
        const isGrouped = ConfigService.windowGrouping === "grouped";
        const records = WindowService.records || [];
        const nextItems = [];
        // §5.8: only non-fullscreen urgents trigger the temporary dock reveal;
        // a fullscreen video/game must not have the full dock forced over it.
        const nowUrgent = [];

        if (isGrouped) {
            // Grouped mode: Aggregate unpinned windows by canonical desktopId
            const unpinnedGroups = {};
            const groupOrder = [];

            for (let i = 0; i < records.length; i++) {
                const record = records[i];
                if (!!record.isUrgent && !record.toplevel.fullscreen)
                    nowUrgent.push(record.windowId);

                const desktopId = record.identity.desktopId;
                if (svc.isAppPinned(desktopId))
                    continue; // Pinned apps are rendered in the pinned section

                if (!unpinnedGroups[desktopId]) {
                    unpinnedGroups[desktopId] = {
                        desktopId: desktopId,
                        appId: desktopId,
                        rawAppId: record.identity.rawAppId,
                        title: record.identity.name || record.title,
                        icon: record.iconSource ?? record.identity.iconSource,
                        isActivated: false,
                        isMinimized: true,
                        isUrgent: false,
                        isFullscreen: false,
                        pid: Number(record.pid || 0),
                        isWindowItem: false,
                        windowId: record.windowId,
                        effectWindowId: record.provider === "kwin"
                            ? String(record.handleId ?? "") : "",
                        windowCount: 0,
                    };
                    groupOrder.push(desktopId);
                }
                const group = unpinnedGroups[desktopId];
                group.windowCount++;
                if (record.toplevel.activated)
                    group.isActivated = true;
                if (!record.toplevel.minimized)
                    group.isMinimized = false;
                if (record.isUrgent)
                    group.isUrgent = true;
                if (record.toplevel.fullscreen)
                    group.isFullscreen = true;
            }

            for (let i = 0; i < groupOrder.length; i++) {
                nextItems.push(unpinnedGroups[groupOrder[i]]);
            }
        } else {
            // Separate mode (legacy flat list)
            for (let i = 0; i < records.length; i++) {
                const record = records[i];
                if (!!record.isUrgent && !record.toplevel.fullscreen)
                    nowUrgent.push(record.windowId);
                nextItems.push({
                    windowId: record.windowId,
                    // The animation effect must address the compositor window,
                    // not WindowService's provider-neutral synthetic id.
                    effectWindowId: record.provider === "kwin"
                        ? String(record.handleId ?? "") : "",
                    desktopId: record.identity.desktopId,
                    appId: record.identity.desktopId,
                    rawAppId: record.identity.rawAppId,
                    title: record.title,
                    icon: record.iconSource ?? record.identity.iconSource,
                    isActivated: !!record.toplevel.activated,
                    isMinimized: !!record.toplevel.minimized,
                    isUrgent: !!record.isUrgent,
                    isFullscreen: !!record.toplevel.fullscreen,
                    pid: Number(record.pid || 0),
                    isWindowItem: true,
                    windowCount: 1,
                });
            }
            nextItems.sort((left, right) => left.pid - right.pid
                           || left.windowId.localeCompare(right.windowId));
        }

        // Detect false->true urgent transitions since the last rebuild. The
        // first rebuild seeds the baseline so a window that was already urgent
        // before the dock appeared does not cause a spurious reveal.
        if (svc._urgentInitDone) {
            const wasUrgent = svc._lastUrgentIds;
            for (let i = 0; i < nowUrgent.length; i++) {
                if (wasUrgent.indexOf(nowUrgent[i]) === -1)
                    svc.urgentWindowAppeared();
            }
        }
        svc._lastUrgentIds = nowUrgent;
        svc._urgentInitDone = true;

        svc._setWindowItems(nextItems);
    }

    function _setWindowItems(nextItems) {
        // Reordering ListModel rows while its Repeater delegates are alive can
        // leave Qt Quick trying to stack items whose parents are already being
        // replaced. Grouped mode changes representative window IDs frequently,
        // so update rows in place and rely on DockIcon's synchronous decode to
        // avoid an empty first texture.
        while (svc.windowModel.count > nextItems.length)
            svc.windowModel.remove(svc.windowModel.count - 1);

        for (let i = 0; i < nextItems.length; i++) {
            const item = nextItems[i];
            if (i >= svc.windowModel.count) {
                svc.windowModel.append(item);
                continue;
            }

            const row = svc.windowModel.get(i);
            const keys = Object.keys(item);
            for (let j = 0; j < keys.length; j++) {
                const key = keys[j];
                if (row[key] !== item[key])
                    svc.windowModel.setProperty(i, key, item[key]);
            }
        }
    }

    function _refreshPresentation() {
        _refreshPinned();
        _refreshWindowItems();
    }

    property Connections _windowConnections: Connections {
        target: WindowService
        function onRevisionChanged() {
            svc._refreshPresentation();
        }
    }

    property Connections _configConnections: Connections {
        target: ConfigService
        function onDockItemsChanged() {
            svc._refreshPresentation();
        }
        function onPinnedAppIdsChanged() {
            svc._refreshPresentation();
        }
        function onWindowGroupingChanged() {
            svc._refreshPresentation();
        }
    }

    property Connections _identityConnections: Connections {
        target: AppIdentityService
        function onRevisionChanged() {
            svc._refreshPresentation();
        }
    }

    function activateApp(appId) {
        const identity = AppIdentityService.resolve(appId);
        const windows = WindowService.windowsForApp(identity.desktopId);

        if (windows.length === 0) {
            console.log("[DockModel] launch app=" + identity.desktopId);
            // KWin must receive the Dock launch ticket before the client can
            // map its first window. Otherwise the real window may be painted
            // once and only then jump back to the Dock animation origin.
            DockWindowAnimationTargetService.prepareLaunch(identity, function() {
                AppActionService.launch(identity);
            });
            return;
        }

        if (windows.length === 1) {
            const singleWin = windows[0];
            if (singleWin.toplevel.activated && !singleWin.toplevel.minimized) {
                console.log("[DockModel] minimize single window app=" + identity.desktopId);
                WindowService.minimizeWindow(singleWin.windowId, true);
            } else {
                console.log("[DockModel] activate single window app=" + identity.desktopId);
                activateWindow(singleWin.windowId);
            }
            return;
        }

        // Multiple windows (macOS logic):
        // Find if any window of this app is currently activated
        let activeIdx = -1;
        for (let i = 0; i < windows.length; i++) {
            if (windows[i].toplevel.activated) {
                activeIdx = i;
                break;
            }
        }

        if (activeIdx === -1) {
            // App not currently in foreground: activate MRU window
            console.log("[DockModel] activate app MRU window=" + windows[0].windowId);
            activateWindow(windows[0].windowId);
        } else {
            // App already active: cycle to next window in group
            const nextIdx = (activeIdx + 1) % windows.length;
            console.log("[DockModel] cycle app window from=" + windows[activeIdx].windowId
                        + " to=" + windows[nextIdx].windowId);
            activateWindow(windows[nextIdx].windowId);
        }
    }

    function launchNewWindow(appId) {
        if (!appId) {
            console.warn("[DockModel] launchNewWindow: empty appId");
            return;
        }
        const identity = AppIdentityService.resolve(appId);
        console.log("[DockModel] launch new window instance app=" + identity.desktopId
                    + " hasEntry=" + !!identity.entry);
        if (identity.entry) {
            AppActionService.launch(identity);
            return;
        }
        // Fallback: search catalog for matching desktop entry
        const catalog = AppPresentationService.catalog();
        for (let i = 0; i < catalog.length; i++) {
            const item = catalog[i];
            if (AppIdentityService.sameApp(item.desktopId, appId)
                    || AppIdentityService.sameApp(item.rawAppId, appId)) {
                if (item.entry) {
                    AppActionService.launch(item);
                    return;
                }
            }
        }
        AppActionService.launch(identity);
    }

    function activateWindow(windowId) {
        // WindowService remains the sole authority for the actual Wayland
        // activation request.
        WindowService.activateWindow(windowId);
    }

    // Dock task icons are toggles: a background/minimized window is brought
    // forward, while the currently focused window is minimized. Keep this
    // separate from activateWindow() because preview clicks and context-menu
    // "activate" actions must always bring a window forward, never minimize.
    function toggleWindow(windowId) {
        const record = WindowService.windowById(windowId);
        if (!record) {
            console.warn("[DockModel] toggle missing windowId=" + windowId);
            return;
        }
        if (record.toplevel.activated && !record.toplevel.minimized) {
            console.log("[DockModel] minimize window=" + windowId);
            WindowService.minimizeWindow(windowId, true);
        } else {
            console.log("[DockModel] activate window=" + windowId);
            activateWindow(windowId);
        }
    }

    function minimizeWindow(windowId) {
        WindowService.minimizeWindow(windowId, true);
    }

    function closeWindow(windowId) {
        WindowService.closeWindow(windowId);
    }

    function pinApp(appId) {
        const identity = AppIdentityService.resolve(appId);
        if (!ConfigService.addAppItem(identity.desktopId))
            return;
        console.log("[DockModel] pin app=" + identity.desktopId
                    + " items=" + JSON.stringify(ConfigService.dockItems));
        svc._refreshPresentation();
    }

    // Pin membership is defined by persisted Dock data. Compare canonical
    // identities rather than raw app IDs because a
    // live Wayland window and its .desktop entry can use different aliases.
    function isAppPinned(appId) {
        const wanted = AppIdentityService.canonicalId(appId);
        const pinnedIds = ConfigService.pinnedAppIds || [];
        for (let i = 0; i < pinnedIds.length; i++) {
            if (AppIdentityService.sameApp(pinnedIds[i], wanted))
                return true;
        }
        return false;
    }

    function unpinApp(appId) {
        const wanted = AppIdentityService.canonicalId(appId);
        if (!ConfigService.removeAppItem(wanted))
            return;
        console.log("[DockModel] unpin app=" + wanted
                    + " items=" + JSON.stringify(ConfigService.dockItems));
        svc._refreshPresentation();
    }

    // Drag slots are indices into the *visible* pinned list, which hides
    // pinned apps that currently have windows (they show as window tasks in
    // the right-hand section instead). Persisted order lives in the full
    // ConfigService.dockItems list, so a visible slot must be translated to
    // the full-list index of the item occupying it; otherwise every drop
    // lands in the wrong place while any pinned app is running. Inserting at
    // the target's full index is correct in both directions because
    // moveDockItem splices after removing the source.
    function _visibleSlotToDockIndex(type, visibleIndex) {
        const visible = svc.pinnedItems
        const dockItems = ConfigService.dockItems || []
        if (type === "app" && visibleIndex >= 0 && visibleIndex < visible.length) {
            const targetAppId = visible[visibleIndex].appId
            for (let i = 0; i < dockItems.length; i++) {
                const item = dockItems[i]
                if (item.type === "app" && item.appId === targetAppId)
                    return i
            }
        }
        return visibleIndex
    }

    function movePinnedItem(type, key, targetIndex) {
        if (!ConfigService.moveDockItem(type, key,
                _visibleSlotToDockIndex(type, targetIndex)))
            return
        console.log("[DockModel] reorder " + type + "=" + key
                    + " target=" + targetIndex)
        // ConfigService's dockItemsChanged connection already rebuilds the
        // presentation synchronously. A second rebuild here recreates pinned
        // delegates during their release animation and causes a visible flash.
    }


    Component.onCompleted: _refreshPresentation()
}
