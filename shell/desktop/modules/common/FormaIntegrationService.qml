pragma Singleton
import QtQuick
import qs.desktop.modules.platform
import "FormaApplications.mjs" as FormaApplications

QtObject {
    id: service
    property var state: ({ready: false, enabled: false, busy: false, applications: [], error: ""})
    property bool requestInFlight: false

    function snapshot() { return state; }
    function preferredId(role) { return FormaApplications.preferredId(state, role); }
    function resolvePinnedId(id) { return FormaApplications.resolvePinnedId(state, id); }

    function fail(message) {
        pendingEnabled = null;
        requestInFlight = false;
        state = Object.assign({}, state, {available: false, ready: false, busy: false, error: message});
    }

    function consume(response) {
        requestInFlight = false;
        const result = response?.result;
        if (!response?.ok) {
            fail(response?.error?.message || "Platform service is disconnected");
            return;
        }
        if (!result || typeof result.ready !== "boolean" || typeof result.enabled !== "boolean"
            || !Array.isArray(result.applications)) {
            fail("The desktop environment returned invalid Forma preferences");
            return;
        }
        state = Object.assign({}, result, {busy: pendingEnabled !== null});
        if (pendingEnabled !== null) {
            const enabled = pendingEnabled;
            pendingEnabled = null;
            setEnabled(enabled);
        }
    }

    function refresh() {
        if (requestInFlight)
            return;
        if (!PlatformClient.connected) {
            fail("Platform service is disconnected");
            return;
        }
        requestInFlight = true;
        PlatformClient.request("integration.forma.get", {}, function(response) { service.consume(response); });
    }

    function setEnabled(enabled) {
        // A refresh may already be queued by the Settings snapshot. Finish it
        // before the write rather than dropping a user's toggle.
        if (requestInFlight) {
            pendingEnabled = enabled;
            state = Object.assign({}, state, {busy: true});
            return;
        }
        if (!PlatformClient.connected) {
            fail("Platform service is disconnected");
            return;
        }
        requestInFlight = true;
        state = Object.assign({}, state, {busy: true, error: ""});
        PlatformClient.request("integration.forma.set", {enabled: enabled},
            function(response) { service.consume(response); });
    }

    property var pendingEnabled: null
    property Connections transport: Connections {
        target: PlatformClient
        function onConnectedChanged() {
            if (PlatformClient.connected)
                Qt.callLater(service.refresh);
            else
                service.fail("Platform service is disconnected");
        }
    }
    Component.onCompleted: Qt.callLater(refresh)
}
