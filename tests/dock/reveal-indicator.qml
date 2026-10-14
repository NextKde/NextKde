import QtQuick
import Quickshell
import qs.desktop.modules.dock
import qs.desktop.modules.platform

Item {
    property bool started: false

    DockRevealHandle {
        id: handle
        width: 800
        height: 600
        windowWidth: width
        windowHeight: height
        dockWidth: 400
        dockHeight: 60
        fadeOpacity: 1
        showIndicator: ConfigService.showRevealIndicator
    }

    function check(condition, message) {
        if (!condition) throw new Error(message)
    }

    function checkVisualAndInput() {
        for (const edge of ["bottom", "left", "right"]) {
            handle.position = edge
            handle.active = true
            ConfigService.updateRevealIndicatorVisibility(true)
            const hit = handle.hitTarget
            const geometry = [hit.x, hit.y, hit.width, hit.height].join(":")
            check(handle.visualBar.visible, "indicator defaults visible at " + edge)
            check(edge === "bottom" ? handle.visualBar.width === 400 : handle.visualBar.height === 300,
                "indicator length is 50% of the screen edge at " + edge)
            check(hit.enabled && hit.width > 0 && hit.height > 0, "edge target is active")
            ConfigService.updateRevealIndicatorVisibility(false)
            check(!handle.visualBar.visible && !handle.visualPill.visible,
                "all indicator painting is hidden at " + edge)
            check(handle.blurRegion === null, "hidden indicator publishes no blur region")
            check(hit.enabled && [hit.x, hit.y, hit.width, hit.height].join(":") === geometry,
                "hiding the visual must preserve the edge hit target at " + edge)
            handle.active = false
            check(!hit.enabled && hit.width === 0 && hit.height === 0,
                "always-visible mode still disables the edge target")
            handle.active = true
            ConfigService.updateRevealIndicatorVisibility(true)
            check(handle.visualBar.visible && handle.visualPill.visible,
                "indicator can be shown again at " + edge)
        }
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (started || !ConfigService.ready) return
            started = true
            try {
                if (Quickshell.env("KOS_TEST_RELOAD") === "1") {
                    check(!ConfigService.showRevealIndicator, "hidden indicator survives restart")
                    check(!handle.visualBar.visible && handle.hitTarget.enabled,
                        "restart keeps edge reveal available without the visual")
                    check(ConfigService.updateRevealIndicatorVisibility(true), "indicator can be restored")
                    check(handle.visualBar.visible, "restored indicator is visible")
                    console.log("DOCK_REVEAL_INDICATOR_RELOAD_PASS")
                    Qt.quit()
                    return
                }
                check(ConfigService.showRevealIndicator, "missing setting defaults to visible")
                ConfigService._apply({showRevealIndicator: false})
                check(!ConfigService.showRevealIndicator, "stored false hides the indicator")
                for (const invalid of ["false", null, 0]) {
                    ConfigService._apply({showRevealIndicator: invalid})
                    check(ConfigService.showRevealIndicator, "invalid values retain the visible default")
                }
                ConfigService._apply({})
                check(ConfigService.showRevealIndicator, "legacy config remains visible")
                check(!ConfigService.updateRevealIndicatorVisibility("false"), "reject non-boolean writes")
                check(!ConfigService.updateRevealIndicatorVisibility(true), "ignore unchanged writes")
                const mode = ConfigService.visibilityMode
                const pins = JSON.stringify(ConfigService.dockItems)
                checkVisualAndInput()
                check(ConfigService.visibilityMode === mode, "indicator preference never changes hide mode")
                check(JSON.stringify(ConfigService.dockItems) === pins, "indicator preference never changes pins")
                ConfigService.updateRevealIndicatorVisibility(false)
                savedCheck.start()
            } catch (error) {
                console.log("FAIL " + error)
                Qt.quit()
            }
        }
    }

    Timer {
        id: savedCheck
        interval: 100
        repeat: true
        onTriggered: JsonConfigStore.readPath(ConfigService.configPath, function(data, exists) {
            if (!exists) return
            if (JSON.parse(data).showRevealIndicator === false) {
                console.log("DOCK_REVEAL_INDICATOR_SAVE_PASS")
                Qt.quit()
            }
        })
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: { console.log("FAIL timeout"); Qt.quit() }
    }
}
