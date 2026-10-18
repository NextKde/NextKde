import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.desktop.modules.bar
import qs.desktop.modules.common
import qs.desktop.modules.platform

ShellRoot {
    id: fixture
    property int stage: 0
    property int ticks: 0
    property int checks: 0
    property real summaryHeight: 0
    property real openingHeight: 0
    function check(ok, message) {
        if (!ok) throw new Error("STATUS_PANELS_FAIL: " + message)
        checks++
    }
    function find(node, name) {
        if (node.objectName === name) return node
        for (const child of node.children || []) {
            const match = find(child, name)
            if (match) return match
        }
        return null
    }
    FloatingWindow {
        id: host
        screen: Quickshell.screens.length > 1 ? Quickshell.screens[1] : Quickshell.screens[0]
        implicitWidth: 500; implicitHeight: 700
        Item { id: entry; x: 80; y: 20; width: 40; height: 30 }
        BarStatusArea { id: statusArea; x: 40; y: 100; dockHosted: true }
    }
    BatteryPanel { id: battery }
    NetworkTrafficPanel { id: traffic }
    Timer {
        running: true; repeat: true; interval: 150
        onTriggered: {
            fixture.ticks++
            if (fixture.ticks > 80) throw new Error("STATUS_PANELS_FAIL: timed out")
            if (!ScreenLifecycle.outputAvailable || Quickshell.screens.length < 2) return
            fixture.stage++
            if (fixture.stage === 1) {
                PowerProfileService.platform = PlatformClient
                NetworkService.available = true
                NetworkService.deviceState = "connected"
                NetworkService.deviceName = "test0"
                traffic.toggle(entry)
                fixture.openingHeight = traffic.implicitHeight
                fixture.check(traffic.interactive && traffic.revealProgress === 1,
                    "traffic maps with enabled input and no intermediate scaled frame")
                fixture.check(fixture.openingHeight > 200,
                    "traffic layout has its full summary height before mapping")
            } else if (fixture.stage === 2) {
                fixture.check(traffic.requestedOpen && !traffic.detailsExpanded, "summary opens without process details")
                fixture.check(traffic.implicitHeight === fixture.openingHeight,
                    "traffic summary does not resize after its first layout")
                fixture.check(PlatformClient.applicationRequests === 0, "summary must not sample process traffic")
                fixture.check(traffic.targetScreen === host.screen, "traffic screen follows its secondary-screen anchor")
                fixture.check(battery.targetScreen === ScreenLifecycle.activeScreen, "unanchored battery has fallback")
                NetworkService.trafficSampled("test0",1024,256)
                fixture.check(traffic.downloadHistory[traffic.downloadHistory.length - 1] === 1024, "completed sample updates graph")
                fixture.summaryHeight = traffic.implicitHeight
                traffic.detailsExpanded = true
            } else if (fixture.stage === 3) {
                fixture.check(PlatformClient.applicationRequests === 1, "expanding requests process sample")
                fixture.check(traffic.implicitHeight > fixture.summaryHeight, "expanded details change panel height")
                const rows = find(traffic.contentItem, "traffic-application-list")
                fixture.check(rows !== null && rows.visible, "process rows become visible")
                traffic.detailsExpanded = false
                traffic.refreshApplications()
                fixture.check(PlatformClient.applicationRequests === 1, "collapsed details stop process requests")
                traffic.detailsExpanded = true
                traffic.close()
                fixture.check(traffic.detailsExpanded, "closing preserves expanded layout for exit animation")
                battery.toggle(entry)
            } else if (fixture.stage === 4) {
                fixture.check(battery.targetScreen === host.screen, "battery screen follows secondary-screen anchor")
                fixture.check(PowerProfileService.activeProfile === "balanced", "initial power profile is confirmed")
                PowerProfileService.setProfile("power-saver")
                fixture.check(PowerProfileService.activeProfile === "balanced", "pending switch does not claim success")
            } else if (fixture.stage === 5) {
                fixture.check(PowerProfileService.activeProfile === "power-saver", "readback confirms power profile")
                battery.close()
                traffic.toggle(entry)
                fixture.check(traffic.implicitHeight === fixture.openingHeight,
                    "reopening settles summary geometry before mapping")
            } else if (fixture.stage === 6) {
                fixture.check(!traffic.detailsExpanded, "reopening starts with summary")
                fixture.check(PlatformClient.applicationRequests === 2, "reopening summary does not sample processes")
                traffic.close()
                console.log("STATUS_PANELS_PASS " + fixture.checks + " checks")
                Qt.quit()
            }
        }
    }
}
