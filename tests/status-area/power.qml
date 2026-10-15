import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.desktop.modules.bar

Item {
    id: test
    property int stage: 0
    property var originalModel: null
    QtObject {
        id: nativePower
        property int profile: PowerProfile.Balanced
        property bool hasPerformanceProfile: true
        property int degradationReason: PerformanceDegradationReason.None
    }
    QtObject {
        id: fakePlatform
        property string current: "balanced"
        property bool failWrite: false
        property bool holdRead: false
        property bool rejectMode: false
        property var delayed: null
        function request(operation, payload, callback) {
            if (operation === "power.profile.set") {
                if (!failWrite && !rejectMode) current = payload.profile
                const success = !failWrite
                Qt.callLater(() => callback({ok: success, result: {}}))
            } else {
                const snapshot = {ok:true, result:{activeProfile:current, profiles:["power-saver","balanced","performance"], degraded:""}}
                if (holdRead) delayed = () => callback(snapshot)
                else Qt.callLater(() => callback(snapshot))
            }
        }
    }
    BatteryPanel { id: battery }
    NetworkTrafficPanel { id: traffic }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) { const found = find(child,name); if (found) return found }
        return null
    }
    function check(value, message) {
        if (!value) { console.error("POWER_PANEL_FAIL: " + message); Qt.quit() }
    }
    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            test.stage++
            if (test.stage === 1) {
                PowerProfileService.platform = fakePlatform
                PowerProfileService.systemProfiles = nativePower
                PowerProfileService.refresh()
                traffic.applicationRows = [{name:"browser",download:100,upload:20},{name:"mail",download:10,upload:2}]
            } else if (test.stage === 2) {
                test.check(PowerProfileService.activeProfile === "balanced", "initial mode")
                test.check(test.find(battery.contentItem,"power-mode-balanced").selected, "initial checkmark")
                PowerProfileService.setProfile("power-saver")
                test.check(PowerProfileService.changing && PowerProfileService.pendingProfile === "power-saver", "pending mode")
                const list = test.find(traffic.contentItem,"traffic-application-list")
                test.originalModel = list.model
                traffic.applicationRows = [{name:"browser",download:200,upload:40},{name:"mail",download:15,upload:5}]
            } else if (test.stage === 3) {
                test.check(PowerProfileService.activeProfile === "power-saver", "write ack updates mode")
                test.check(test.find(battery.contentItem,"power-mode-power-saver").selected, "checkmark follows ack")
                const list = test.find(traffic.contentItem,"traffic-application-list")
                test.check(list.model === test.originalModel && list.model.get(0).download === 200, "application model replaced")
                fakePlatform.failWrite = true
                PowerProfileService.setProfile("performance")
            } else if (test.stage === 4) {
                test.check(PowerProfileService.activeProfile === "power-saver" && PowerProfileService.error.length > 0, "failed mode shows false selection")
                nativePower.profile = PowerProfile.Performance
            } else if (test.stage === 5) {
                test.check(PowerProfileService.activeProfile === "performance", "external system change ignored")
                test.check(test.find(battery.contentItem,"power-mode-performance").selected, "external checkmark")
                fakePlatform.holdRead = true
                fakePlatform.current = "balanced"
                PowerProfileService.refresh()
                nativePower.profile = PowerProfile.PowerSaver
                fakePlatform.delayed()
            } else if (test.stage === 6) {
                test.check(PowerProfileService.activeProfile === "power-saver", "stale read overwrote system signal")
                test.check(test.find(battery.contentItem,"power-mode-power-saver").selected, "stale checkmark")
                traffic.applicationRows = [{name:"mail",download:300,upload:5},{name:"browser",download:20,upload:1}]
            } else if (test.stage === 7) {
                const list = test.find(traffic.contentItem,"traffic-application-list")
                test.check(list.model === test.originalModel && list.model.get(0).name === "mail", "reordering replaced model")
                fakePlatform.holdRead = false
                fakePlatform.failWrite = false
                fakePlatform.rejectMode = true
                fakePlatform.current = "power-saver"
                PowerProfileService.setProfile("balanced")
            } else if (test.stage === 8) {
                test.check(PowerProfileService.activeProfile === "power-saver" && PowerProfileService.error.length > 0, "silent system rejection shows false checkmark")
                console.error("POWER_PANEL_PASS")
                Qt.quit()
            }
        }
    }
}
