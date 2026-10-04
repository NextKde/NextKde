import QtQuick
import Quickshell
import qs.desktop.modules.dock

ShellRoot {
    DockWindow { id: leftDock; position: "left"; visible: true }
    DockWindow { id: rightDock; position: "right"; visible: true }
    DockWindow {
        id: bottomDock
        position: "bottom"; visible: true
        Component.onCompleted: { testContainer.width = 900; testContainer.height = 56 }
    }
    function check(condition, message) {
        if (!condition) throw new Error(message)
    }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                for (const dock of [leftDock, rightDock, bottomDock]) {
                    const edge = dock.position
                    check(dock.edgeMargin === 7 && dock.workspaceMargin === 7,
                        edge + " margins must follow 56px thickness, not 900px length")
                    check(dock.exclusiveZone === 70, edge + " reserves only the thickness and gaps")
                    if (edge === "left") check(dock.restX === 7, "left glass is near the edge")
                    if (edge === "right") check(dock.restX === dock.width - 63, "right glass is near the edge")
                    if (edge === "bottom") check(dock.restY === dock.height - 63, "bottom inset stays unchanged: " + dock.restY + ", height=" + dock.height + ", thickness=" + dock.testContainer.height)

                    dock.testController.revealProgress = 1
                    dock.testController.handleActive = true
                    dock.testController.handleOpacity = 0
                    check(dock.testPill.visible && dock.testRegions.regions.length === 1,
                        edge + " shown glass has only the Dock region")
                    check(dock.testHandle.blurRegion === null,
                        edge + " faded-out hint must not keep a compositor region")
                    dock.testController.revealProgress = 0
                    dock.testController.handleOpacity = 1
                    check(!dock.testPill.visible && dock.testRegions.regions.length === 1,
                        edge + " hidden Dock retires its glass, leaving only the hint")
                    check(dock.testRegions.regions[0] === dock.testHandle.blurRegion,
                        edge + " hidden region belongs to the hint")
                    check(dock.visible && dock.testHandle.hitTarget.enabled,
                        edge + " hiding glass preserves the mapped window and edge input")
                    dock.testHandle.showIndicator = false
                    check(dock.testRegions.regions.length === 0 && dock.testHandle.hitTarget.enabled,
                        edge + " disabling the hint removes all glass but keeps edge input")
                    dock.testHandle.showIndicator = true
                    dock.testController.revealProgress = 0.5
                    check(dock.testPill.visible && dock.testRegions.regions.length === 2,
                        edge + " revealing restores the glass during the animation")
                }
                ConfigService.dockStyle = "taskbar"
                check(leftDock.edgeMargin === 0 && leftDock.workspaceMargin === 0
                    && leftDock.exclusiveZone === 56, "taskbar keeps its flush edge reservation")
                console.log("DOCK_SURFACE_PASS")
            } catch (error) {
                console.log("FAIL " + error)
            }
            Qt.quit()
        }
    }
}
