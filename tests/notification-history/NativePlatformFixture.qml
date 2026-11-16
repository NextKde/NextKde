pragma Singleton
import QtQuick

// Deterministic, read-only render data. The visual fixture never connects to
// the user's platform daemon or receives their active-window/focus events.
QtObject {
    property QtObject socket: QtObject { property bool connected: true }
    readonly property bool connected: true
    property bool enabled: true
    property var capabilities: ["keepawake"]
    property bool capabilityProbeComplete: true
    function supports(operation) { return capabilities.indexOf(String(operation)) >= 0 }
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)
    function request(operation, payload, callback) {
        let result = {available:false}
        switch (operation) {
        case "state.read": result={exists:false,data:""}; break
        case "state.write": result={}; break
        case "audio.get": result={available:true,percent:45,muted:false}; break
        case "audio.applications": result={available:true,applications:[]}; break
        case "bluetooth.list": result={available:true,powered:true,devices:[]}; break
        case "display.brightness.get": result={available:true,percent:80,device:"sample",displays:[]}; break
        case "network.refresh": result={available:true,wifiEnabled:true,connectionType:"wifi",deviceState:"connected",
            connectivity:"full",deviceName:"wlan-sample",wifiDeviceName:"wlan-sample",ssid:"Home",connectionName:"Home"}; break
        case "network.details": result={ipv4:"192.0.2.1",signalStrength:88}; break
        case "network.traffic": result={rxBytes:0,txBytes:0}; break
        case "nightlight.get": result={available:true,enabled:false}; break
        case "keepawake.get": result={available:true,enabled:false}; break
        case "kwin.subscribe": case "kwin.command": result={}; break
        }
        if (callback) Qt.callLater(function() { callback({ok:true,result:result}) })
        return "fixture"
    }
}
