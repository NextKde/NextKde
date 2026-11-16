import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../shared/qml/foundation" as Foundation

ShellRoot {
    // Same layer/namespace and sliding input geometry as the standalone Bar.
    // Keep the surface mapped when hidden to exercise its transparent space.
    PanelWindow {
        id: inputPanel
        visible: false
        anchors { top: true; left: true; right: true }
        implicitHeight: 35
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.namespace: "dock"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        property real slideY: 0
        property int clicks: 0
        property int wheels: 0
        Rectangle {
            id: panelContent
            y: inputPanel.slideY
            width: inputPanel.width; height: inputPanel.height
            color: "#806080a0"
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: inputPanel.clicks++
                onWheel: inputPanel.wheels++
            }
        }
        Item { id: edge; width: inputPanel.width; height: inputPanel.slideY <= -35 ? 2 : 0 }
        mask: Region {
            Region { item: panelContent }
            Region { item: edge }
        }
    }
    Window {
        id: first
        visible: true
        title: "Cooperative controls A"
        width: 540; height: 300
        flags: Qt.Window | Qt.FramelessWindowHint
        color: "#315a85"
        property real inset: 14.5
        property int backgroundClicks: 0
        MouseArea { anchors.fill: parent; onClicked: first.backgroundClicks++ }
        Foundation.KosWindowControls {
            id: controlsA
            targetWindow: first
            maximizeMode: true
            circleSize: 14; buttonWidth: 22; buttonHeight: 22; spacing: 6
            x: first.width - width - first.inset; y: 10
        }
        Text { anchors.centerIn: parent; text: "A — transparent compositor controls"; color: "white" }
    }
    Window {
        id: second
        visible: true
        title: "Cooperative controls B"
        width: 440; height: 260
        flags: Qt.Window | Qt.FramelessWindowHint
        color: "#754c36"
        Foundation.KosWindowControls {
            id: controlsB
            targetWindow: second
            maximizeMode: true
            circleSize: 18; buttonWidth: 22; buttonHeight: 32; spacing: 10
            x: 24; y: 34
        }
        Text { anchors.centerIn: parent; text: "B — independent surface"; color: "white" }
    }
    IpcHandler {
        target: "cooperative"
        function state(): string {
            return JSON.stringify({a:controlsA.compositorActive, b:controlsB.compositorActive,
                supported:controlsA.compositorSupported, ax:controlsA.x+4, ay:controlsA.y+4,
                bx:controlsB.x+2, by:controlsB.y+7, aw:controlsA.width, ah:controlsA.height,
                panelClicks:inputPanel.clicks, panelWheels:inputPanel.wheels,
                backgroundClicks:first.backgroundClicks, actions:controlsA.actions, layout:controlsA.buttonLayout, hover:controlsA.hoverGlyphs, visibility:first.visibility});
        }
        function maximize(): void { first.showMaximized(); }
        function showPanel(): void { inputPanel.slideY = 0; inputPanel.visible = true; }
        function partialPanel(): void { inputPanel.slideY = -8; }
        function hidePanel(): void { inputPanel.slideY = -37; }
        function removePanel(): void { inputPanel.visible = false; }
        function moveSlot(): void { first.inset = 96; controlsA.y = 54; }
        function closeOnly(): void { controlsA.actions = ["close"]; }
        function minimizeOnly(): void { controlsA.actions = ["minimize"]; }
        function maximizeOnly(): void { controlsA.actions = ["maximize"]; }
        function reversed(): void { controlsA.actions = ["close", "maximize"]; }
        function noButtons(): void { controlsA.actions = []; }
        function allButtons(): void { controlsA.actions = ["maximize", "minimize", "close"]; }
        function resize(): void { first.width = 720; }
        function fade(): void { controlsA.opacity = 0.5; }
        function unfade(): void { controlsA.opacity = 1; }
        function fullscreen(): void { first.showFullScreen(); }
        function restore(): void { first.showNormal(); }
        function hidePeer(): void { second.hide(); }
        function showPeer(): void { second.show(); }
        function quit(): void { Qt.quit(); }
    }
}
