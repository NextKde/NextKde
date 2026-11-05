pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

QtObject {
    id: service
    property var calendar: ({ state: "loading", message: "Loading application data…" })
    property var weather: ({ state: "loading", message: "Loading application data…" })
    property var pending: ({})
    property var opening: ({})
    property var launchErrors: ({})
    property int generation: 0
    property var readRevisions: ({})

    function invalidateRead(key) {
        const revisions = Object.assign({}, readRevisions)
        revisions[key] = (revisions[key] || 0) + 1
        readRevisions = revisions
    }

    function record(key) { return key === "calendar" ? calendar : weather }
    function assign(key, value) {
        if (key === "calendar") calendar = value
        else weather = value
    }
    function feedback(key) {
        if (launchErrors[key]) return I18n.tr(launchErrors[key])
        if (record(key).queryError) return I18n.tr("Application inspection is taking too long; installation state is unknown")
        const messages = {
            loading: "Loading application data…",
            "not-installed": "Install the application to open it",
            ambiguous: "Multiple application installations found; manage them in Settings",
            unavailable: "Application data is unavailable; check the installation and platform service",
            missing: "Application data is missing; open the app to update it",
            invalid: "Application data is invalid; open the app to update it",
            unsupported: "This application or storage profile does not support widgets",
            stale: "Cached data; open the application to update"
        }
        return I18n.tr(messages[record(key).state] || "")
    }
    function launchMessage(response, fallback) {
        const messages = {
            "widget-query-timeout": "Application inspection is taking too long; installation state is unknown",
            "widget-query-busy": "Application inspection is taking too long; installation state is unknown",
            "source-changed": "Application source changed; refresh the widget",
            busy: "Application launch is already in progress",
            "settings-navigation-failed": "Settings did not confirm navigation; try again",
            "settings-unavailable": "Application Settings is unavailable",
            "application-launch-failed": "Could not open application"
        }
        return messages[response?.error?.code] || fallback
    }
    function setError(key, value) {
        const next = Object.assign({}, launchErrors)
        next[key] = value
        launchErrors = next
    }
    function reload(key) {
        if (pending[key] || !PlatformClient.connected) return
        const epoch = generation
        const revision = readRevisions[key] || 0
        const next = Object.assign({}, pending)
        next[key] = true
        pending = next
        PlatformClient.request("application.widget-snapshot", { app: key }, function(response) {
            if (epoch !== generation) return
            const done = Object.assign({}, service.pending)
            delete done[key]
            service.pending = done
            if (revision !== (service.readRevisions[key] || 0)) {
                service.reload(key)
                return
            }
            const result = response?.ok ? response.result : {
                state: "unavailable", message: String(response?.error?.message || "Application data is unavailable"),
                queryError: response?.error?.code === "widget-query-timeout" || response?.error?.code === "widget-query-busy"
            }
            service.assign(key, result)
        })
    }
    function manage(key) {
        if (opening[key]) return
        const epoch = generation
        const busy = Object.assign({}, opening)
        busy[key] = true
        opening = busy
        PlatformClient.request("settings.launch", { shellDir: Quickshell.shellDir, app: key }, function(response) {
            if (epoch !== service.generation) return
            const done = Object.assign({}, service.opening)
            delete done[key]
            service.opening = done
            if (!response?.ok)
                service.setError(key, service.launchMessage(response, "Could not open application Settings"))
        })
    }
    function open(key, options) {
        if (opening[key]) return
        setError(key, "")
        if (!PlatformClient.connected) {
            setError(key, "Platform service is disconnected")
            return
        }
        const item = record(key)
        if (item.state === "not-installed" || item.state === "ambiguous" || item.state === "unavailable") {
            manage(key)
            return
        }
        if (!item.installed || !item.sourceToken) {
            setError(key, "Application state is not ready; try again")
            reload(key)
            return
        }
        // Item/location ids only make sense with the currently displayed source.
        const parameters = Object.assign({}, options || {})
        if (item.state !== "ready" && item.state !== "stale") {
            delete parameters.item
            delete parameters.location
        }
        const next = Object.assign({}, opening)
        next[key] = true
        opening = next
        const epoch = generation
        invalidateRead(key)
        PlatformClient.request("application.widget-open", {
            app: key, sourceToken: item.sourceToken, options: parameters
        }, function(response) {
            if (epoch !== generation) return
            const done = Object.assign({}, service.opening)
            delete done[key]
            service.opening = done
            // A poll started before this launch result must not restore a
            // source rejected by the launcher's fresh installation check.
            service.invalidateRead(key)
            if (!response?.ok && service.record(key).sourceToken === item.sourceToken) {
                service.setError(key, service.launchMessage(response, "Could not open application"))
                service.assign(key, { state: "loading", message: service.feedback(key) })
            }
            service.reload(key)
        })
    }
    property Timer poll: Timer {
        interval: 30000
        repeat: true
        running: PlatformClient.connected
        triggeredOnStart: true
        onTriggered: { service.reload("calendar"); service.reload("weather") }
    }
    property Connections transport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            service.generation++
            service.pending = ({})
            service.opening = ({})
            service.calendar = ({ state: "unavailable", message: "Application data is reconnecting" })
            service.weather = ({ state: "unavailable", message: "Application data is reconnecting" })
            if (connected) { service.reload("calendar"); service.reload("weather") }
        }
    }
    property Connections catalog: Connections {
        target: AppPresentationService
        function onCatalogRevisionChanged() {
            service.generation++
            service.pending = ({})
            service.opening = ({})
            service.calendar = ({ state: "loading", message: "Application installation changed" })
            service.weather = ({ state: "loading", message: "Application installation changed" })
            service.reload("calendar")
            service.reload("weather")
        }
    }
}
