import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

ShellRoot {
    Window {
        id: editor
        visible: true
        width: 500
        height: 320
        title: "Clipboard anchor fixture"
        color: "white"
        Item {
            id: nonText
            anchors.fill: parent
            TextInput {
                id: field
                x: 40; y: 80; width: 300; height: 30
                text: "fixture"
                font.pixelSize: 20
                focus: true
            }
        }
        Timer {
            interval: 150; running: true
            onTriggered: { editor.requestActivate(); field.forceActiveFocus() }
        }
    }
    IpcHandler {
        target: "fixture"
        function move(): string {
            const oldX = field.cursorRectangle.x
            field.cursorPosition = 0
            return JSON.stringify({dx: field.cursorRectangle.x - oldX})
        }
        function disable(): void { nonText.forceActiveFocus() }
    }
}
