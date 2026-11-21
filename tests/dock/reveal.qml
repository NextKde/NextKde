import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.desktop.modules.dock

ShellRoot {
    id: test
    property int stage: 0
    property int enteredCount: 0
    property int exitedCount: 0
    property string dockPosition: "bottom"
    property real dockX: 200
    property real dockY: 520
    property real dockWidth: 400
    property real dockHeight: 60

    // QT_QPA_PLATFORM=offscreen in run.mjs makes this a local test surface;
    // synthetic events are delivered to this QQuickWindow, never the desktop.
    Window {
        id: window
        width: 800
        height: 600
        visible: true
        Item {
            id: surface
            anchors.fill: parent
            Item {
                x: test.dockX; y: test.dockY
                width: test.dockWidth; height: test.dockHeight
                HoverHandler {
                    enabled: controller.revealProgress > 0
                    onHoveredChanged: controller.pointerInsideDock = hovered
                }
            }
            DockRevealHandle {
                id: handle
                position: test.dockPosition
                windowWidth: surface.width
                windowHeight: surface.height
                dockX: test.dockX; dockY: test.dockY
                dockWidth: test.dockWidth; dockHeight: test.dockHeight
                active: controller.handleActive
                // The same state contract used by DockWindow. Waiting for the
                // hover delay must not enlarge the cold trigger rectangle.
                expanded: controller.revealProgress > 0 || controller.phase === "Showing"
                fadeOpacity: controller.handleOpacity
                onEntered: { test.enteredCount++; controller.handleEntered() }
                onExited: { test.exitedCount++; controller.handleExited() }
                onClicked: controller.handleClicked()
            }
        }
        TestEvent { id: events }
    }
    DockRevealHandle { id: defaultHandle; active: false }
    DockAutoHideController {
        id: controller
        mode: "persistent"
        configReady: true
        position: test.dockPosition
        dockWidth: test.dockWidth
        dockHeight: test.dockHeight
    }

    function appWindows(changes = {}, notify = true) {
        WindowService.records = [Object.assign({
            identity: {desktopId: "org.example.Editor.desktop"},
            toplevel: {appId: "provider-specific-editor", minimized: false},
            geometry: {x: 100, y: 100, width: 100, height: 100},
            screenName: "fixture-output", desktopIds: ["fixture"], isVisible: true
        }, changes)]
        if (notify) WindowService.placementRevision++
    }

    function check(ok, message) {
        if (!ok) throw new Error("stage=" + stage + " phase=" + controller.phase + " " + message)
    }
    function move(x, y) {
        check(events.mouseMove(surface, x, y, 0, Qt.NoButton, Qt.NoModifier), "synthetic mouse move")
    }
    function rect(x, y, width, height) {
        check(handle.hitTarget.x === x && handle.hitTarget.y === y
            && handle.hitTarget.width === width && handle.hitTarget.height === height,
            "input rectangle: got " + [handle.hitTarget.x, handle.hitTarget.y,
                handle.hitTarget.width, handle.hitTarget.height].join(","))
    }

    Timer {
        id: steps
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            try {
                switch (test.stage++) {
                case 0:
                    check(controller.phase === "Hidden", "persistent mode boots hidden")
                    rect(200, 598, 400, 2)
                    move(100, 599)
                    interval = 130
                    break
                case 1:
                    check(controller.phase === "Hidden" && enteredCount === 0,
                        "edge outside the Dock span cannot reveal")
                    move(400, 590)
                    break
                case 2:
                    check(controller.phase === "Hidden" && enteredCount === 0,
                        "floating gap cannot reveal a hidden Dock")
                    move(400, 599)
                    interval = 30
                    break
                case 3:
                    check(controller.phase === "RevealPending", "edge enters the real hover delay")
                    rect(200, 598, 400, 2)
                    move(400, 590)
                    interval = 180
                    break
                case 4:
                    check(controller.phase === "Hidden" && !controller._handleHovered,
                        "leaving before the delay cancels reveal")
                    move(400, 599)
                    interval = 400
                    break
                case 5:
                    check(controller.phase === "Held" && controller.revealProgress === 1,
                        "remaining on the edge reveals and holds the Dock")
                    rect(200, 578, 400, 22)
                    move(400, 590)
                    interval = 1200
                    break
                case 6:
                    check(controller.phase === "Held" && controller._handleHovered,
                        "slow travel through the 20px gap exceeds leave timeout without hiding")
                    move(400, 579)
                    break
                case 7:
                    check(controller.phase === "Held" && (controller._handleHovered
                        || controller.pointerInsideDock), "2px overlap keeps a hover inhibitor during hand-off")
                    move(400, 570)
                    break
                case 8:
                    check(controller.phase === "Held" && !controller._handleHovered
                        && controller.pointerInsideDock, "glass holds after leaving the corridor")
                    move(100, 300)
                    interval = 1450
                    break
                case 9:
                    check(controller.phase === "Hidden" && controller.revealProgress === 0,
                        "leaving both regions allows hide")
                    rect(200, 598, 400, 2)
                    move(400, 590)
                    interval = 180
                    break
                case 10:
                    check(controller.phase === "Hidden", "completed hide retracts the old corridor")
                    test.dockX = 50
                    test.dockWidth = 100
                    rect(50, 598, 100, 2)
                    move(400, 599)
                    break
                case 11:
                    check(controller.phase === "Hidden", "old edge span stops responding after layout resize")
                    move(100, 599)
                    interval = 400
                    break
                case 12:
                    check(controller.phase === "Held" && controller._handleHovered,
                        "resized Dock span responds")
                    controller.mode = "always"
                    interval = 200
                    break
                case 13:
                    check(controller.phase === "Shown" && !handle.hitTarget.enabled,
                        "always-visible mode disables the reveal target")
                    rect(0, 0, 0, 0)
                    check(!controller._handleHovered, "disabled target releases its hover hold")
                    move(100, 300)
                    test.dockPosition = "left"
                    test.dockX = 20; test.dockY = 130
                    test.dockWidth = 60; test.dockHeight = 300
                    controller.mode = "persistent"
                    controller.resetForScreenChange()
                    interval = 180
                    break
                case 14:
                    rect(0, 130, 2, 300)
                    check(handle.visualBar.y + handle.visualBar.height / 2 === 280,
                        "side hint centre follows the Dock below the reserved top area")
                    move(1, 80)
                    break
                case 15:
                    check(controller.phase === "Hidden", "reserved top area is outside the side Dock span")
                    move(1, 250)
                    interval = 400
                    break
                case 16:
                    check(controller.phase === "Held", "left edge hover reveals")
                    rect(0, 130, 22, 300)
                    // Geometry can become empty while hovered during a layout
                    // reset. It must not strand the controller's hover hold.
                    test.dockHeight = 0
                    interval = 200
                    break
                case 17:
                    rect(0, 0, 0, 0)
                    check(!controller._handleHovered, "empty geometry releases its hover hold")
                    move(400, 100)
                    test.dockPosition = "right"
                    test.dockX = 720; test.dockY = 170
                    test.dockWidth = 60; test.dockHeight = 300
                    controller.resetForScreenChange()
                    interval = 180
                    break
                case 18:
                    rect(798, 170, 2, 300)
                    move(799, 100)
                    break
                case 19:
                    check(controller.phase === "Hidden", "right edge outside span is inert")
                    move(799, 250)
                    interval = 400
                    break
                case 20:
                    check(controller.phase === "Held", "right edge hover reveals")
                    rect(778, 170, 22, 300)
                    check(handle.visualBar.y + handle.visualBar.height / 2 === 320,
                        "hint is centred on the Dock's own rectangle")
                    test.dockWidth = 0; test.dockHeight = 0
                    interval = 200
                    break
                case 21:
                    check(!controller._handleHovered,
                        "empty geometry releases its hover hold")
                    rect(0, 0, 0, 0)
                    controller.mode = "always"
                    interval = 200
                    break
                case 22:
                    check(!controller._handleHovered && !handle.hitTarget.enabled,
                        "always mode clears the hover and disables the edge target")
                    test.dockPosition = "bottom"
                    test.dockX = 200; test.dockY = 520
                    test.dockWidth = 400; test.dockHeight = 60
                    controller.targetScreen = {name: "fixture-output", x: 0, y: 0, width: 800, height: 600}
                    controller.autoHideApps = ["org.example.Editor.desktop"]
                    controller.resetForScreenChange()
                    interval = 100
                    break
                case 23:
                    check(controller.phase === "Bootstrapping" && controller.revealProgress === 0,
                        "always mode with app rules waits for the initial window snapshot")
                    test.dockWidth = 0; test.dockHeight = 0
                    appWindows()
                    controller.windowDataReady = true
                    interval = 450
                    break
                case 24:
                    check(controller.phase === "Hidden" && controller.handleActive,
                        "a selected app boots hidden even without Dock overlap")
                    check(controller.mode === "always" && controller.effectiveMode === "persistent",
                        "application rules work before Dock dimensions are ready")
                    test.dockWidth = 400; test.dockHeight = 60
                    controller.handleEntered()
                    break
                case 25:
                    check(controller.phase === "Held", "edge still reveals an app-hidden Dock")
                    controller.handleExited()
                    break
                case 26:
                    check(controller.phase === "Hidden", "leaving the edge restores app hiding")
                    appWindows({toplevel: {minimized: true}})
                    break
                case 27:
                    check(controller.phase === "Shown", "minimizing the last app window restores always mode")
                    appWindows()
                    break
                case 28:
                    check(controller.phase === "Hidden", "restoring the app hides the Dock")
                    WindowService.currentDesktopId = "another-desktop"
                    break
                case 29:
                    check(controller.phase === "Shown", "another desktop ignores the selected app")
                    WindowService.currentDesktopId = "fixture"
                    break
                case 30:
                    check(controller.phase === "Hidden", "returning to the app desktop hides")
                    appWindows({screenName: "other-output", geometry: {x: 900, y: 100, width: 100, height: 100}})
                    break
                case 31:
                    check(controller.phase === "Shown", "moving the app to another output restores the Dock")
                    appWindows()
                    break
                case 32:
                    check(controller.phase === "Hidden", "moving back reapplies the rule")
                    controller.autoHideApps = []
                    break
                case 33:
                    check(controller.phase === "Shown" && !controller.handleActive,
                        "removing the rule restores the saved mode immediately")
                    controller.autoHideApps = ["org.example.Editor.desktop"]
                    break
                case 34:
                    check(controller.phase === "Hidden", "adding a rule affects already open apps")
                    WindowService.records = []
                    WindowService.placementRevision++
                    break
                case 35:
                    check(controller.phase === "Shown", "closing the app restores always mode")
                    // WindowService publishes urgency before placementRevision.
                    appWindows({}, false)
                    controller.requestReveal("urgent", 1000)
                    WindowService.placementRevision++
                    break
                case 36:
                    check(controller._temporaryRevealHold && controller.revealProgress === 1,
                        "first urgent app keeps its reveal hold before placement catches up")
                    interval = 1200
                    break
                case 37:
                    check(controller.phase === "Hidden", "app hiding resumes after the urgent hold expires")
                    console.log("DOCK_REVEAL_RUNTIME_PASS")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.log("FAIL " + error)
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: { console.log("FAIL timeout stage=" + test.stage); Qt.quit() }
    }
}
