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
    property bool batteryRendered: false
    property real batteryOpeningHeight: 0
    property int batteryReadsOnClose: 0
    QtObject {
        id: sampleBattery
        property bool ready: true
        property bool isPresent: true
        property bool isLaptopBattery: true
        property int state: UPowerDeviceState.FullyCharged
        property real percentage: 0.8
        property bool healthSupported: true
        property real healthPercentage: 0.9
        property real changeRate: 0
        property real energyCapacity: 49.5
        property real energy: 30
        property real timeToFull: 1800
        property real timeToEmpty: 3600
    }
    function captureBatteryFrame() {
        const surface = find(battery.contentItem, "battery-panel-surface")
        check(surface.grabToImage(function(result) {
            check(String(result.url).length > 0, "battery frame has image data")
            const captureDir = Quickshell.env("KOS_STATUS_CAPTURE_DIR")
            if (captureDir) check(result.saveToFile(captureDir + "/battery.png"), "battery capture is saved")
            PowerProfileService.setProfile("power-saver")
            fixture.check(PowerProfileService.activeProfile === "balanced", "pending switch does not claim success")
            fixture.batteryRendered = true
        }), "battery frame capture can be scheduled")
    }
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
    }
    BatteryPanel { id: battery; battery: sampleBattery; batteryPowered: false }
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
                || (fixture.stage === 5 && !fixture.collapsedRendered)
                || (fixture.stage === 7 && !fixture.batteryRendered)) return
            fixture.stage++
            if (fixture.stage === 1) {
                const previewStyle = Quickshell.env("KOS_STATUS_TEST_STYLE")
                const previewTheme = Quickshell.env("KOS_STATUS_TEST_THEME")
                if (previewStyle) AppearanceConfigService.shellStyle = previewStyle
                if (previewTheme) AppearanceConfigService.themeMode = previewTheme
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
                const heading = fixture.find(traffic.contentItem, "traffic-heading")
                const statusPill = fixture.find(traffic.contentItem, "traffic-status-pill")
                fixture.check(heading !== null && heading.text === "网络",
                    "Chinese catalog reaches the panel heading")
                fixture.check(statusPill !== null && statusPill.text === "已连接",
                    "Chinese catalog reaches the status badge")
                fixture.summaryHeight = traffic.surfaceHeight
                fixture.captureFrame(function() { fixture.summaryRendered = true })
            } else if (fixture.stage === 3) {
                traffic.detailsExpanded = true
            } else if (fixture.stage === 4) {
                fixture.check(PlatformClient.applicationRequests === 1, "expanding requests process sample")
                fixture.check(traffic.surfaceHeight >= fixture.summaryHeight
                    && traffic.surfaceHeight === Math.min(924, traffic.height),
                    "expanded details grow until constrained by screen height")
                fixture.check(traffic.implicitHeight === fixture.openingHeight, "expanding does not resize the Wayland surface")
                const surface = find(traffic.contentItem, "traffic-panel-surface")
                fixture.check(traffic.mask.item === surface && surface.height <= traffic.height,
                    "unused window space is outside the input region")
                fixture.check(traffic.detailsExpanded && traffic.processModel.count > 0,
                    "process samples reach the QML panel model")
                const chart = fixture.find(traffic.contentItem, "traffic-chart")
                const grid = fixture.find(traffic.contentItem, "traffic-connectivity-grid")
                const processList = fixture.find(traffic.contentItem, "traffic-process-list")
                fixture.check(chart !== null && grid !== null && processList !== null,
                    "the production panel renders its chart, connectivity grid and process list")
                fixture.check(traffic.implicitWidth === 280,
                    "the QML card keeps the native 280 px width")
                fixture.captureFrame(function() { fixture.detailsRendered = true })
            } else if (fixture.stage === 5) {
                I18n.language = "en"
                traffic.detailsExpanded = false
                traffic.refreshApplications()
                fixture.check(PlatformClient.applicationRequests === 1, "collapsed details stop process requests")
                fixture.check(traffic.processModel.count === 0, "collapsing releases the process delegates")
                NetworkService.trafficSampled("test0",2048,512)
                fixture.captureFrame(function() { fixture.collapsedRendered = true })
            } else if (fixture.stage === 6) {
                const reopenedHeading = fixture.find(traffic.contentItem, "traffic-heading")
                fixture.check(reopenedHeading !== null && reopenedHeading.text === "Network",
                    "open panel follows runtime language changes")
                fixture.check(traffic.surfaceHeight === fixture.summaryHeight, "collapse restores compact card height")
                fixture.check(traffic.implicitHeight === fixture.openingHeight, "collapse preserves Wayland surface size")
                traffic.detailsExpanded = true
                traffic.close()
                fixture.check(traffic.detailsExpanded, "closing preserves expanded layout for exit animation")
                battery.toggle(entry)
            } else if (fixture.stage === 7) {
                fixture.check(battery.targetScreen === host.screen, "battery screen follows secondary-screen anchor")
                fixture.batteryOpeningHeight = battery.implicitHeight
                fixture.check(battery.implicitWidth === 280, "battery matches the native traffic card width")
                fixture.check(PlatformClient.batteryRequests === 1, "battery hardware is read only on open")
                const body = fixture.find(battery.contentItem, "battery-panel-body")
                fixture.check(body !== null && body.hasBattery && !body.charging, "fully charged is not actively charging")
                fixture.check(fixture.find(battery.contentItem, "battery-full-capacity").text === "4500 mAh", "native full capacity reaches the card")
                fixture.check(fixture.find(battery.contentItem, "battery-adapter-power").text === "12.29 W / 65 W", "adapter actual and rated power are distinct")
                fixture.check(fixture.find(battery.contentItem, "battery-power").text === "0.00 W", "zero battery power is a valid measurement")
                fixture.check(body.runtimeText === "Unplug to estimate", "AC power does not use a stale discharge estimate")
                const footer = fixture.find(battery.contentItem, "battery-power-modes")
                fixture.check(footer.y + footer.height <= battery.surfaceHeight, "power modes remain inside the visible card")
                for (const key of ["power-saver", "balanced", "performance"])
                    fixture.check(fixture.find(battery.contentItem, "power-mode-" + key) !== null, "power mode retained: " + key)
                I18n.language = "zh-CN"
                fixture.captureBatteryFrame()
                fixture.check(PowerProfileService.activeProfile === "balanced", "initial power profile is confirmed")
            } else if (fixture.stage === 8) {
                I18n.language = "en"
                fixture.check(PowerProfileService.activeProfile === "power-saver", "readback confirms power profile")
                sampleBattery.state = UPowerDeviceState.PendingCharge
            } else if (fixture.stage === 9) {
                const body = fixture.find(battery.contentItem, "battery-panel-body")
                fixture.check(body.statusText === "On hold" && !body.charging, "pending charge is paused, not charging")
                fixture.check(body.timeText === "On hold", "paused charging has no invented countdown")
                sampleBattery.state = UPowerDeviceState.Charging
            } else if (fixture.stage === 10) {
                const body = fixture.find(battery.contentItem, "battery-panel-body")
                fixture.check(body.charging && body.statusText === "Charging", "charging state follows UPower")
                fixture.check(body.timeText === "0 h 30 min", "charging shows time to full")
                sampleBattery.state = UPowerDeviceState.Discharging
                sampleBattery.percentage = 0.12
                battery.batteryPowered = true
            } else if (fixture.stage === 11) {
                const body = fixture.find(battery.contentItem, "battery-panel-body")
                fixture.check(body.statusText === "On battery" && body.timeText === "1 h 0 min", "discharging shows remaining time")
                fixture.check(fixture.find(battery.contentItem, "battery-runtime").text === "1 h 0 min", "dedicated runtime row uses the system estimate")
                fixture.check(body.fillColor.toString() === "#ff453a", "low battery uses the warning fill")
                fixture.check(!fixture.find(battery.contentItem, "battery-adapter-section").visible, "unplugging hides adapter details")
                fixture.check(battery.implicitHeight === fixture.batteryOpeningHeight, "charge state changes preserve the Wayland allocation")
                PowerProfileService.setProfile("performance")
                sampleBattery.timeToEmpty = 0
                sampleBattery.changeRate = 10
            } else if (fixture.stage === 12) {
                fixture.check(fixture.find(battery.contentItem, "battery-runtime").text === "3 h 0 min", "runtime falls back to remaining energy and discharge power")
                fixture.check(PowerProfileService.activeProfile === "performance", "performance mode confirms in the new panel")
                PowerProfileService.setProfile("balanced")
                sampleBattery.changeRate = 0
            } else if (fixture.stage === 13) {
                fixture.check(fixture.find(battery.contentItem, "battery-runtime").text === "Calculating…", "zero discharge power shows an honest pending estimate")
                fixture.check(PowerProfileService.activeProfile === "balanced", "balanced mode confirms in the new panel")
                I18n.language = "zh-CN"
                sampleBattery.ready = false
                battery.hardware = ({})
            } else if (fixture.stage === 14) {
                const body = fixture.find(battery.contentItem, "battery-panel-body")
                fixture.check(body.statusText === "未检测到电池", "missing battery has a localized fallback")
                fixture.check(fixture.find(battery.contentItem, "battery-percentage").text === "—", "missing battery does not report zero percent")
                fixture.check(fixture.find(battery.contentItem, "battery-heading").text === "电池", "battery follows language changes")
                battery.close()
                fixture.batteryReadsOnClose = PlatformClient.batteryRequests
                battery.refreshHardware()
                traffic.toggle(entry)
                fixture.check(traffic.implicitHeight === fixture.openingHeight,
                    "reopening settles summary geometry before mapping")
            } else if (fixture.stage === 15) {
                fixture.check(PlatformClient.batteryRequests === fixture.batteryReadsOnClose, "closed battery panel does not sample hardware")
                fixture.check(Object.keys(battery.hardware).length === 0, "closing releases hardware snapshot")
                fixture.check(!traffic.detailsExpanded, "reopening starts with summary")
                fixture.check(PlatformClient.applicationRequests === 2, "reopening summary does not sample processes")
                traffic.close()
                console.log("STATUS_PANELS_PASS " + fixture.checks + " checks")
                Qt.quit()
            }
        }
    }
}
