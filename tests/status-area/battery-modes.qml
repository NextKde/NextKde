import QtQuick
import Quickshell
import qs.shared.qml.i18n
import qs.desktop.modules.bar
import qs.desktop.modules.common

// VM-only real popup geometry regression; no writes to the host power daemon.
ShellRoot {
    id: fixture
    property int stage: -1
    property int ticks: 0
    property int checks: 0
    property var geometry: null
    property bool capturing: false
    readonly property var states: [
        {profile: "balanced"},
        {profile: "performance", degraded: "high-operating-temperature"},
        {profile: "balanced"},
        {profile: "performance", degraded: "high-operating-temperature"},
        {changing: true, pending: "balanced", degraded: "high-operating-temperature"},
        {pending: "balanced"},
        {loading: true},
        {error: "Permission denied. ".repeat(30), degraded: "high-operating-temperature"},
        {degraded: "high-operating-temperature ".repeat(30)},
        {profile: "power-saver", language: "zh-CN"},
        {profile: "performance", language: "zh-CN", degraded: "high-operating-temperature"},
        {profile: "balanced", language: "en"}
    ]
    function find(node, name) {
        if (node.objectName === name) return node
        for (const child of node.children || []) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function check(ok, message) {
        if (!ok) {
            timer.stop()
            console.error("STATUS_PANELS_FAIL: stage " + stage + ": " + message)
            Qt.quit()
            throw new Error(message)
        }
        checks++
    }
    function applyState(state) {
        I18n.language = state.language || "en"
        PowerProfileService.activeProfile = state.profile || "balanced"
        PowerProfileService.profiles = state.loading ? [] : ["power-saver", "balanced", "performance"]
        PowerProfileService.loading = !!state.loading
        PowerProfileService.changing = !!state.changing
        PowerProfileService.pendingProfile = state.pending || ""
        PowerProfileService.error = state.error || ""
        PowerProfileService.degraded = state.degraded || ""
    }
    function captureFrame() {
        const directory = Quickshell.env("KOS_STATUS_CAPTURE_DIR")
        if (!directory) return
        const name = directory + "/battery-mode-" + stage + ".png"
        capturing = true
        check(find(battery.contentItem, "battery-panel-surface").grabToImage(function(result) {
            fixture.check(result.saveToFile(name), "status frame is saved")
            fixture.capturing = false
            fixture.applyState(fixture.states[fixture.stage])
        }), "status frame capture is scheduled")
    }
    FloatingWindow {
        id: host
        implicitWidth: 500; implicitHeight: 700
        Item { id: entry; x: 80; y: 20; width: 40; height: 30 }
    }
    BatteryPanel { id: battery; battery: null; batteryPowered: true }
    Timer {
        id: timer
        interval: 180; running: true; repeat: true
        onTriggered: {
            if (++fixture.ticks > 100) {
                fixture.check(false, "timed out")
                return
            }
            if (!ScreenLifecycle.outputAvailable) return
            if (fixture.capturing) return
            if (fixture.stage === -1) {
                PowerProfileService.systemProfiles = null
                fixture.applyState(fixture.states[0])
                battery.anchorItem = entry
                battery.show()
                fixture.stage = 0
                return
            }
            if (!battery.interactive || battery.revealProgress < 1) return
            const footer = fixture.find(battery.contentItem, "battery-power-modes")
            const current = [battery.width, battery.height, footer.y]
            if (fixture.geometry === null) fixture.geometry = current
            console.log("BATTERY_MODE_GEOMETRY", fixture.stage, JSON.stringify(current))
            fixture.check(JSON.stringify(current) === JSON.stringify(fixture.geometry),
                "window size and mode button position stay fixed: " + JSON.stringify(current)
                    + " expected " + JSON.stringify(fixture.geometry))
            const message = fixture.find(battery.contentItem, "battery-mode-status")
            fixture.check(message !== null, "mode status is available")
            const state = fixture.states[fixture.stage]
            const expected = state.changing || state.pending ? I18n.tr("Changing power mode…")
                : state.loading ? I18n.tr("Loading power modes…") : state.error
                || (state.degraded ? I18n.tr("Performance is limited: %1").arg(state.degraded)
                    : fixture.find(battery.contentItem, "battery-panel-body").modeDescription)
            fixture.check(message.text === expected, "status priority and full text are preserved")
            const viewport = fixture.find(battery.contentItem, "battery-mode-status-viewport")
            fixture.check(viewport.height <= message.implicitHeight,
                "status viewport does not reserve blank lines")
            fixture.check(Math.abs(battery.surfaceHeight - footer.y - footer.height - 8) < 1,
                "card bottom follows the status with the standard padding")
            fixture.check(battery.anchor.margins.bottom === -8,
                "top-bar gap matches the traffic popup")
            fixture.check(viewport.contentY === 0, "new status starts at the top")
            if ([0, 1, 7].includes(fixture.stage)) fixture.captureFrame()
            if (state.error || state.degraded?.length > 100) {
                fixture.check(viewport.contentHeight > viewport.height, "long messages remain scrollable")
                viewport.contentY = viewport.contentHeight - viewport.height
                fixture.check(viewport.contentY > 0, "the end of a long message can be reached")
            }
            if (++fixture.stage === fixture.states.length) {
                battery.close()
                console.log("STATUS_PANELS_PASS " + fixture.checks + " checks")
                Qt.quit()
                return
            }
            if (!fixture.capturing) fixture.applyState(fixture.states[fixture.stage])
        }
    }
}
