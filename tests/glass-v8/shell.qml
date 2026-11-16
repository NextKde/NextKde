import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Kos.SurfaceShape 1.0

// Manual comparison on the real compositor. No pixel assertions or private data.
ShellRoot {
    id: root
    property bool panelsVisible: true
    property bool toastVisible: false
    property real sigmaOverride: -1
    property int sampleCount: 21
    Timer { id: rebirth; interval: 300; onTriggered: root.sampleCount = 21 }
    NumberAnimation {
        id: sweep
        target: root; property: "sigmaOverride"; from: 4; to: 16; duration: 1500
        onStopped: root.sigmaOverride = -1
    }
    IpcHandler {
        target: "glass-v8"
        function hide(hidden: bool): void { root.panelsVisible = !hidden }
        function toast(shown: bool): void { root.toastVisible = shown }
        function sigma(value: real): void { root.sigmaOverride = value }
        function rebuild(): void { root.sampleCount = 0; rebirth.restart() }
        function animate(): void { sweep.restart() }
        function quit(): void { Qt.quit() }
    }
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-glass-v8-background"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "#447d9b"
        Repeater {
            model: 100
            Rectangle {
                required property int index
                x: index * 16; width: 8; height: 1000
                color: index % 5 === 0 ? "#f2c06a" : "#80c7ba"
            }
        }
        Repeater {
            model: 6
            Rectangle {
                required property int index
                x: index * 210 + 40; y: index % 2 * 110 + 100
                width: 160; height: 460; radius: 80
                color: index % 2 ? "#aa5e6d" : "#29475c"
            }
        }
        Repeater {
            model: 3
            Text {
                required property int index
                x: 30; y: 132 + index * 180
                text: "Background detail • 背景细节    Background detail • 背景细节"
                font.pixelSize: 32; color: "#fff7dc"
            }
        }
    }
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-glass-v8-comparison"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // Deliberately unrelated legacy input: v8 geometry must ignore it.
        BackgroundEffect.blurRegion: Region { x: 0; y: 0; width: 1; height: 1 }
        Text {
            x: 30; y: 24
            text: "v8 Gaussian — row 1: sigma / row 2: tint / row 3: complete-effect fade"
            font.pixelSize: 20; color: "white"
        }
        Repeater {
            model: root.sampleCount
            Item {
                id: cell
                required property int index
                readonly property int column: index % 7
                readonly property int row: Math.floor(index / 7)
                readonly property var sigmas: [0, 4, 8, 12, 16, 24, 32]
                readonly property var tints: [0, 0.05, 0.1, 0.2, 0.35, 0.55, 0.8]
                x: 30 + column * 155; y: 105 + row * 180
                width: 140; height: 135
                visible: root.panelsVisible
                Text {
                    y: -28
                    color: "white"; font.pixelSize: 16
                    text: cell.row === 0 ? "σ " + (root.sigmaOverride >= 0 ? root.sigmaOverride : cell.sigmas[cell.column])
                        : cell.row === 1 ? "tint " + cell.tints[cell.column]
                        : "fade " + (cell.column / 6).toFixed(2)
                }
                Item { id: outline; anchors.fill: parent }
                SurfaceShape {
                    id: shape
                    target: outline
                    radius: 24; exponent: 3
                    effectType: SurfaceShape.Frosted
                    material: SurfaceShape.Regular
                    blurSigma: cell.row === 0
                        ? (root.sigmaOverride >= 0 ? root.sigmaOverride : cell.sigmas[cell.column]) : 12
                    tintMode: SurfaceShape.Fixed
                    tintColor: "#102030"
                    tintOpacity: cell.row === 1 ? cell.tints[cell.column] : cell.row === 2 ? 0.08 : 0
                    materialOpacity: cell.row === 2 ? cell.column / 6 : 1
                    scrimEnabled: false
                    onActiveChanged: if (active) console.log("GLASS_V8", cell.index,
                        "continuous", continuousBlurSupported, "sigma", blurSigma)
                }
            }
        }
        Item {
            id: toast
            x: 450; y: 680; width: 260; height: 36
            visible: root.panelsVisible && root.toastVisible
            SurfaceShape {
                target: toast; radius: 18
                blurSigma: 12; tintMode: SurfaceShape.Fixed
                tintOpacity: 0.1; effectType: SurfaceShape.Liquid
            }
        }
    }
}
