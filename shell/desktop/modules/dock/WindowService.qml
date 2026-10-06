pragma Singleton
import QtQuick
import Quickshell.Io
import Quickshell.Wayland._ToplevelManagement
import qs.desktop.modules.platform
import qs.desktop.modules.common
import "ProcessIdentity.mjs" as ProcessIdentity
import "WindowRecordIndex.mjs" as WindowRecordIndex

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
    // Placement consumers must observe this counter, not recordsChanged.
    // Pure geometry updates retain the presentation array and its objects.
    property int placementRevision: 0
    property string activeWindowId: ""
    // KWin's real active window (unfiltered scan in the bridge snapshot):
    // non-empty while ANY window holds focus, including transient dialogs
    // that never enter `records`. Empty = genuinely nothing active (desktop).
    property string kwinActiveId: ""
    // KWin 活动窗是自己的全屏桌面表面（挂件层/壁纸）＝"焦点在桌面上"
    // 而不是"未跟踪 transient"——桌面聚焦语义的判据（见 window-bridge.js）
    property bool kwinActiveDesktop: false

    // Forwarded by the KWin input effect through this service's existing local
    // bridge. Consumers use the global logical coordinates for outside-click
    // dismissal; the event itself is never consumed by KWin.
    signal globalPointerPressed(real x, real y, int button, real timestamp)

    // Activation requested by this process (dock icon/preview/menu click):
    // emitted the instant the click happens, before the bridge command is
    // queued. Stage's sidebar uses it to run the simultaneous swap without
    // waiting for the change to round-trip through the 120ms-debounced
    // snapshot path.
    signal activationRequested(string windowId)
    // Bridge command receipt (round35 NEW-2): fired for every action echo
    // from the KWin script. found=false means the command could not be
    // applied (window gone / bridge not ready); consumers that gate UI state
    // on command success (stage engage) reset on this instead of staying
    // stuck when the command was lost.
    signal commandFinished(string action, string ticket, bool found)

    property int _nextWindowNumber: 1
    property var _recordsById: ({})
    // KWin does not implement zwlr-foreign-toplevel-management-v1. Its local
    // bridge receives snapshots from our KWin Script over D-Bus and is used
    // only when the standard Wayland provider has no windows.
    property var _kwinWindows: []
    property bool _kwinReceivedInitialSnapshot: false
    property bool _kwinReceivedDesktopSnapshot: false
    // Serialized form of the last applied KWin snapshot. Redundant snapshots
    // (same content re-published) are dropped without scheduling a rebuild.
    property string _lastSnapshotJson: ""
    property var _pendingKwinActivation: null
    property bool _kwinScriptStarted: false
    property bool _kwinSubscribePending: false
    // Process-side identity hints, keyed by window PID. A window resolves from
    // its reported app id first; these are consulted only when that finds
    // nothing, because some toolkits report an id that no installed entry
    // carries. See ProcessIdentity.mjs.
    property var _processHintsByPid: ({})
    property var _processProbeByPid: ({})
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
        (svc._kwinReceivedInitialSnapshot && svc._kwinReceivedDesktopSnapshot)
            || (!svc._kwinBridgeEnabled && svc._foreignRebuiltOnce)
    property Connections _platformEvents: Connections {
        target: PlatformClient
        function onEventReceived(eventName, payload) {
            // window.action = 命令回执（publishAction）：engage-swap 派发
            // 失败自愈（stage 侧 engaging 卡复位）依赖它——漏掉这个过滤
            // 项会让整条回执链变成死代码（桥一路发到 shell 门口被丢弃）
            if (eventName === "window.snapshot" || eventName === "desktops"
                    || eventName === "thumbnail"
                    || eventName === "global-pointer-press"
                    || eventName === "window.action")
                svc._consumeKwinEvent(payload)
        }
    }
    property Connections _platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            svc._handlePlatformTransport(connected)
        }
    }

    // Losing the platform daemon must not make every running application
    // disappear from Dock. Keep the last authoritative KWin snapshot and its
    // virtual-desktop state as a read-only fallback; actions already fail
    // harmlessly through PlatformClient while it is offline. Reconnection
    // subscribes again and replaces the stale data with a fresh snapshot.
    function _handlePlatformTransport(connected) {
        if (connected) {
            svc._subscribeKwin()
            return
        }
        svc._kwinSubscribePending = false
        svc._pendingKwinActivation = null
        svc._kwinActivationTimer.stop()
        // Thumbnail replies are event-only and cannot arrive after the socket
        // drops. Their temporary files may also belong to the old daemon.
        svc._thumbnailPendingByHandle = ({})
        if (Object.keys(svc._thumbnailUrlsByHandle).length) {
            svc._thumbnailUrlsByHandle = ({})
            svc.thumbnailRevision++
        }
        console.warn("[WindowService] platform disconnected; keeping "
            + svc.records.length + " cached windows until reconnection")
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

    // A KDE icon-theme change must re-resolve live window icons too. Records
    // were built against the themed `image://icon` source; walking the snapshot
    // again on the theme revision flips any KWin-baked file:// path to that
    // stable themed source. DockIcon recreates its renderer on the same
    // revision, so the re-request paints against the newly active theme.
    property Connections _iconThemeConnections: Connections {
        target: IconThemeReloadService
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

    function _newWindowId() {
        return "window-" + (svc._nextWindowNumber++);
    }

    function _presentationEqual(left, right) {
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
            && left.desktopIds.every((id, i) => id === right.desktopIds[i]);
    }

    function _placementEqual(left, right) {
        return !!left.isMaximized === !!right.isMaximized
            && !!left.isVisible === !!right.isVisible
            && (left.screenName || "") === (right.screenName || "")
            && geometriesEqual(left.geometry, right.geometry);
    }

    function _updatePlacement(record, next) {
        record.geometry = next.geometry;
        record.screenName = next.screenName;
        record.isMaximized = next.isMaximized;
        record.isVisible = next.isVisible;
        // KWin toplevels are plain snapshot objects; foreign toplevels are
        // provider-owned QObjects and must never be written here.
        if (record.provider === "kwin") {
            record.toplevel.geometry = next.toplevel.geometry;
            record.toplevel.outputName = next.toplevel.outputName;
            record.toplevel.maximized = next.toplevel.maximized;
            record.toplevel.visible = next.toplevel.visible;
        }
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


    function _rebuild() {
        const foreignTops = _collectToplevels();
        const useKwin = foreignTops.length === 0 && svc._kwinWindows.length > 0;
        const tops = useKwin ? svc._kwinWindows : foreignTops;
        const nextRecords = [];
        const nextById = ({});
        const oldRecords = WindowRecordIndex.indexWindowRecords(svc.records);

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
            const old = useKwin ? oldRecords.kwin.get(handleId)
                : oldRecords.foreign.get(toplevel);
            const windowPid = Number(toplevel.pid || 0);
            svc._ensureProcessHints(windowPid);
            const identity = AppIdentityService.resolve(toplevel.appId,
                svc._processHintsByPid[windowPid]);
            // Prefer the shared themed presentation source (image://icon/<name>)
            // for live tasks too, exactly like the launcher and pinned apps.
            // DockIcon recreates its renderer on an icon-theme revision to
            // re-request that stable URL, so a KDE theme change refreshes
            // running-window icons. Fall back to KWin's absolute icon file only
            // when theme lookup yields nothing.
            const themedSource = identity.iconSource;
            const iconSource = themedSource
                || (useKwin && source.iconPath
                    ? "file://" + source.iconPath : themedSource);
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
        let presentationChanged = changed;
        if (!presentationChanged) {
            for (let i = 0; i < nextRecords.length; i++) {
                if (!svc._presentationEqual(svc.records[i], nextRecords[i])) {
                    presentationChanged = true;
                    changed = true;
                    break;
                }
                if (!svc._placementEqual(svc.records[i], nextRecords[i]))
                    changed = true;
            }
        }
        // readiness 置位必须在 early-return 之前（v87 审查）：零窗首次
        // 收集 changed=false 直接返回＝_foreignRebuiltOnce 永不置位，
        // providerReady 契约（"first collection done, even when zero
        // windows"）被打破，非 KWin 合成器路径的 dock 首拍碰撞判定悬空
        svc._hasRebuiltOnce = true;
        if (!useKwin)
            svc._foreignRebuiltOnce = true;
        if (!changed)
            return;

        if (!presentationChanged) {
            for (let i = 0; i < nextRecords.length; i++)
                svc._updatePlacement(svc.records[i], nextRecords[i]);
            svc.placementRevision++;
            return;
        }

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
        // MRU 时间戳（v87 审查）：dock 多窗应用点击应激活"最近用过的窗"
        // 而不是 records 序首窗——历史行为与注释语义不符。copy-on-write
        //（var 属性原地变异不发通知，v82 P0 同款坑）
        if (active) {
            const stamps = Object.assign({}, svc._lastActivatedAt)
            stamps[active.windowId] = Date.now()
            svc._lastActivatedAt = stamps
        }
        svc.revision++;
        // Add/remove, minimization and desktop membership also affect
        // collision eligibility, so presentation updates notify both lanes.
        svc.placementRevision++;
        svc._pruneThumbnails(nextRecords);
        svc._pruneProcessHints(nextRecords);
    }

    // windowId → 最近一次成为活动窗的时间戳（0 = 未知，排最后）
    property var _lastActivatedAt: ({})
    function lastActivatedAtOf(windowId) {
        return _lastActivatedAt[windowId] || 0
    }

    // Thumbnail state is keyed by KWin's window handle, which dies with the
    // window. Without this sweep a closed window would leave its PNG URL and
    // any pending mark behind forever; a late thumbnail event for a dead
    // handle is dropped again on the next rebuild.
    function _pruneThumbnails(nextRecords) {
        const live = {};
        for (let i = 0; i < nextRecords.length; i++) {
            if (nextRecords[i].handleId)
                live[nextRecords[i].handleId] = true;
        }
        let evicted = false;
        const urls = {};
        for (const handle in svc._thumbnailUrlsByHandle) {
            if (live[handle])
                urls[handle] = svc._thumbnailUrlsByHandle[handle];
            else
                evicted = true;
        }
        if (evicted) {
            svc._thumbnailUrlsByHandle = urls;
            svc.thumbnailRevision++;
        }
        let pendingChanged = false;
        const pending = {};
        for (const handle in svc._thumbnailPendingByHandle) {
            if (live[handle])
                pending[handle] = svc._thumbnailPendingByHandle[handle];
            else
                pendingChanged = true;
        }
        if (pendingChanged)
            svc._thumbnailPendingByHandle = pending;
    }

    // ── Process identity fallback ──
    // One probe per PID, run lazily on the first frame that needs it. The
    // pipeline is asynchronous, so a window keeps its first (possibly generic)
    // icon for a few milliseconds and repaints once the hints land.
    property Component _processProbeFactory: Component {
        Process { stdout: StdioCollector {} }
    }

    function _ensureProcessHints(pid) {
        if (!(pid > 0))
            return;
        if (svc._processHintsByPid[pid] !== undefined)
            return;
        if (svc._processProbeByPid[pid])
            return;
        const probe = svc._processProbeFactory.createObject(svc, {
            command: ProcessIdentity.probeCommand(pid)
        });
        const pending = Object.assign({}, svc._processProbeByPid);
        pending[pid] = probe;
        svc._processProbeByPid = pending;
        probe.exited.connect(function() {
            const hints = ProcessIdentity.parseProbeOutput(probe.stdout?.text ?? "");
            const inFlight = Object.assign({}, svc._processProbeByPid);
            delete inFlight[pid];
            svc._processProbeByPid = inFlight;
            // pid 仍在当前 records 里才入缓存（v87 审查）：probe 在途期间
            // 窗口关闭（或被剪枝销毁后 exited 仍触发）时，把已死 pid 的
            // hints 塞回缓存＝pid 复用后污染无关新窗的身份。rebuild 循环
            // 是同步的，exited 异步到达时 records 已含新窗快照
            let stillLive = false;
            const recs = svc.records || [];
            for (let i = 0; i < recs.length; i++) {
                if (recs[i].pid === pid) {
                    stillLive = true;
                    break;
                }
            }
            // An empty result is cached too: a window that cannot be identified
            // must not be probed again on every rebuild.
            if (stillLive) {
                const resolved = Object.assign({}, svc._processHintsByPid);
                resolved[pid] = hints;
                svc._processHintsByPid = resolved;
            }
            probe.destroy();
            if (hints.length && stillLive)
                svc._scheduleUpdate();
        });
        probe.running = true;
    }

    // Per-PID hints die with the PID: the kernel recycles PIDs, and a survivor
    // would seed a later window with an unrelated application's identity.
    function _pruneProcessHints(nextRecords) {
        const live = {};
        for (let i = 0; i < nextRecords.length; i++) {
            const pid = nextRecords[i].pid;
            if (pid > 0)
                live[pid] = true;
        }
        let stale = false;
        const kept = {};
        for (const pid in svc._processHintsByPid) {
            if (live[pid])
                kept[pid] = svc._processHintsByPid[pid];
            else
                stale = true;
        }
        if (stale)
            svc._processHintsByPid = kept;
        // A probe whose PID disappeared before it reported would otherwise be
        // kept — and that PID would never be probed again.
        let inFlight = null;
        for (const pid in svc._processProbeByPid) {
            if (live[pid])
                continue;
            if (!inFlight)
                inFlight = Object.assign({}, svc._processProbeByPid);
            if (inFlight[pid])
                inFlight[pid].destroy();
            delete inFlight[pid];
        }
        if (inFlight)
            svc._processProbeByPid = inFlight;
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

    // Toggle Plasma's native KWin Overview effect.
    function toggleOverview() {
        _sendKwinCommand({ action: "toggle-overview" })
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

    // KWin 的稳定窗口 UUID（PlasmaWindow uuid / internalId 去花括号）——
    // zkde_screencast 单窗口流的 uuid 口径（ScreencastingRequest 同源）。
    // shell 句柄（window-N）不是 KWin id，直传会静默开不出流。
    function handleIdOf(windowId) {
        const record = windowById(windowId);
        return record?.provider === "kwin" ? (record.handleId ?? "") : "";
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
        activationRequested(windowId);
        if (record.provider === "kwin") {
            _enqueueKwinCommand({ action: "activate", id: record.handleId });
            return;
        }
        try { record.toplevel.activate(); } catch (e) {}
    }

    // 整组一起展开（macOS 语义）：同应用全部窗口还原抬升、focusId 最后激活
    // 拿焦点。必须走单个 activate-group 原子命令——连续的 activate 会被
    // _kwinActivationTimer 的单槽合并吞掉兄弟窗的还原（dock/侧栏两条入口
    // 都踩过）。activationRequested 只对 focus 窗发一次（stage 退位交换）。
    function activateGroup(windowIds, focusId) {
        const ids = [];
        for (let i = 0; i < windowIds.length; i++) {
            const record = windowById(windowIds[i]);
            if (!record)
                continue;
            if (record.provider === "kwin") {
                ids.push(record.handleId);
            } else {
                try { record.toplevel.activate(); } catch (e) {}
            }
        }
        if (ids.length === 0)
            return;
        const focusRecord = windowById(focusId);
        const focusHandle = focusRecord?.provider === "kwin"
            ? focusRecord.handleId : ids[ids.length - 1];
        activationRequested(focusId);
        _sendKwinCommand({ action: "activate-group", ids: ids,
            focusId: focusHandle });
    }

    // 同拍交换（点击卡片）：激活目标组 + 收编退位组走**一条原子命令**——
    // 分开发会按桥的 50ms 命令轮询一拍一条，收编比激活晚一拍起跑（实测
    // 50ms，实时模式肉眼可见的"慢半拍"）。activationRequested 只对焦点窗
    // 发一次（stage 退位交换 / dock 路径都依赖它）。
    function engageSwap(activateIds, focusId, minimizeIds, ticket) {
        const actHandles = [];
        for (let i = 0; i < activateIds.length; i++) {
            const record = windowById(activateIds[i]);
            if (!record)
                continue;
            if (record.provider === "kwin") {
                actHandles.push(record.handleId);
            } else {
                try { record.toplevel.activate(); } catch (e) {}
            }
        }
        if (actHandles.length === 0)
            return;
        const minHandles = [];
        for (let m = 0; m < minimizeIds.length; m++) {
            const record = windowById(minimizeIds[m]);
            if (record?.provider === "kwin")
                minHandles.push(record.handleId);
        }
        const focusRecord = windowById(focusId);
        const focusHandle = focusRecord?.provider === "kwin"
            ? focusRecord.handleId : actHandles[actHandles.length - 1];
        activationRequested(focusId);
        _sendKwinCommand({ action: "engage-swap", ids: actHandles,
            focusId: focusHandle, minimizeIds: minHandles,
            ticket: ticket || undefined });
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

    function minimizeAllWindows() {
        const current = svc.records || [];
        const ids = [];
        for (let i = 0; i < current.length; i++) {
            if (!current[i].toplevel?.minimized)
                ids.push(current[i].windowId);
        }
        // 原子批量（v87 审查）：逐窗 minimizeWindow 在桥侧 50ms/条排队，
        // N 窗阶梯延迟——与 minimizeGroup 的注释规约一致（多窗批量一律
        // 走它）
        minimizeGroup(ids, true);
    }

    // 整组原子最小化：逐窗命令在桥侧 50ms/条排队（shell 侧的合并槽只
    // 作用于 activate，minimize 本就直发——真正的串行化瓶颈在桥），
    // N 窗收编管线会被拖到 N*50ms——比显示桌面开关的防抖还长（打断窗口
    // 的根源，实测踩过）。多窗批量一律走这里，单窗路径用 minimizeWindow。
    function minimizeGroup(windowIds, value) {
        const ids = [];
        for (let i = 0; i < windowIds.length; i++) {
            const record = windowById(windowIds[i]);
            if (!record)
                continue;
            if (record.provider === "kwin") {
                ids.push(record.handleId);
            } else {
                try { record.toplevel.minimized = value === undefined ? true : value; } catch (e) {}
            }
        }
        if (ids.length === 0)
            return;
        _sendKwinCommand({ action: "minimize-group", ids: ids,
            value: value === undefined ? true : value });
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
            minimizeGroup(_minimizedByShowDesktop, true);
        } else {
            // All windows on current desktop are minimized: restore previously minimized or all
            // （恢复集过滤已消失的 id：窗口在收起期间关闭时，逐条发死 id
            // 只会在桥侧留 warn——v87 审查）
            const toRestore = (_minimizedByShowDesktop.length > 0
                ? _minimizedByShowDesktop
                : currentDeskWindows.map(r => r.windowId))
                .filter(id => !!windowById(id));

            minimizeGroup(toRestore, false);
            _minimizedByShowDesktop = [];
        }
    }

    function _consumeKwinEvent(event) {
            try {
                if (event.type !== "snapshot")
                    console.log("[WindowService] bridge event type=" + event.type
                        + (event.stage ? " stage=" + event.stage : ""));
                // Command receipts (round35 NEW-2): the bridge echoes every
                // command's outcome (action + optional shell ticket). Only
                // consumers that need confirmation subscribe; snapshot state
                // self-corrects everything else.
                if (event.type === "action") {
                    svc.commandFinished(String(event.action ?? ""),
                        String(event.ticket ?? ""), !!event.found);
                    return;
                }
                if (event.type === "snapshot" && Array.isArray(event.windows)) {
                        // Coalesce redundant snapshots. The KWin script already
                        // publishes only on change, but a second filter here
                        // keeps the model rebuild rate bounded even if a future
                        // provider stops deduplicating. activeId joins the key:
                        // focus moving onto an untracked dialog changes nothing
                        // in `windows` but must still reach consumers.
                        // activeDesktop 同理：桌面表面（quickshell）不在
                        // windows 里，它拿走/交还焦点时 windows 与 activeId
                        // 都不变——漏键会把桌面聚焦状态冻结在旧值。
                        const snapshotJson = JSON.stringify(event.windows)
                            + "#" + (event.activeId ?? "")
                            + "#" + (event.activeDesktop ? 1 : 0);
                        if (snapshotJson === svc._lastSnapshotJson)
                            return;
                        svc._lastSnapshotJson = snapshotJson;
                        // Keep activation direct. Virtual-desktop transient
                        // filtering is handled separately; delaying this
                        // authoritative list also delayed focus changes.
                        svc.kwinActiveId = String(event.activeId ?? "");
                        svc.kwinActiveDesktop = !!event.activeDesktop;
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
                        // A capture requested just before its window closed
                        // resolves after the handle was pruned; storing it
                        // would resurrect a dead key until the next
                        // presentation rebuild.
                        const live = svc.records.some(
                            record => record.handleId === event.id);
                        if (event.path && live) {
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
                        svc.desktops = Array.isArray(event.desktops)
                            ? event.desktops : [];
                        svc.currentDesktopId = event.current ?? "";
                        if (!svc._kwinReceivedDesktopSnapshot) {
                            svc._kwinReceivedDesktopSnapshot = true;
                            console.info("[WindowService] initial desktop snapshot desktops="
                                + svc.desktops.length + " current=" + svc.currentDesktopId)
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
            if (!response?.ok) {
                console.warn("[WindowService] KWin command failed: "
                    + (response?.error?.message || "platform unavailable"))
                // A rejected thumbnail request never produces a thumbnail
                // event, so release the pending mark here or the handle is
                // stuck until the next disconnect.
                if (command.action === "thumbnail"
                        && svc._thumbnailPendingByHandle[command.id]) {
                    const pending = Object.assign({}, svc._thumbnailPendingByHandle)
                    delete pending[command.id]
                    svc._thumbnailPendingByHandle = pending
                }
                // 传输层失败必须合成失败回执：带票根的命令（engage-swap）
                // 的自愈全靠 commandFinished——被拒后没人发＝engaging 卡
                // 永久隐形，直到某次模型重建顺带救回（"命令丢失自愈只修
                // 了半条链"）
                if (command.ticket !== undefined)
                    svc.commandFinished(command.action, command.ticket, false)
            }
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
            else {
                svc._sendKwinCommand({ action: "desktops" })
                // The replayed cache can predate the current focus (a
                // no-focus instant leaves every window activated=false and
                // no later windowActivated event corrects it) — ask the
                // bridge for a fresh authoritative snapshot. Seeds
                // activeWindowId after shell restarts.
                svc._sendKwinCommand({ action: "refresh-snapshot" })
            }
        })
    }

    Component.onCompleted: {
        if (svc._kwinBridgeEnabled) {
            _subscribeKwin()
            _scheduleUpdate()
        }
    }
}
