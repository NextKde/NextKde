import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "Kos/Ui"

FloatingWindow {
    id: window
    visible: true
    implicitWidth: 600
    implicitHeight: 600
    property int phase: 0
    property int failures: 0
    property int edgeIndex: 0
    property var edges: ["bottom", "left", "right"]
    function check(value, message) {
        if (!value) { failures++; console.log("FAIL " + message) }
    }
    Item {
        id: host
        anchors.fill: parent
        property point magnificationPointer: Qt.point(300, 300)
        property bool launchAnimationVisible: true
        readonly property alias nameLabel: sharedLabel
        function magnificationFor(item) { return 0.5 }
        function spreadFor(item) { return 0 }
        function hoverFor(item) { return true }
        function updateNameLabel() { sharedLabel.updateGeometry() }
        DockNameLabel {
            id: sharedLabel
            targetIcon: icon
            pointerRoot: host
            pointerPosition: host.magnificationPointer
        }
        Row {
            x: 270; y: 300
            rotation: window.edgeIndex === 0 ? 0 : 90
            DockIcon {
                id: icon
                appId: "dock-feedback-probe.desktop"
                displayName: "Launch probe"
                iconSize: 44
                magnificationRoot: host
                magnificationPointer: host.magnificationPointer
                dockEdge: window.edges[window.edgeIndex]
                vertical: window.edgeIndex !== 0
            }
        }
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (window.phase === 0) {
                DockLaunchService.begin(icon.appId)
                window.check(icon._launching && icon._launchBouncing, "launch starts immediately")
                const records = WindowService.records.slice()
                records.push({identity: {desktopId: icon.appId, name: "Probe", iconSource: ""},
                    rawAppId: icon.appId, windowId: "probe-window", title: "Probe", toplevel: {
                        activated: false, minimized: false, fullscreen: false}})
                WindowService.records = records
                WindowService.revision++
                window.check(icon._launching, "immediate window readiness preserves visible launch feedback")
            } else if (window.phase === 2) {
                window.check(icon._launchLift < -1, "launch has visible workspace lift")
                host.magnificationPointer = Qt.point(325, 330)
            } else if (window.phase === 3) {
                const anchor = sharedLabel
                window.check(anchor !== null, "label anchor exists")
                if (anchor) {
                    window.check(Math.abs((icon.vertical ? anchor.y + anchor.height / 2 : anchor.x + anchor.width / 2)
                        - (icon.vertical ? 330 : 325)) < 0.01,
                        "label tracks pointer along " + icon.dockEdge)
                    const center = icon.mapToItem(host, icon.width / 2, icon.height / 2)
                    const extent = icon.iconSize * icon.scale / 2 + 6
                    const expected = icon.dockEdge === "bottom" ? center.y - extent
                        : center.x + (icon.dockEdge === "left" ? extent : -extent)
                    window.check(Math.abs((icon.vertical ? (icon.dockEdge === "right" ? anchor.x + anchor.width : anchor.x)
                            : anchor.y + anchor.height) - expected) < 0.01, "label follows artwork edge in same frame")
                }
            } else if (window.phase === 4) {
                AppTheme.reduceMotion = true
                window.check(!icon._launchBouncing && icon._launchLift === 0,
                    "reduced motion stops bounce without clearing launch state")
                window.check(icon._launching, "reduced motion preserves pending launch")
                AppTheme.reduceMotion = false
                window.check(icon._launchBouncing, "pending launch resumes when motion is enabled")
                host.launchAnimationVisible = false
                window.check(!icon._launchBouncing && icon._launchLift === 0,
                    "hidden Dock stops the animation driver")
                window.check(icon._launching, "hiding does not cancel the launch request")
                host.launchAnimationVisible = true
                window.check(icon._launchBouncing, "visible Dock resumes pending launch feedback")
            } else if (window.phase === 6) {
                DockLaunchService.reconcile()
                window.check(!icon._launching, "ready window ends pending after minimum feedback")
            } else if (window.phase === 10) {
                window.check(!icon._launchBouncing && icon._launchLift === 0,
                    "landing settles exactly")
                WindowService.records = []
                WindowService.revision++
                DockLaunchService.begin(icon.appId)
                AppActionService.launchFailed(icon.appId)
                window.check(!icon._launching, "asynchronous failure ends launch")
                const pending = {}
                pending[icon.appId] = Date.now() - DockAnimation.launchFeedbackTimeoutMs - 1
                DockLaunchService.pending = pending
                DockLaunchService.reconcile()
                window.check(!icon._launching, "windowless launch expires")
                console.log("REPORT " + icon.dockEdge + " readiness/failure/expiry/landing/label passed")
                if (window.edgeIndex === 2) {
                    if (window.failures === 0) console.log("DOCK_LAUNCH_FEEDBACK_PASS")
                    Qt.quit()
                    return
                }
                window.edgeIndex++
                host.magnificationPointer = Qt.point(300, 300)
                window.phase = -1
            }
            window.phase++
        }
    }
}
