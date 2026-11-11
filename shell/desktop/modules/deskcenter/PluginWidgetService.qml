pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

QtObject {
    id: service
    property var plugins: []
    property var instances: []
    property int revision: 0
    property string error: ""
    property bool loading: false
    property bool mutating: false
    property bool available: false
    property int generation: 0
    property int readSerial: 0
    readonly property bool connected: PlatformClient.connected

    // Normalize QVariant/QV4 sequences at the IPC boundary, once. No caller
    // interprets manifest view data: only resolved instance views are rendered.
    function plain(value, fallback) {
        try { return JSON.parse(JSON.stringify(value)) ?? fallback } catch (_) { return fallback }
    }
    function accept(snapshot) {
        const data = plain(snapshot, {})
        const nextPlugins = Array.isArray(data.plugins) ? data.plugins : []
        const nextInstances = Array.isArray(data.instances) ? data.instances : []
        if (JSON.stringify(plugins) !== JSON.stringify(nextPlugins)) plugins = nextPlugins
        if (JSON.stringify(instances) !== JSON.stringify(nextInstances)) instances = nextInstances
        revision++
        available = true
        // Catalog verification belongs to Plugin Center. A successful local
        // snapshot keeps installed/builtin widgets usable even when remote
        // discovery fails; only transport or instance mutations set error.
        error = ""
    }
    function refresh() {
        if (!connected || loading || mutating) return
        if (PlatformClient.capabilityProbeComplete && !PlatformClient.supports("plugin.snapshot")) {
            available = false
            error = I18n.tr("Desktop plugins are not supported by this platform service")
            return
        }
        loading = true
        const epoch = generation
        const serial = ++readSerial
        PlatformClient.request("plugin.snapshot", {}, function(response) {
            if (epoch !== service.generation || serial !== service.readSerial) return
            service.loading = false
            if (response?.ok) service.accept(response.result)
            else {
                service.available = false
                service.error = String(response?.error?.message || I18n.tr("Could not load desktop plugins"))
                service.instances = service.instances.map(item => Object.assign({}, item,
                    {state: "unavailable", message: service.error, view: {}}))
            }
        })
    }
    function mutate(operation, payload, callback) {
        if (!connected || mutating) {
            error = I18n.tr(connected ? "A widget change is still being saved" : "Platform service is disconnected")
            if (callback) callback(false, null)
            return
        }
        ++readSerial
        loading = false
        mutating = true
        error = ""
        const epoch = generation
        PlatformClient.request(operation, payload, function(response) {
            if (epoch !== service.generation) {
                if (callback) callback(false, null)
                return
            }
            service.mutating = false
            if (response?.ok) service.accept(response.result)
            else service.error = String(response?.error?.message || I18n.tr("Could not save widget changes"))
            if (callback) callback(!!response?.ok, response?.result || null)
        })
    }
    function instance(id) {
        for (const item of instances) if (item.id === id) return item
        return null
    }
    function add(pluginId, widgetId, size, callback) {
        mutate("plugin.instance-add", {pluginId, widgetId, size}, callback)
    }
    function remove(id, callback) {
        mutate("plugin.instance-remove", {instanceId: id}, callback)
    }
    function configure(id, patch, callback) {
        mutate("plugin.instance-configure", Object.assign({instanceId: id}, patch), callback)
    }
    function action(id, actionId) {
        const item = instance(id)
        if (!available || !item || ["ready", "permission-required"].indexOf(item.state) < 0) return
        mutate("plugin.instance-action", {instanceId: id, actionId})
    }
    function openCenter() {
        PlatformClient.request("settings.launch", {shellDir: Quickshell.shellDir, app: "plugins"}, function(response) {
            if (!response?.ok)
                service.error = String(response?.error?.message || I18n.tr("Could not open Plugin Center"))
        })
    }
    property Timer poll: Timer {
        interval: 10000
        repeat: true
        running: PlatformClient.connected
        triggeredOnStart: true
        onTriggered: service.refresh()
    }
    property Connections transport: Connections {
        target: PlatformClient
        function onTransportChanged(connected) {
            service.generation++
            service.readSerial++
            service.loading = false
            service.mutating = false
            service.available = false
            // Retain geometry and names while reconnecting, never live values.
            service.instances = service.instances.map(item => Object.assign({}, item,
                {state: "unavailable", message: I18n.tr("Platform service is disconnected"), view: {}}))
            if (connected) service.refresh()
        }
    }
}
