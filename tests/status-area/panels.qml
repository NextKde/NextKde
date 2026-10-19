import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.shared.qml.i18n
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
    property bool summaryRendered: false
    property bool detailsRendered: false
    property bool collapsedRendered: false
    function captureFrame(done) {
        const surface = find(traffic.contentItem, "traffic-panel-surface")
        check(surface.grabToImage(function(result) {
            check(String(result.url).length > 0, "traffic frame has image data")
            const captureDir = Quickshell.env("KOS_STATUS_CAPTURE_DIR")
            if (captureDir) check(result.saveToFile(captureDir + "/traffic-" + fixture.stage + ".png"),
                "production native traffic panel capture is saved")
            done()
        }), "traffic frame capture can be scheduled")
    }
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
            if (fixture.ticks > 80) {
                console.error("STATUS_PANELS_FAIL: timed out waiting for stage " + fixture.stage)
                Qt.quit()
                return
            }
            if (!ScreenLifecycle.outputAvailable || Quickshell.screens.length < 2) return
            if ((fixture.stage === 2 && !fixture.summaryRendered)
                || (fixture.stage === 4 && !fixture.detailsRendered)
                || (fixture.stage === 5 && !fixture.collapsedRendered)) return
            fixture.stage++
            if (fixture.stage === 1) {
                I18n.language = "zh-CN"
                PowerProfileService.platform = PlatformClient
                NetworkService.available = true
                NetworkService.deviceState = "connected"
                NetworkService.deviceName = "test0"
                traffic.toggle(entry)
                fixture.openingHeight = traffic.implicitHeight
                fixture.check(traffic.interactive && traffic.revealProgress === 1,
                    "traffic maps with enabled input and no intermediate scaled frame")
                fixture.check(traffic.surfaceHeight > 200,
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
                fixture.check(traffic.nativeView.snapshot.translations.Network === "网络"
                    && traffic.nativeView.snapshot.translations.UP === "已连接",
                    "Chinese catalog reaches native headings and status badges")
                fixture.summaryHeight = traffic.surfaceHeight
                fixture.captureFrame(function() { fixture.summaryRendered = true })
            } else if (fixture.stage === 3) {
                traffic.detailsExpanded = true
            } else if (fixture.stage === 4) {
                fixture.check(PlatformClient.applicationRequests === 1, "expanding requests process sample")
                fixture.check(traffic.surfaceHeight > fixture.summaryHeight, "expanded details change visible panel height")
                fixture.check(traffic.implicitHeight === fixture.openingHeight, "expanding does not resize the Wayland surface")
                const surface = find(traffic.contentItem, "traffic-panel-surface")
                fixture.check(traffic.mask.item === surface && surface.height <= traffic.height,
                    "unused window space is outside the input region")
                fixture.check(traffic.nativeView.detailsExpanded
                    && traffic.nativeView.snapshot.applications.length > 0,
                    "process samples reach the native Forma component tree")
                fixture.check(traffic.nativeView.nativeComponentCount > 100,
                    "the production panel uses original Forma layout and controls")
                fixture.check(traffic.nativeView.renderedPixelSize.width >= traffic.width,
                    "the native target is not a smaller bitmap scaled up")
                fixture.captureFrame(function() { fixture.detailsRendered = true })
            } else if (fixture.stage === 5) {
                I18n.language = "en"
                traffic.detailsExpanded = false
                traffic.refreshApplications()
                fixture.check(PlatformClient.applicationRequests === 1, "collapsed details stop process requests")
                NetworkService.trafficSampled("test0",2048,512)
                fixture.captureFrame(function() { fixture.collapsedRendered = true })
            } else if (fixture.stage === 6) {
                fixture.check(traffic.nativeView.snapshot.translations.Network === "Network",
                    "open native panel follows runtime language changes")
                fixture.check(traffic.surfaceHeight === fixture.summaryHeight, "collapse restores compact card height")
                fixture.check(traffic.implicitHeight === fixture.openingHeight, "collapse preserves Wayland surface size")
                traffic.detailsExpanded = true
                traffic.close()
                fixture.check(traffic.detailsExpanded, "closing preserves expanded layout for exit animation")
                battery.toggle(entry)
            } else if (fixture.stage === 7) {
                fixture.check(battery.targetScreen === host.screen, "battery screen follows secondary-screen anchor")
                fixture.check(PowerProfileService.activeProfile === "balanced", "initial power profile is confirmed")
                PowerProfileService.setProfile("power-saver")
                fixture.check(PowerProfileService.activeProfile === "balanced", "pending switch does not claim success")
            } else if (fixture.stage === 8) {
                fixture.check(PowerProfileService.activeProfile === "power-saver", "readback confirms power profile")
                battery.close()
                traffic.toggle(entry)
                fixture.check(traffic.implicitHeight === fixture.openingHeight,
                    "reopening settles summary geometry before mapping")
            } else if (fixture.stage === 9) {
                fixture.check(!traffic.detailsExpanded, "reopening starts with summary")
                fixture.check(PlatformClient.applicationRequests === 2, "reopening summary does not sample processes")
                traffic.close()
                console.log("STATUS_PANELS_PASS " + fixture.checks + " checks")
                Qt.quit()
            }
        }
    }
}
