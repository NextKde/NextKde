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
    property int applicationRequests: 0
    property int batteryRequests: 0
    property string powerMode: "balanced"
    // Deliberately exceed a panel-test tick: profile assertions must wait for
    // write/readback completion instead of depending on one fast event loop.
    property Timer profileReply: Timer {
        interval: 220
        property var replies: []
        onTriggered: {
            const pending = replies
            replies = []
            for (const reply of pending) reply()
        }
    }
    function request(operation, payload, callback) {
        let result = {available:false}
        switch (operation) {
        case "network.applications": applicationRequests++; result={sockets:[{id:"1",name:"browser",pid:1,rxBytes:100*applicationRequests,txBytes:20*applicationRequests}]}; break
        case "power.profiles": result={profiles:["power-saver","balanced","performance"],activeProfile:powerMode,degraded:""}; break
        case "power.profile.set": powerMode=payload.profile; result={}; break
        case "power.battery": batteryRequests++; result={available:true,complete:true,
            batteries:[{name:"BAT0",chargeFullMah:4500,chargeDesignMah:5000,
                voltage:12,currentMa:0,powerWatts:0,cycles:193,temperature:32}],
            adapters:[{name:"AC"},{name:"USB",powerWatts:12.29,ratedPowerWatts:65,currentMa:614.5,voltage:20}]}; break
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
        if (callback) {
            const reply = function() { callback({ok:true,result:result}) }
            if (operation === "power.profiles" || operation === "power.profile.set") {
                profileReply.replies = profileReply.replies.concat([reply])
                profileReply.start()
            } else Qt.callLater(reply)
        }
        return "fixture"
    }
}
