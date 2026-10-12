import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property var uid: null
    property bool ready: false
    property bool frozen: false
    onFrozenChanged: {
        if (frozen) { reader.running = false; timeout.stop(); }
        else reload();
    }
    property var state: ({source: "", fit: "crop", version: "default"})
    function reset() { state = {source: "", fit: "crop", version: "default"}; ready = true; }
    function reload() {
        if (!frozen && !readerBusy) { readingGeneration = generation; readerBusy = true; reader.running = true; timeout.restart(); }
    }
    property int generation: 0
    property int readingGeneration: 0
    property bool switching: false
    property bool readerBusy: false
    onUidChanged: {
        ++generation; switching = true;
        state = {source: "", fit: "crop", version: "default"}; ready = false;
        if (reader.running) reader.running = false;
        switching = false;
        Qt.callLater(reload);
    }
    Component.onCompleted: reload()
    Process {
        id: reader
        command: ["/usr/bin/python3", Quickshell.shellDir + "/companion/wallpaper.py", String(root.uid === null ? -1 : root.uid)]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.frozen || root.switching || root.readingGeneration !== root.generation) return;
                try {
                    let result = JSON.parse(text);
                    if (result.uid === (root.uid === null ? -1 : root.uid)) { root.state = result; root.ready = true; }
                } catch (_) { root.reset(); }
            }
        }
        onExited: (code, status) => {
            readerBusy = false; timeout.stop();
            if (root.switching || root.readingGeneration !== root.generation) { Qt.callLater(root.reload); return; }
            if (code !== 0 && !root.frozen) root.reset();
        }
    }
    Timer { interval: 1000; running: !root.frozen; repeat: true; onTriggered: root.reload(); }
    Timer { id: timeout; interval: 3000; onTriggered: { reader.running = false; root.reset(); } }
}
