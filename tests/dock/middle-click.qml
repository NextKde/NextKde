import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.dock

// Offscreen fixture for the Dock's middle-click new-window gesture.
//
// It loads the shipping DockIcon through the same `desktop` symlink used by
// hover-hit.qml and delivers synthetic pointer events into a real
// QQuickWindow. The host binding is intentionally absent: this fixture pins
// the pointer contract (which signal each button emits, that the other
// buttons keep their own actions, that an unresolved-entry tile stays inert,
// and what holding the middle button must and must not do), while button
// acceptance and the DockContainer-to-service wiring are checked by the
// source assertions in tests/dock/model.test.mjs.
ShellRoot {
    id: root

    property int newWindows: 0
    property int activations: 0
    property int contexts: 0
    property int editRequests: 0
    property int editExits: 0
    property int shellNewWindows: 0
    property int shellActivations: 0
    property int ghostNewWindows: 0
    property int failures: 0
    property bool finished: false

    function check(value, message) {
        if (!value) {
            failures++
            console.log("FAIL " + message)
        }
    }

    function click(item, button) {
        return events.mouseClick(item, item.width / 2, item.height / 2,
            button, Qt.NoModifier, 5)
    }

    Window {
        id: window
        width: 360
        height: 240
        visible: true

        Item {
            id: host
            anchors.fill: parent

            DockIcon {
                id: appIcon
                x: 60
                y: 90
                iconSize: 44
                appId: "org.example.MiddleClick.desktop"
                newWindowEnabled: true
                // Custom menus route the right button to the icon's own
                // contextRequested signal instead of building the Wayland
                // PopupWindow, which is not wanted in an offscreen fixture.
                showContextMenu: false
                customContextMenu: true
                onNewWindowRequested: root.newWindows++
                onActivate: root.activations++
                onContextRequested: root.contexts++
                onRequestEdit: root.editRequests++
                onRequestEditExit: root.editExits++
            }

            // Fixed shell control shape: no app identity. It must not accept
            // the middle button at all, so neither action may fire.
            DockIcon {
                id: shellIcon
                x: 210
                y: 90
                iconSize: 44
                showContextMenu: false
                customContextMenu: true
                allowEdit: false
                onNewWindowRequested: root.shellNewWindows++
                onActivate: root.shellActivations++
            }

            // A non-empty appId is not proof of a resolved desktop entry:
            // AppIdentityService synthesises an id from an unknown raw class.
            // The host leaves the gesture disabled in that case.
            DockIcon {
                id: ghostIcon
                x: 135
                y: 90
                iconSize: 44
                appId: "org.example.Ghost.desktop"
                showContextMenu: false
                customContextMenu: true
                onNewWindowRequested: root.ghostNewWindows++
            }
        }

        TestEvent { id: events }
    }

    function finish() {
        finished = true
        console.log("REPORT newWindows=" + newWindows
            + " activations=" + activations
            + " contexts=" + contexts
            + " editRequests=" + editRequests
            + " editExits=" + editExits
            + " shellNewWindows=" + shellNewWindows
            + " ghostNewWindows=" + ghostNewWindows)
        if (failures === 0)
            console.log("DOCK_MIDDLE_CLICK_PASS")
        Qt.quit()
    }

    function run() {
        try {
            root.check(root.click(appIcon, Qt.MiddleButton), "middle click delivered")
            root.check(root.newWindows === 1, "middle click launches one new window")
            root.check(root.activations === 0, "middle click must not activate or toggle")

            root.check(root.click(appIcon, Qt.LeftButton), "left click delivered")
            root.check(root.activations === 1, "left click keeps its activation path")
            root.check(root.newWindows === 1, "left click must not launch a new window")

            root.check(root.click(appIcon, Qt.RightButton), "right click delivered")
            root.check(root.contexts === 1, "right click keeps its context-menu path")
            root.check(root.newWindows === 1, "right click must not launch a new window")
            root.check(root.activations === 1, "right click must not activate")

            appIcon.editMode = true
            root.click(appIcon, Qt.MiddleButton)
            root.check(root.newWindows === 1, "edit mode suppresses the new-window gesture")
            root.check(root.editExits === 1, "middle click in edit mode only ends the edit session")
            appIcon.editMode = false

            root.click(shellIcon, Qt.MiddleButton)
            root.check(root.shellNewWindows === 0, "an icon without an app id must not launch")
            root.check(root.shellActivations === 0, "middle click is not a control activation")

            root.click(ghostIcon, Qt.MiddleButton)
            root.check(root.ghostNewWindows === 0,
                "an app id without a resolved desktop entry must not launch")

            // MouseArea emits pressAndHold for any accepted button. Holding
            // middle on a pinned icon must not enter the edit/reorder state.
            root.check(events.mousePress(appIcon, appIcon.width / 2, appIcon.height / 2,
                Qt.MiddleButton, Qt.NoModifier, 5), "middle press delivered")
            holdTimer.start()
        } catch (error) {
            console.log("FAIL exception: " + error)
            root.finish()
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: false
        onTriggered: root.run()
    }

    Timer {
        id: holdTimer
        // Qt fires pressAndHold once the platform's hold interval elapses;
        // wait past that interval plus a margin so the assertion tests the
        // handler's button filter rather than the timer's precision.
        interval: Math.max(Qt.styleHints.mousePressAndHoldInterval, 400) + 300
        repeat: false
        onTriggered: {
            root.check(root.editRequests === 0,
                "middle press-and-hold must not request edit mode")
            events.mouseRelease(appIcon, appIcon.width / 2, appIcon.height / 2,
                Qt.MiddleButton, Qt.NoModifier, 5)
            // The handler rejects the composed press-and-hold event, so Qt
            // keeps the release a click: a slow middle press still opens the
            // window instead of the gesture silently vanishing.
            root.check(root.newWindows === 2,
                "the release after a middle press-and-hold still opens the window")
            // Positive control: the same hold with the left button must still
            // enter the edit path, so the middle-button filter cannot silently
            // swallow the rest of the handler.
            root.check(events.mousePress(appIcon, appIcon.width / 2, appIcon.height / 2,
                Qt.LeftButton, Qt.NoModifier, 5), "left press delivered")
            leftHoldTimer.start()
        }
    }

    Timer {
        id: leftHoldTimer
        interval: holdTimer.interval
        repeat: false
        onTriggered: {
            root.check(root.editRequests === 1,
                "a left press-and-hold still enters the edit path")
            events.mouseRelease(appIcon, appIcon.width / 2, appIcon.height / 2,
                Qt.LeftButton, Qt.NoModifier, 5)
            root.check(root.activations === 1,
                "a left press-and-hold must not activate on release")
            root.finish()
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: {
            if (!root.finished) {
                console.log("FAIL timeout")
                Qt.quit()
            }
        }
    }
}
