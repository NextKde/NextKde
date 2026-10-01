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
    DockAutoHideController {
        id: controller
        mode: "persistent"
        configReady: true
        position: test.dockPosition
        dockWidth: test.dockWidth
        dockHeight: test.dockHeight
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
        interval: 18000
        running: true
        onTriggered: { console.log("FAIL timeout stage=" + test.stage); Qt.quit() }
    }
}
