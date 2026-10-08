import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root
    property string captureName: ""
    property var captureDone: null
    function check(condition, message) {
        if (!condition) {
            console.error("PROTOTYPE_FAIL: " + message);
            Qt.quit();
            throw new Error(message);
        }
    }
    function endpoints(opened) {
        check(launcher.width === 1100 && launcher.height === 650,
              "launcher dimensions must stay fixed");
        check(launcher.glassLayer.width === 1100 && launcher.glassLayer.height === 650,
              "glass dimensions must stay fixed");
        check(launcher.iconGrid.delegates.count === 50, "expected 50 delegates");
        for (let index = 0; index < 50; ++index) {
            const icon = launcher.iconGrid.delegates.itemAt(index);
            const visual = icon.visualItem;
            check(Math.abs(icon.offsetX) <= 32 && Math.abs(icon.offsetY) <= 24, "offset clamp");
            check(icon.x === (index % 10) * 88 && icon.y === Math.floor(index / 10) * 88, "fixed grid cell moved");
            check(!icon.animating && Math.abs(visual.x - (opened ? 0 : -icon.offsetX)) < 0.001
                && Math.abs(visual.y - (opened ? 0 : -icon.offsetY)) < 0.001, "icon position did not settle");
            check(Math.abs(visual.scale - (opened ? 1 : 0.8)) < 0.001
                && Math.abs(visual.opacity - (opened ? 1 : 0)) < 0.001, "icon scale/opacity did not settle");
        }
        check(launcher.glassLayer.effect.status === ShaderEffect.Compiled, "SDF shader not compiled");
        check(Math.abs(launcher.glassLayer.effect.revealProgress - (opened ? 1 : 0)) < 0.001,
              "SDF uniform did not settle after reversal");
    }
    function capture(progress, name, next) {
        launcher.glassLayer.previewProgress = progress;
        captureName = name;
        captureDone = next;
        // Allow the changed uniform to synchronize to the scene graph before
        // grabToImage's separate offscreen pass observes the node.
        captureTimer.restart();
    }
    Timer {
        id: captureTimer
        interval: 60
        onTriggered: launcher.glassLayer.grabToImage(function (result) {
            root.check(result.saveToFile(Qt.resolvedUrl(root.captureName)), "could not save shader output");
            root.captureDone();
        })
    }
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "kos-launcher-prototype-verify"
        anchors { left: true; top: true }
        implicitWidth: 1120; implicitHeight: 670
        color: "transparent"
        mask: Region { width: 0; height: 0 }
        Launcher { id: launcher; x: 10; y: 10 }
    }
    Timer { interval: 200; running: true; onTriggered: launcher.opened = true }
    Timer { interval: 300; running: true; onTriggered: {
        launcher.glassLayer.grabToImage(function (result) {
            root.check(result.saveToFile(Qt.resolvedUrl("animated.png")), "could not capture the animated uniform");
        });
    } }
    Timer { interval: 900; running: true; onTriggered: {
        root.endpoints(true);
        launcher.opened = false;
    } }
    Timer { interval: 1500; running: true; onTriggered: {
        root.endpoints(false);
        launcher.opened = true;
    } }
    Timer { interval: 1560; running: true; onTriggered: launcher.opened = false }
    Timer { interval: 1620; running: true; onTriggered: launcher.opened = true }
    Timer { interval: 2400; running: true; onTriggered: {
        root.endpoints(true);
        launcher.glassLayer.animationsEnabled = false;
        root.capture(0, "closed.png", function () {
            root.capture(0.5, "half.png", function () {
                root.capture(1, "open.png", function () {
                    console.log("PROTOTYPE_PASS");
                    Qt.quit();
                });
            });
        });
    } }
}
