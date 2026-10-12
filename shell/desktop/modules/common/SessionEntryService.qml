pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.desktop.modules.wallpaper
import qs.desktop.modules.dock

// Cover IPC is scoped to its installed QML path; no environment import into
// the shared user service. Normal launches open after one bounded discovery.
QtObject {
    id: root
    property bool discovering: true
    property bool pending: false
    property bool released: false
    property var handoff: ({})
    property var frames: ({})
    property var essentials: ({})
    property real progress: 1
    property bool defaultBackground: false
    property string initialWallpaper: ""
    property bool imageMatches: false
    property string verifiedSource: ""
    property string sessionImage: ""
    readonly property bool staticPresentation: defaultBackground || sessionImage !== ""
    property string sessionFit: "crop"
    property string verificationKey: ""
    readonly property string coverPath: Quickshell.env("KOS_GREETER_APP_DIR")
        ? Quickshell.env("KOS_GREETER_APP_DIR") + "/cover.qml" : Qt.resolvedUrl("../../../../apps/greeter/cover.qml").toString().replace(/^file:\/\//, "")
    function clearPresentation() {
        sessionImage = ""; defaultBackground = false; imageMatches = false;
        verificationKey = ""; frames = ({});
    }
    function record(name) { console.info("KOS_ENTRY " + name + " " + Date.now()); }
    function frame(output, source, fit) {
        if (!pending || (!defaultBackground && (!imageMatches || source !== sessionImage || fit !== handoff.fit))) return;
        const first = !frames[output];
        let next = Object.assign({}, frames); next[output] = true; frames = next;
        if (first) record("FrameSubmitted " + handoff.session + " " + output + " " + handoff.hash); check();
    }
    function verify() {
        if (!pending || defaultBackground || verifier.running) return;
        const source = WallpaperService.wallpaperUrl.toString();
        const key = source + "|" + handoff.hash + "|" + handoff.fit;
        if (verificationKey === key) return;
        verificationKey = key; imageMatches = false; frames = ({});
        verifier.command = ["/usr/bin/python3", coverPath.replace(/cover.qml$/, "companion/entry.py"), source, handoff.hash, handoff.version, handoff.fit];
        verifier.running = true;
    }
    property Process verifier: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (root.pending && result.source === WallpaperService.wallpaperUrl.toString()
                        && result.hash === root.handoff.hash && result.match) {
                        root.verifiedSource = result.source; root.sessionImage = result.image; root.sessionFit = root.handoff.fit; root.imageMatches = true;
                        root.record("ResourceMatched");
                    }
                } catch (_) {}
            }
        }
    }
    property Timer verifyTimer: Timer { interval: 250; running: root.pending; repeat: true; onTriggered: root.verify() }
    function essential(name, ready) {
        let next = Object.assign({}, essentials); next[name] = ready; essentials = next; check();
    }
    function check() {
        if (!pending || (!defaultBackground && !imageMatches) || !essentials.dock || !ConfigService.ready
            || !AppearanceConfigService.ready
            || (!AppearanceConfigService.barIntegratedWithDock && !essentials.bar)) return;
        const outputs = Quickshell.screens.map(s => s.name).sort();
        if (JSON.stringify(outputs) !== JSON.stringify(handoff.outputs) || !outputs.length
            || !outputs.every(n => frames[n])) return;
        reveal.command = ["/usr/bin/qs", "-p", coverPath, "ipc", "call", "cover", "reveal",
            JSON.stringify({session: handoff.session, hash: handoff.hash, version: handoff.version, fit: handoff.fit, outputs: outputs})];
        if (!reveal.running) reveal.running = true;
    }
    function release(reason) {
        if (released) return;
        released = true; discovering = false; pending = false; record(reason); animation.start();
    }
    property NumberAnimation animation: NumberAnimation {
        target: root; property: "progress"; to: 1; duration: Quickshell.env("KOS_GREETER_REDUCED_MOTION") === "1" ? 1 : 620
        easing.type: Easing.OutCubic
        onFinished: root.record("RevealComplete")
    }
    property Timer deadline: Timer { interval: 12000; running: true; onTriggered: root.release("Timeout") }
    property Timer discoveryDeadline: Timer { interval: 12000; running: true; onTriggered: { if (root.discovering) root.release("NoCover"); } }
    property Timer poll: Timer { interval: 200; running: !root.released; repeat: true; onTriggered: { if (!root.discovery.running) root.discovery.running = true; } }
    property Connections wallpaperChanges: Connections {
        target: WallpaperService
        function onPresentationChangeRequested() { if (root.released) root.clearPresentation(); }
        function onModeChanged() { if (root.released) root.clearPresentation(); }
        function onFitModeChanged() { if (root.released) root.clearPresentation(); }
        function onTakeoverEnabledChanged() { if (root.released) root.clearPresentation(); }
        function onWallpaperUrlChanged() {
            root.imageMatches = false; root.frames = ({}); root.verificationKey = ""; root.sessionImage = "";
            if (root.released && WallpaperService.wallpaperUrl.toString() !== root.initialWallpaper)
                root.defaultBackground = false;
        }
    }
    property Connections previewChanges: Connections {
        target: WallpaperPreviewService
        function onActiveChanged() {
            if (root.released && WallpaperPreviewService.active) root.clearPresentation();
        }
    }
    property Connections appearanceChanges: Connections {
        target: AppearanceConfigService
        function onSpatialWallpaperEnabledChanged() { if (root.released) root.clearPresentation(); }
    }
    property Process discovery: Process {
        command: ["/usr/bin/qs", "-p", root.coverPath, "ipc", "call", "cover", "describe"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.released) return;
                try {
                    const value = JSON.parse(text);
                    if (!/^[0-9a-f]{32}$/.test(value.session) || value.revealing) return;
                    const changed = root.handoff.session !== value.session || root.handoff.hash !== value.hash
                        || root.handoff.fit !== value.fit || JSON.stringify(root.handoff.outputs) !== JSON.stringify(value.outputs);
                    if (changed) { root.frames = ({}); root.imageMatches = false; root.verificationKey = ""; root.sessionImage = ""; }
                    root.handoff = value;
                    root.defaultBackground = value.version === "default" && value.hash === "";
                    if (!root.pending) {
                        root.initialWallpaper = WallpaperService.wallpaperUrl.toString();
                        root.progress = 0; root.record("ResourceReady");
                    }
                    root.pending = true; root.discovering = false;
                    root.verify(); root.check();
                } catch (_) {}
            }
        }
    }
    property Process reveal: Process {
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim() === "accepted") root.release("RevealStarted"); }
        }
    }
}
