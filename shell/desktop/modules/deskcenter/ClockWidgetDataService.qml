import QtQuick
import QtCore
import Quickshell
import qs.desktop.modules.platform
import qs.desktop.modules.common

// Per-instance data adapter for the bundled org.nextkde.example.clock
// package. Also the demo vehicle for the SDK's optional Settings.qml
// convention (see docs/plugins/WidgetSDK.zh-CN.md section 6): format24h is
// the one piece of instance config the example exposes, persisted here
// rather than inside Widget.qml itself, since the view must stay a pure
// function of `data`/`widgetSize`/`appearance`.
QtObject {
    id: root
    property string widgetId: "org.nextkde.example.clock"
    // The desktop can place more than one instance of this package (e.g. two
    // clocks at different sizes), each needing its own widgetSize lookup and
    // its own persisted format24h -- so this must be a per-instance key, not
    // the shared package id. Defaults to widgetId so the gallery preview
    // (which never sets it) keeps working against a single shared file.
    // The host (DeskCenterWindow.qml's widgetCardComponent) pokes this to
    // the card's actual instance id once the content is loaded.
    property string instanceId: widgetId
    property var data: ({ timeText: "--:--", dateText: "" })
    property var widgetSize: [1, 1]
    property string error: ""
    readonly property var packageInfo: WidgetPackageService.packages.find(item => item.id === widgetId) ?? null
    readonly property bool available: packageInfo !== null
    readonly property bool format24h: _settings.format24h

    property Settings _settings: Settings {
        location: "file://" + Quickshell.stateDir + "/example-clock-widget-"
            + encodeURIComponent(root.instanceId) + ".ini"
        category: "Settings"
        property bool format24h: true
    }

    function setFormat24h(value) {
        const next = Boolean(value)
        if (_settings.format24h === next) return
        _settings.format24h = next
        _settings.sync()
        updateTime()
    }

    function updateTime() {
        if (!available) return
        const now = new Date()
        const dateText = Qt.formatDate(now, "yyyy-MM-dd")
        const timeText = root.format24h
            ? Qt.formatTime(now, "HH:mm")
            : Qt.formatTime(now, "h:mm AP")
        if (data.timeText === timeText && data.dateText === dateText) return
        data = { timeText: timeText, dateText: dateText }
    }

    Component.onCompleted: {
        WidgetPackageService.refresh()
        updateTime()
    }
    // QtObject has no default property, so child objects must be declared
    // as named properties rather than bare children.
    property Connections _packageConnections: Connections {
        target: WidgetPackageService
        function onPackagesChanged() { root.updateTime() }
    }
    property Timer _tick: Timer {
        interval: 1000
        repeat: true
        running: root.available
        onTriggered: root.updateTime()
    }
}
