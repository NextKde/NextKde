pragma Singleton
import QtQuick
import Quickshell.Wayland._ToplevelManagement
import qs.desktop.modules.platform

// WindowService — provider-neutral runtime window model.
//
// It currently uses Quickshell's Wayland Toplevel API. The public model uses
// canonical desktopId values from AppIdentityService, so a future Hyprland
// metadata adapter can add class/initialClass without changing Dock, Alt+Tab,
// or Stage Manager consumers.

QtObject {
    id: svc

    property ListModel windowModel: ListModel {}
    readonly property int windowCount: windowModel.count
    property var records: []
    property int revision: 0
    property string activeWindowId: ""

    // Forwarded by the KWin input effect through this service's existing local
    // bridge. Consumers use the global logical coordinates for outside-click
    // dismissal; the event itself is never consumed by KWin.
    signal globalPointerPressed(real x, real y, int button, real timestamp)

    property int _nextWindowNumber: 1
    property var _recordsById: ({})
    // KWin does not implement zwlr-foreign-toplevel-management-v1. Its local
    // bridge receives snapshots from our KWin Script over D-Bus and is used
    // only when the standard Wayland provider has no windows.
    property var _kwinWindows: []
    property bool _kwinReceivedInitialSnapshot: false
    // Serialized form of the last applied KWin snapshot. Redundant snapshots
    // (same content re-published) are dropped without scheduling a rebuild.
    property string _lastSnapshotJson: ""
    property var _pendingKwinActivation: null
    property bool _kwinScriptStarted: false
    property bool _kwinSubscribePending: false
    property var _thumbnailUrlsByHandle: ({})
    property var _thumbnailPendingByHandle: ({})
    // A QML binding can depend on this counter to observe a map entry update.
    property int thumbnailRevision: 0
    readonly property bool _kwinBridgeEnabled: true
    // The controller waits for this before doing its first collision pass, so a
    // smart dock does not hide against a still-empty initial window snapshot.
    // KWin is authoritative on Plasma (it does not expose foreign-toplevel), so
    // readiness there means "first KWin snapshot applied". On compositors that
    // do expose foreign-toplevel, readiness is "first collection done", even
    // when that collection is zero windows.
    property bool _hasRebuiltOnce: false
    // Readiness reached on the first foreign-toplevel collection (even zero
    // windows). On KWin this stays false because KWin owns the list via the
    // bridge instead.
    property bool _foreignRebuiltOnce: false
    // On the KWin build the bridge is authoritative, so readiness means "first
    // KWin snapshot applied" — an empty foreign collection at startup is not
    // proof the desktop is empty. On a future non-KWin build (bridge disabled)
    // the foreign provider is authoritative after its first collection.
    readonly property bool providerReady:
        svc._kwinReceivedInitialSnapshot
            || (!svc._kwinBridgeEnabled && svc._foreignRebuiltOnce)
    property Connections _platformEvents: Connections {
        target: PlatformClient
        function onEventReceived(eventName, payload) {
            if (eventName === "window.snapshot" || eventName === "desktops"
                    || eventName === "thumbnail" || eventName === "global-pointer-press")
                svc._consumeKwinEvent(payload)
        }
    }
    property Connections _platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                svc._subscribeKwin()
            } else {
                // The platform daemon drops subscriber sockets on restart;
                // discard its stale snapshot until the fresh bridge state is
                // delivered after reconnection.
                svc._kwinSubscribePending = false
                svc._kwinReceivedInitialSnapshot = false
                svc._lastSnapshotJson = ""
                svc._kwinWindows = []
                svc._rebuild()
            }
        }
    }

    property Repeater _topRepeater: Repeater {
        model: ToplevelManager.toplevels
        delegate: Item {
            id: toplevelDelegate
            readonly property Toplevel toplevel: modelData

            property Connections changeConnection: Connections {
                target: toplevelDelegate.toplevel
                // Not every foreign-toplevel implementation exposes urgent;
                // ignore that optional signal while observing it when present.
                ignoreUnknownSignals: true
                function onActivatedChanged() { svc._scheduleUpdate() }
                function onMinimizedChanged() { svc._scheduleUpdate() }
                function onDemandsAttentionChanged() { svc._scheduleUpdate() }
                function onTitleChanged() { svc._scheduleUpdate() }
                function onAppIdChanged() { svc._scheduleUpdate() }
                function onClosed() { svc._scheduleUpdate() }
            }
        }
    }

    property Timer _updateTimer: Timer {
        interval: 40
        repeat: false
        onTriggered: svc._rebuild()
    }

    // Merge pointer double-clicks or quick target changes before sending an
    // IPC request. The platform bridge also coalesces requests, but doing it
    // here avoids needless messages in the first place.
    property Timer _kwinActivationTimer: Timer {
        interval: 24
        repeat: false
        onTriggered: {
            const command = svc._pendingKwinActivation;
            svc._pendingKwinActivation = null;
            if (command)
                svc._sendKwinCommand(command);
        }
    }

    property Timer _countPoll: Timer {
        interval: 500
        repeat: true
        running: true
        property int previousCount: -1
        onTriggered: {
            if (previousCount !== svc._topRepeater.count) {
                previousCount = svc._topRepeater.count;
                svc._scheduleUpdate();
            }
        }
    }

    property Connections _managerConnections: Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { svc._scheduleUpdate() }
    }

    // If an app identity was initially resolved before DesktopEntries loaded,
    // rebuild the live model when the identity cache is invalidated so window
    // icons and canonical desktop IDs are corrected without a click.
    property Connections _identityConnections: Connections {
        target: AppIdentityService
        function onRevisionChanged() { svc._scheduleUpdate() }
    }

    function _scheduleUpdate() {
        _updateTimer.restart();
    }

    function _collectToplevels() {
        const result = [];
        for (let i = 0; i < _topRepeater.count; i++) {
            const item = _topRepeater.itemAt(i);
            if (item?.toplevel)
                result.push(item.toplevel);
        }
        return result;
    }

    function _findOldRecord(toplevel, provider, handleId) {
        for (let i = 0; i < svc.records.length; i++) {
            const record = svc.records[i];
            if (provider === "kwin") {
                if (record.provider === "kwin" && record.handleId === handleId)
                    return record;
            } else if (record.provider === "foreign" && record.toplevel === toplevel) {
                return svc.records[i];
            }
        }
        return null;
    }

    function _newWindowId() {
        return "window-" + (svc._nextWindowNumber++);
    }

    function _recordsEqual(left, right) {
        return left.windowId === right.windowId
            && left.provider === right.provider
            && left.handleId === right.handleId
            && left.title === right.title
            && left.identity.desktopId === right.identity.desktopId
            && left.identity.rawAppId === right.identity.rawAppId
            && left.iconSource === right.iconSource
            && left.pid === right.pid
            && !!left.isUrgent === !!right.isUrgent
            && !!left.toplevel.activated === !!right.toplevel.activated
            && !!left.toplevel.minimized === !!right.toplevel.minimized
            && !!left.toplevel.fullscreen === !!right.toplevel.fullscreen
            && !!left.onAllDesktops === !!right.onAllDesktops
            && left.desktopIds.length === right.desktopIds.length
            && left.desktopIds.every((id, i) => id === right.desktopIds[i])
            && !!left.isMaximized === !!right.isMaximized
            && !!left.isVisible === !!right.isVisible
            && (left.screenName || "") === (right.screenName || "")
            && geometriesEqual(left.geometry, right.geometry);
    }

    // Null-safe geometry equality. A window that moves (or stops reporting
    // geometry) must change the record or the Dock collision pass stays stale.
    function geometriesEqual(left, right) {
        if (!left || !right)
            return !left && !right;
        return left.x === right.x
            && left.y === right.y
            && left.width === right.width
            && left.height === right.height;
    }

    function _setRow(row, record) {
        const values = {
            windowId: record.windowId,
            desktopId: record.identity.desktopId,
            appId: record.identity.desktopId,
            rawAppId: record.identity.rawAppId,
            title: record.title,
            icon: record.iconSource,
            pid: record.pid,
            isActivated: record.toplevel.activated || false,
            isMinimized: record.toplevel.minimized || false,
            isFullscreen: record.toplevel.fullscreen || false,
            isUrgent: !!record.isUrgent,
        };
        const keys = Object.keys(values);
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            if (row[key] !== values[key])
                windowModel.setProperty(row.index, key, values[key]);
        }
    }

    function _rebuild() {
        const foreignTops = _collectToplevels();
        const useKwin = foreignTops.length === 0 && svc._kwinWindows.length > 0;
        const tops = useKwin ? svc._kwinWindows : foreignTops;
        const nextRecords = [];
        const nextById = ({});

        for (let i = 0; i < tops.length; i++) {
            const source = tops[i];
            const provider = useKwin ? "kwin" : "foreign";
            const handleId = useKwin ? String(source.id) : "";
            const toplevel = useKwin ? {
                activated: !!source.activated,
                minimized: !!source.minimized,
                fullscreen: !!source.fullscreen,
                pid: Number(source.pid || 0),
                appId: source.appId || "",
                title: source.title || "",
                desktopIds: Array.isArray(source.desktops) ? source.desktops : [],
                onAllDesktops: !!source.onAllDesktops,
                // Full-reveal geometry & placement for Dock collision.
                geometry: source.geometry && source.geometry.width > 0
                    ? source.geometry : null,
                outputName: source.outputName || "",
                maximized: !!source.maximized,
                visible: source.visible === undefined ? true : !!source.visible
            } : source;
            const old = _findOldRecord(toplevel, provider, handleId);
            const identity = AppIdentityService.resolve(toplevel.appId);
            // Presentation owns every icon lookup so Dock, QuickSearch,
            // notifications and AppLauncher render the exact same source,
            // and the icon engine picks a size-appropriate asset. The KWin
            // bridge's themed path is only a fallback for icon names that
            // Quickshell's own theme lookup cannot resolve.
            const iconSource = useKwin && !identity.iconSource && source.iconPath
                ? "file://" + source.iconPath : identity.iconSource;
            // zwlr-foreign-toplevel does not require an urgency field, so
            // read it defensively. KWin's bridge always provides `urgent`.
            let foreignUrgent = false;
            if (!useKwin) {
                try { foreignUrgent = !!source.demandsAttention; } catch (e) {}
            }
            const record = {
                windowId: old?.windowId ?? _newWindowId(),
                toplevel: toplevel,
                provider: provider,
                handleId: handleId,
                identity: identity,
                pid: Number(toplevel.pid || 0),
                iconSource: iconSource,
                title: toplevel.title || identity.name || identity.desktopId,
                isUrgent: useKwin ? !!source.urgent : foreignUrgent,
                desktopIds: Array.isArray(toplevel.desktopIds) ? toplevel.desktopIds : [],
                onAllDesktops: !!toplevel.onAllDesktops,
                // Provision-normalised placement used by the Dock auto-hide
                // controller. Foreign-toplevel has no compositor geometry, so
                // those stay null/unknown and the controller degrades.
                geometry: useKwin && toplevel.geometry ? toplevel.geometry : null,
                screenName: useKwin ? (toplevel.outputName || "") : "",
                isMaximized: useKwin ? !!toplevel.maximized : false,
                isVisible: useKwin
                    ? !!toplevel.visible
                    : (toplevel.minimized ? false : true),
            };
            nextRecords.push(record);
            nextById[record.windowId] = record;
        }

        let changed = svc.records.length !== nextRecords.length;
        if (!changed) {
            for (let i = 0; i < nextRecords.length; i++) {
                if (!svc._recordsEqual(svc.records[i], nextRecords[i])) {
                    changed = true;
                    break;
                }
            }
        }
        if (!changed)
            return;

        svc._hasRebuiltOnce = true;
        if (!useKwin)
            svc._foreignRebuiltOnce = true;

        while (windowModel.count > tops.length)
            windowModel.remove(windowModel.count - 1);

        for (let i = 0; i < nextRecords.length; i++) {
            const record = nextRecords[i];
            if (i >= windowModel.count) {
                windowModel.append({
                    windowId: record.windowId,
                    desktopId: record.identity.desktopId,
                    appId: record.identity.desktopId,
                    rawAppId: record.identity.rawAppId,
                    title: record.title,
                    icon: record.iconSource,
                    pid: record.pid,
                    isActivated: record.toplevel.activated || false,
                    isMinimized: record.toplevel.minimized || false,
                    isFullscreen: record.toplevel.fullscreen || false,
                    isUrgent: !!record.isUrgent,
                });
            } else {
                const row = windowModel.get(i);
                const values = {
                    windowId: record.windowId,
                    desktopId: record.identity.desktopId,
                    appId: record.identity.desktopId,
                    rawAppId: record.identity.rawAppId,
                    title: record.title,
                    icon: record.iconSource,
                    pid: record.pid,
                    isActivated: record.toplevel.activated || false,
                    isMinimized: record.toplevel.minimized || false,
                    isFullscreen: record.toplevel.fullscreen || false,
                    isUrgent: !!record.isUrgent,
                };
                const keys = Object.keys(values);
                for (let j = 0; j < keys.length; j++) {
                    const key = keys[j];
                    if (row[key] !== values[key])
                        windowModel.setProperty(i, key, values[key]);
                }
            }
        }

        svc.records = nextRecords;
        svc._recordsById = nextById;
        const active = nextRecords.find(record => record.toplevel.activated);
        svc.activeWindowId = active?.windowId ?? "";
        svc.revision++;
    }

    // ── Virtual desktops (KWin D-Bus, via the bridge) ──
    // List of { id, name, order }. The overview maps each window's
    // record.desktopIds against these ids to place windows on desktops.
    property var desktops: []
    property string currentDesktopId: ""

    // Switch to a virtual desktop by id (KWin performs the actual switch).
    function switchDesktop(id) {
        _sendKwinCommand({ action: "switch-desktop", id: id })
    }

    function windowById(windowId) {
        return _recordsById[String(windowId)] ?? null;
    }

    function windowsForApp(desktopId) {
        const result = [];
        for (let i = 0; i < records.length; i++) {
            if (AppIdentityService.sameApp(records[i].identity, desktopId))
                result.push(records[i]);
        }
        return result;
    }

    function thumbnailUrl(windowId) {
        // Reading the revision makes bindings reactive while retaining a
        // private map keyed by KWin's stable UUID.
        thumbnailRevision
        const record = windowById(windowId);
        return record?.provider === "kwin"
            ? (_thumbnailUrlsByHandle[record.handleId] ?? "") : "";
    }

    function requestThumbnail(windowId) {
        const record = windowById(windowId);
        if (!record) {
            console.warn("[WindowService] thumbnail missing windowId=" + windowId);
            return false;
        }
        if (record.provider !== "kwin" || !record.handleId) {
            console.warn("[WindowService] thumbnail unavailable provider="
                + record.provider + " windowId=" + windowId);
            return false;
        }
        if (_thumbnailPendingByHandle[record.handleId])
            return false;

        const pending = Object.assign({}, _thumbnailPendingByHandle);
        pending[record.handleId] = true;
        _thumbnailPendingByHandle = pending;
        console.log("[WindowService] thumbnail request id=" + record.handleId);
        _sendKwinCommand({ action: "thumbnail", id: record.handleId });
        return true;
    }

    function activateWindow(windowId) {
        const record = windowById(windowId);
        if (!record) {
            console.warn("[WindowService] activate missing windowId=" + windowId);
            return;
        }
        if (record.provider === "kwin") {
            _enqueueKwinCommand({ action: "activate", id: record.handleId });
            return;
        }
        try { record.toplevel.activate(); } catch (e) {}
    }

    function minimizeWindow(windowId, value) {
        const record = windowById(windowId);
        if (!record)
            return;
        if (record.provider === "kwin") {
            _enqueueKwinCommand({
                action: "minimize",
                id: record.handleId,
                value: value === undefined ? true : value
            });
            return;
        }
        try { record.toplevel.minimized = value === undefined ? true : value; } catch (e) {}
    }

    function closeWindow(windowId) {
        const record = windowById(windowId);
        if (!record)
            return;
        if (record.provider === "kwin") {
            _enqueueKwinCommand({ action: "close", id: record.handleId });
            return;
        }
        try { record.toplevel.close(); } catch (e) {}
    }

    property var _minimizedByShowDesktop: []

    function toggleShowDesktop() {
        const currentId = svc.currentDesktopId;
        const records = svc.records || [];
        const currentDeskWindows = [];

        for (let i = 0; i < records.length; i++) {
            const r = records[i];
            const onDesktop = r.toplevel?.onAllDesktops
                || (Array.isArray(r.toplevel?.desktopIds) && r.toplevel.desktopIds.indexOf(currentId) >= 0)
                || (Array.isArray(r.desktopIds) && r.desktopIds.indexOf(currentId) >= 0);
            if (onDesktop) {
                currentDeskWindows.push(r);
            }
        }

        const unminimized = currentDeskWindows.filter(r => !r.toplevel?.minimized);

        if (unminimized.length > 0) {
            // There are visible open windows on current desktop: minimize all of them
            _minimizedByShowDesktop = unminimized.map(r => r.windowId);
            for (let i = 0; i < unminimized.length; i++) {
                minimizeWindow(unminimized[i].windowId, true);
            }
        } else {
            // All windows on current desktop are minimized: restore previously minimized or all
            const toRestore = _minimizedByShowDesktop.length > 0
                ? _minimizedByShowDesktop
                : currentDeskWindows.map(r => r.windowId);

            for (let i = 0; i < toRestore.length; i++) {
                minimizeWindow(toRestore[i], false);
            }
            _minimizedByShowDesktop = [];
        }
    }

    function _consumeKwinEvent(event) {
            try {
                if (event.type !== "snapshot")
                    console.log("[WindowService] bridge event type=" + event.type
                        + (event.stage ? " stage=" + event.stage : ""));
                if (event.type === "snapshot" && Array.isArray(event.windows)) {
                        // Coalesce redundant snapshots. The KWin script already
                        // publishes only on change, but a second filter here
                        // keeps the model rebuild rate bounded even if a future
                        // provider stops deduplicating.
                        const snapshotJson = JSON.stringify(event.windows);
                        if (snapshotJson === svc._lastSnapshotJson)
                            return;
                        svc._lastSnapshotJson = snapshotJson;
                        // Keep activation direct. Virtual-desktop transient
                        // filtering is handled separately; delaying this
                        // authoritative list also delayed focus changes.
                        svc._kwinWindows = event.windows;
                        if (!svc._kwinReceivedInitialSnapshot) {
                            svc._kwinReceivedInitialSnapshot = true;
                            console.info("[WindowService] initial KWin snapshot windows="
                                + event.windows.length)
                        }
                        // KWin already coalesces metadata bursts and throttles
                        // live geometry. Apply its authoritative snapshot now;
                        // another 40ms debounce here only adds latency to Dock
                        // collision edges and can itself be restarted by motion.
                        svc._updateTimer.stop();
                        svc._rebuild();
                } else if (event.type === "thumbnail" && event.id) {
                        const pending = Object.assign({}, svc._thumbnailPendingByHandle);
                        delete pending[event.id];
                        svc._thumbnailPendingByHandle = pending;
                        if (event.path) {
                            const urls = Object.assign({}, svc._thumbnailUrlsByHandle);
                            urls[event.id] = "file://" + event.path;
                            svc._thumbnailUrlsByHandle = urls;
                            svc.thumbnailRevision++;
                            console.log("[WindowService] thumbnail ready id="
                                + event.id + " " + event.width + "x" + event.height);
                        } else if (event.error) {
                            console.warn("[WindowService] thumbnail failed id="
                                + event.id + " error=" + event.error);
                        }
                } else if (event.type === "desktops") {
                        if (Array.isArray(event.desktops)) {
                            svc.desktops = event.desktops;
                            svc.currentDesktopId = event.current ?? "";
                        }
                } else if (event.type === "global-pointer-press") {
                        svc.globalPointerPressed(Number(event.x), Number(event.y),
                                                 Number(event.button),
                                                 Number(event.timestamp));
                }
            } catch (e) {
                console.warn("[WindowService] invalid KWin event: " + e);
            }
    }

    function _enqueueKwinCommand(command) {
        if (command.action === "activate") {
            svc._pendingKwinActivation = command;
            svc._kwinActivationTimer.restart();
            return;
        }
        svc._sendKwinCommand(command);
    }

    function _sendKwinCommand(command) {
        PlatformClient.request("kwin.command", command, function(response) {
            if (!response?.ok)
                console.warn("[WindowService] KWin command failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    function _subscribeKwin() {
        if (!_kwinBridgeEnabled || _kwinSubscribePending)
            return
        _kwinSubscribePending = true
        PlatformClient.request("kwin.subscribe", {}, function(response) {
            _kwinSubscribePending = false
            if (!response?.ok)
                console.warn("[WindowService] KWin subscription failed: "
                    + (response?.error?.message || "platform unavailable"))
        })
    }

    Component.onCompleted: {
        if (svc._kwinBridgeEnabled) {
            _subscribeKwin()
            _scheduleUpdate()
        }
    }
}
