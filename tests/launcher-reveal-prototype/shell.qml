//@ pragma UseQApplication
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    property bool opened: false
    property int mode: 0
    function selectMode(value) {
        opened = false;
        mode = value;
        Qt.callLater(function () { root.opened = true; });
    }
    function reverse() {
        opened = true;
        reversal.step = 0;
        reversal.restart();
    }
    Timer {
        id: reversal
        property int step: 0
        interval: 70; repeat: true
        onTriggered: {
            ++step;
            root.opened = step !== 1;
            if (step === 2) stop();
        }
    }
    IpcHandler {
        target: "launcher-prototype"
        function toggle(): void { root.opened = !root.opened; }
        function selectMode(value: int): void { root.selectMode(value); }
        function reverse(): void { root.reverse(); }
    }
    Window {
        id: window
        title: "启动台动画原型 · 50 个图标 / SDF"
        width: 1280; height: 900
        visible: true
        color: "#101c2a"
        onClosing: Qt.quit()
        Item {
            anchors.fill: parent
            focus: true
            Keys.onSpacePressed: root.opened = !root.opened
            Keys.onEscapePressed: root.opened = false
            Text {
                x: 40; y: 26
                text: "启动台 · 动画原型"
                color: "#f1f5fa"
                font.pixelSize: 24; font.weight: Font.Medium
            }
            Text {
                x: 40; y: 64
                text: "50 个图标 · 10 × 5 · 64px · 20% 收拢（最多 32 / 24px）"
                color: "#a9bccf"
                font.pixelSize: 14
            }
            Row {
                x: 40; y: 100; spacing: 10
                ProbeButton { label: "组合"; selected: root.mode === 0; onClicked: root.selectMode(0) }
                ProbeButton { label: "仅图标"; selected: root.mode === 1; onClicked: root.selectMode(1) }
                ProbeButton { label: "仅 SDF 形状"; selected: root.mode === 2; onClicked: root.selectMode(2) }
                ProbeButton { label: root.opened ? "收起 · Space" : "展开 · Space"; selected: root.opened; onClicked: root.opened = !root.opened }
                ProbeButton { label: "快速反向"; onClicked: root.reverse() }
            }
            Rectangle {
                x: 90; y: 172; width: 1100; height: 650
                color: "transparent"
                border.width: 1; border.color: "#355067"
            }
            Launcher {
                id: launcher
                x: 90; y: 172
                opened: root.opened
                showIcons: root.mode !== 2
                showGlass: root.mode !== 1
            }
            Text {
                x: 40; y: 850
                text: "图标 300ms / 淡入 200ms · 形状 320ms · OutCubic · 当前为纯色形状，没有 Blur / Refraction / Highlight"
                color: "#a9bccf"
                font.pixelSize: 13
            }
        }
    }
    Timer { interval: 400; running: true; onTriggered: root.opened = true }
}
