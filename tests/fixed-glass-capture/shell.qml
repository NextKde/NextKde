import QtQuick
import Quickshell
import Quickshell.Wayland
import Kos.SurfaceShape 1.0

ShellRoot {
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background
        anchors { left: true; right: true; top: true; bottom: true }
        color: "#17334e"
        Repeater {
            model: 12
            Rectangle {
                required property int index
                x: index * 80; width: 40; height: 640
                color: "#bf8540"
            }
        }
    }
    PanelWindow {
        id: panel
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-fixed-glass-test"
        anchors { left: true; right: true; top: true; bottom: true }
        color: "transparent"
        mask: Region { width: 0; height: 0 }
        property real progress: 0
        BackgroundEffect.blurRegion: Region { x: 64; y: 44; width: 832; height: 532 }
        Item {
            id: outline
            width: 800 * (0.22 + 0.78 * panel.progress)
            height: 500 * (0.08 + 0.92 * panel.progress)
            x: 80 + (800 - width) / 2
            y: 560 - height
        }
        SurfaceShape {
            id: shape
            target: outline
            captureGeometry: Qt.rect(64, 44, 832, 532)
            radius: Math.min(28, outline.height / 2)
            exponent: 2.35
            scrimEnabled: true
            scrimCap: 0.3
            scrimDecay: 0.75
        }
        SequentialAnimation {
            running: true
            PauseAnimation { duration: 600 }
            NumberAnimation { target: panel; property: "progress"; to: 1; duration: 650; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 350 }
            NumberAnimation { target: panel; property: "progress"; to: 0; duration: 400; easing.type: Easing.InOutCubic }
            NumberAnimation { target: panel; property: "progress"; to: 1; duration: 400; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 350 }
            ScriptAction { script: {
                if (!shape.fixedCaptureSupported) {
                    console.error("FIXED_CAPTURE_FAIL: protocol v5 unavailable");
                } else {
                    console.log("FIXED_CAPTURE_PASS");
                }
                Qt.quit();
            } }
        }
    }
}
