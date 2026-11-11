pragma Singleton
import QtQuick
import Quickshell
import qs.desktop.modules.platform
import qs.desktop.modules.stage
import qs.desktop.modules.dock

QtObject {
    id: service
    property bool enabled: false
    property bool ready: false
    property bool changing: false
    property string error: ""
    property bool open: false
    property string session: ""
    property double sequence: -1
    property var windows: []
    property string selectedHandle: ""
    property var screenGeometry: ({})
    readonly property string configPath: Quickshell.stateDir + "/switcher/config.json"

    function snapshot() {
        return { enabled: enabled, changing: changing, error: error }
    }

    function setEnabled(value) {
        if (!ready || changing)
            return
        changing = true
        error = ""
        if (!value)
            open = false
        // Join the shell's single kwinrc writer queue; parallel writers lose keys.
        StageConfigService.enqueueBashChain([
            "python3", Qt.resolvedUrl("configure.py").toString().replace(/^file:\/\//, ""),
            value ? "true" : "false",
            Qt.resolvedUrl("tabbox").toString().replace(/^file:\/\//, ""),
            Quickshell.stateDir + "/switcher/native-layout.json"
        ], function(ok) {
            changing = false
            if (!ok) {
                error = "Could not change the window switcher layout"
                return
            }
            enabled = value
            JsonConfigStore.writePath(configPath, JSON.stringify({ enabled: enabled }))
        })
    }

    function consume(event) {
        if (!enabled || !event || Number(event.sequence) <= sequence)
            return
        sequence = Number(event.sequence)
        if (!event.visible) {
            open = false
            lease.stop()
            return
        }
        const newSession = session !== event.session
        if (newSession) {
            session = String(event.session)
            const rows = []
            const handles = event.handles || []
            for (let i = 0; i < handles.length; ++i) {
                const handle = String(handles[i])
                const record = WindowService.records.find(row => row.handleId === handle)
                rows.push({ handleId: handle, windowId: record?.windowId || "",
                    title: record?.title || "Window", iconSource: record?.iconSource || "" })
            }
            // Identity snapshot lasts for the whole chord: revision/thumbnail
            // events never recreate delegates or move cards underneath selection.
            windows = rows
            screenGeometry = event.screen || ({})
        }
        selectedHandle = String(event.selected || "")
        open = windows.length > 0
        lease.restart()
    }

    property Timer lease: Timer {
        interval: 800
        onTriggered: service.open = false
    }
    property Connections events: Connections {
        target: PlatformClient
        function onEventReceived(name, payload) {
            if (name === "switcher")
                service.consume(payload)
        }
        function onTransportChanged(connected) {
            service.open = false
            service.sequence = -1
        }
    }
    Component.onCompleted: JsonConfigStore.readPath(configPath, function(data) {
        let wanted = false
        try { wanted = JSON.parse(data || "{}").enabled === true } catch (e) { /* Default off. */ }
        service.ready = true
        // Also recovers an interrupted disable using the durable native backup.
        service.setEnabled(wanted)
    })
}
