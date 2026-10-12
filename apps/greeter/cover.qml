import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "qml" as Greeter

ShellRoot {
    id: root
    property var state: ({source: "", fit: "crop", version: "default"})
    function record(name) { console.info("KOS_COVER " + name + " " + Date.now()); }
    property bool feedReady: false
    property bool revealing: false
    property real coverOpacity: 1
    readonly property bool reducedMotion: Quickshell.env("KOS_GREETER_REDUCED_MOTION") === "1"
    readonly property int revealDuration: reducedMotion ? 1 : 620
    function requestReveal(payload) {
        if (revealing || !state.session) return "rejected";
        let value;
        try { value = JSON.parse(payload); } catch (_) { return "rejected"; }
        if (!value || typeof value !== "object" || !Array.isArray(value.outputs)) return "rejected";
        const names = Quickshell.screens.map(s => s.name).sort();
        if (value.session !== state.session || value.hash !== state.hash || value.version !== state.version
            || value.fit !== state.fit || JSON.stringify(value.outputs) !== JSON.stringify(names)) {
            record("ReadyRejected"); return "rejected";
        }
        revealing = true; record("RevealStarted"); fade.start(); return "accepted";
    }
    NumberAnimation { id: fade; target: root; property: "coverOpacity"; to: 0; duration: root.revealDuration; easing.type: Easing.OutCubic; onFinished: root.finish("RevealComplete") }
    function finish(reason) { record(reason); Qt.quit(); }
    // Independent of resource readiness, output count, and Shell availability.
    Timer { interval: 15000; running: true; onTriggered: root.finish("Timeout") }
    Timer { id: stale; interval: 2000; running: true; onTriggered: { root.state = ({source: "", fit: "crop", version: "default"}); root.feedReady = true; } }
    Process {
        id: feed
        command: ["/usr/bin/python3", Quickshell.shellDir + "/companion/cover.py", "--feed"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try { root.state = JSON.parse(data); if (!root.feedReady) root.record("FeedReceived"); root.feedReady = true; stale.restart(); }
                catch (_) { root.state = ({source: "", fit: "crop", version: "default"}); root.feedReady = true; }
            }
        }
        onExited: { root.state = ({source: "", fit: "crop", version: "default"}); root.feedReady = true; }
    }
    IpcHandler {
        target: "cover"
        function describe(): string {
            return JSON.stringify({session: root.state.session || "", hash: root.state.hash || "",
                version: root.state.version, fit: root.state.fit,
                outputs: Quickshell.screens.map(s => s.name).sort(), revealing: root.revealing});
        }
        function reveal(payload: string): string { return root.requestReveal(payload); }
        // Legacy T10 recovery harness; production readiness uses matching reveal.
        function ready(): void { root.finish("ShellReady"); }
        function abort(): void { root.finish("Recovery"); }
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            implicitWidth: screen?.width ?? 1920
            implicitHeight: screen?.height ?? 1080
            property bool initialReady: false
            visible: initialReady
            function showWhenReady() {
                if (!initialReady && root.feedReady && host.resourceSettled)
                    Qt.callLater(function() { if (root.feedReady && host.resourceSettled) window.initialReady = true; });
            }
            Connections {
                target: root
                function onFeedReadyChanged() { window.showWhenReady(); }
            }
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "kos-early-cover"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Empty input region: keyboard/TTY and desktop shortcuts remain usable.
            mask: Region {}
            color: "transparent"
            contentItem.clip: true
            Item {
                width: window.width; height: window.height
                // Move the whole scene together; the desktop is already painted below.
                y: -height * (1 - root.coverOpacity)
                Rectangle { anchors.fill: parent; color: "#16283b" }
                Greeter.WallpaperHost {
                    id: host
                    pixelRatio: window.screen ? window.screen.devicePixelRatio : 1
                    decodeWidth: window.screen?.width ?? window.implicitWidth
                    decodeHeight: window.screen?.height ?? window.implicitHeight
                    anchors.fill: parent
                    source: root.state.source; fitMode: root.state.fit
                    onResourceSettledChanged: { if (resourceSettled) root.record("ResourceReady " + window.screen.name); window.showWhenReady(); }
                    Component.onCompleted: { if (resourceSettled) root.record("ResourceReady " + window.screen.name); window.showWhenReady(); }
                    onDecoded: root.record("ImageDecoded " + window.screen.name + " " + root.state.version)
                    onFrameSubmitted: root.record("FrameSubmitted " + window.screen.name + " " + root.state.version)
                    onFallback: reason => root.record("Fallback " + reason)
                }
                Greeter.LoadingSpinner {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.79
                    reducedMotion: root.reducedMotion
                    running: !root.revealing
                }
            }
            onBackingWindowVisibleChanged: root.record("WindowMapped " + screen.name + " " + backingWindowVisible)
            Component.onDestruction: root.record("OutputRemoved")
        }
    }
}
