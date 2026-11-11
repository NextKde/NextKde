pragma Singleton

import QtQuick
import Quickshell
import qs.desktop.modules.platform
import qs.desktop.modules.dock
import qs.desktop.modules.common
import "InputMethodPlacement.mjs" as Placement

QtObject {
    id: svc

    property bool available: PlatformClient.supports("inputmethod.kimpanel")
    property bool userEnabled: false
    property bool takeoverActive: false
    property bool changing: false
    property string error: ""
    property bool enabled: false
    property bool visible: false
    property bool lookupVisible: false
    property bool preeditVisible: false
    property string preeditText: ""
    property int preeditCaret: 0
    property bool auxVisible: false
    property string auxText: ""
    property int cursorIndex: -1
    property bool hasPrev: false
    property bool hasNext: false
    property int layout: 0
    property var candidates: []
    property var spot: ({})
    property var kwinCaret: ({})
    property string imLabel: "中"
    property string imIcon: "fcitx-rime"
    property string imName: "中州韵"
    property var properties: []
    property var menuItems: []
    // Published once after all fields are applied, rather than exposing the
    // intermediate assignments to the animated panel.
    property var popupState: ({})
    property bool _popupSessionOpen: false
    property bool _anchorPending: false
    property int _anchorSerial: 0
    property var _openingCaret: ({})

    signal menuReceived(var items)

    readonly property var activeWindow: {
        const activeId = WindowService.kwinActiveId;
        if (!activeId) return null;
        const records = WindowService.records;
        for (let i = 0; i < records.length; ++i) {
            if (records[i].handleId === activeId || records[i].windowId === activeId) return records[i];
        }
        return null;
    }

    readonly property var globalAnchor: Placement.resolveGlobalSpotRect(
        spot,
        activeWindow,
        _openingCaret,
        Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    )

    readonly property string targetScreenName: Placement.targetScreenName(
        globalAnchor, ScreenLifecycle.usableScreens, activeWindow, ScreenLifecycle.activeScreen)

    property Connections _windowWatch: Connections {
        target: WindowService
        function onKwinActiveIdChanged() {
            svc._openingCaret = ({});
        }
    }

    property Connections _platformEvents: Connections {
        target: PlatformClient
        function onEventReceived(eventName, payload) {
            if (eventName === "inputmethod.state") {
                svc._applyState(payload || ({}));
            } else if (eventName === "inputmethod.menu") {
                svc.menuItems = payload?.items || [];
                svc.menuReceived(svc.menuItems);
            }
        }
    }

    property Connections _platformTransport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            if (connected) {
                svc._subscribe();
            } else {
                svc.visible = false;
                svc._endPopupSession();
                svc.popupState = Object.assign({}, svc.popupState, { visible: false });
            }
        }
    }

    Component.onCompleted: {
        if (PlatformClient.connected) {
            svc._subscribe();
        }
    }

    function _subscribe() {
        PlatformClient.request("inputmethod.subscribe", {}, function(response) {
            if (!response?.ok) {
                console.warn("[InputMethodService] Failed to subscribe to inputmethod events");
            }
        });
    }

    function _applyState(state) {
        svc.userEnabled = !!state.userEnabled;
        svc.takeoverActive = !!state.takeoverActive;
        svc.changing = !!state.changing;
        svc.error = String(state.error || "");
        svc.enabled = !!state.enabled;
        svc.visible = !!state.visible;
        svc.lookupVisible = !!state.lookupVisible;
        svc.preeditVisible = !!state.preeditVisible;
        svc.preeditText = String(state.preeditText || "");
        svc.preeditCaret = Number(state.preeditCaret) || 0;
        svc.auxVisible = !!state.auxVisible;
        svc.auxText = String(state.auxText || "");
        svc.cursorIndex = Number(state.cursorIndex) >= 0 ? Number(state.cursorIndex) : -1;
        svc.hasPrev = !!state.hasPrev;
        svc.hasNext = !!state.hasNext;
        svc.layout = Number(state.layout) || 0;
        // A var signal can expose the transport's QVariantList as an array-like
        // QML sequence. Array.isArray rejects that sequence and drops every
        // candidate despite the daemon reporting lookupVisible=true.
        const nextCandidates = copyList(state.candidates);
        // Caret/visibility events also carry the table. Keep the Repeater's
        // delegates when only those fields changed.
        if (JSON.stringify(nextCandidates) !== JSON.stringify(svc.candidates))
            svc.candidates = nextCandidates;
        svc.spot = state.spot || ({});
        svc.kwinCaret = state.caret || ({});
        if (svc._popupSessionOpen && !svc._anchorPending
                && svc.kwinCaret.available
                && (!svc.kwinCaret.windowId || svc.kwinCaret.windowId === WindowService.kwinActiveId))
            svc._openingCaret = svc.kwinCaret;
        if (state.imLabel) svc.imLabel = String(state.imLabel);
        if (state.imIcon) svc.imIcon = String(state.imIcon);
        if (state.imName) svc.imName = String(state.imName);
        svc.properties = copyList(state.properties);
        const showing = svc.enabled && svc.visible
            && (svc.lookupVisible || svc.preeditVisible || svc.auxVisible);
        if (showing && !svc._popupSessionOpen)
            svc._beginPopupSession();
        else if (!showing)
            svc._endPopupSession();
        svc._publishPopupState();
    }

    function copyList(value) {
        const result = [];
        if (value && typeof value.length === "number")
            for (let i = 0; i < value.length; ++i) result.push(value[i]);
        return result;
    }

    function _publishPopupState() {
        svc.popupState = {
            enabled: svc.enabled, visible: svc.visible,
            anchorReady: !svc._anchorPending,
            lookupVisible: svc.lookupVisible, candidates: svc.candidates,
            preeditVisible: svc.preeditVisible, preeditText: svc.preeditText,
            auxVisible: svc.auxVisible, auxText: svc.auxText,
            cursorIndex: svc.cursorIndex, layout: svc.layout,
            hasPrev: svc.hasPrev, hasNext: svc.hasNext
        };
    }

    function _beginPopupSession() {
        svc._popupSessionOpen = true;
        const windowId = WindowService.kwinActiveId;

        // If a fresh caret/pointer anchor is already available from the daemon for this window,
        // use it immediately to avoid blank frame latency.
        if (svc.kwinCaret.available
                && (!svc.kwinCaret.windowId || svc.kwinCaret.windowId === windowId)) {
            svc._openingCaret = svc.kwinCaret;
            svc._anchorPending = false;
            svc._anchorDeadline.stop();
            return;
        }

        // Also if explicit spot rect is provided by the client, no need to wait for KWin
        const hasSpot = svc.spot && Number.isFinite(svc.spot.x) && Number.isFinite(svc.spot.y)
            && (svc.spot.x !== 0 || svc.spot.y !== 0);
        if (hasSpot) {
            svc._openingCaret = ({});
            svc._anchorPending = false;
            svc._anchorDeadline.stop();
            return;
        }

        svc._openingCaret = ({});
        svc._anchorPending = true;
        const serial = ++svc._anchorSerial;
        svc._anchorDeadline.restart();
        PlatformClient.request("input.clipboard-anchor", { expectedWindowId: windowId }, function(response) {
            if (serial !== svc._anchorSerial || !svc._anchorPending)
                return;
            // A response for an old focused window must never move this panel.
            if ((!windowId || WindowService.kwinActiveId === windowId) && response?.ok && response?.result?.available)
                svc._openingCaret = response.result || ({});
            svc._anchorDeadline.stop();
            svc._anchorPending = false;
            svc._publishPopupState();
        });
    }

    function _endPopupSession() {
        if (!svc._popupSessionOpen)
            return;
        svc._popupSessionOpen = false;
        ++svc._anchorSerial;
        svc._anchorPending = false;
        svc._anchorDeadline.stop();
    }

    property Timer _anchorDeadline: Timer {
        interval: 180
        onTriggered: {
            // Older bridges still show at the current spot/window fallback.
            svc._anchorPending = false;
            svc._publishPopupState();
        }
    }

    function selectCandidate(index) {
        PlatformClient.request("inputmethod.select-candidate", { index: Number(index) || 0 });
    }

    function pageUp() {
        PlatformClient.request("inputmethod.page-up", {});
    }

    function pageDown() {
        PlatformClient.request("inputmethod.page-down", {});
    }

    function triggerProperty(property) {
        PlatformClient.request("inputmethod.trigger-property", { property: String(property) });
    }

    function configure() {
        PlatformClient.request("inputmethod.configure", {});
    }

    function reloadConfig() {
        PlatformClient.request("inputmethod.reload-config", {});
    }

    function setEnabled(val) {
        PlatformClient.request("inputmethod.set-enabled", { enabled: !!val });
    }

    function toggleInputMethod() {
        // Toggle engine or primary property
        triggerProperty("/Fcitx/im");
    }
}
