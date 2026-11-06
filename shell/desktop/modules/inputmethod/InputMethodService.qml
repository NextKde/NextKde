pragma Singleton

import QtQuick
import Quickshell
import qs.desktop.modules.platform
import qs.desktop.modules.dock
import "InputMethodPlacement.mjs" as Placement

QtObject {
    id: svc

    property bool available: PlatformClient.supports("inputmethod.kimpanel")
    property bool enabled: true
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

    signal menuReceived(var items)

    readonly property var activeWindow: {
        const activeId = WindowService.kwinActiveId;
        if (!activeId) return null;
        const records = WindowService.records;
        for (let i = 0; i < records.length; ++i) {
            if (records[i].id === activeId) return records[i];
        }
        return null;
    }

    readonly property var globalAnchor: Placement.resolveGlobalSpotRect(
        spot,
        activeWindow,
        kwinCaret,
        Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    )

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
        svc.enabled = state.enabled !== false;
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
        svc.candidates = Array.isArray(state.candidates) ? state.candidates : [];
        svc.spot = state.spot || ({});
        svc.kwinCaret = state.caret || ({});
        if (state.imLabel) svc.imLabel = String(state.imLabel);
        if (state.imIcon) svc.imIcon = String(state.imIcon);
        if (state.imName) svc.imName = String(state.imName);
        if (Array.isArray(state.properties)) svc.properties = state.properties;
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
