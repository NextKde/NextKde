import QtQuick
import Quickshell
import Quickshell.Wayland

Item {
    id: root
    property var state: ({source: "", fit: "crop", version: "default"})
    property bool sourceReady: false
    property var settledScreens: ({})
    function settled(name, value) {
        let next = Object.assign({}, settledScreens);
        next[name] = value;
        settledScreens = next;
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
                if (!initialReady && root.sourceReady && host.resourceSettled)
                    Qt.callLater(function() { if (root.sourceReady && host.resourceSettled) window.initialReady = true; });
            }
            Connections {
                target: root
                function onSourceReadyChanged() { window.showWhenReady(); }
            }
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "#16283b"
            WallpaperHost {
                id: host
                pixelRatio: window.screen ? window.screen.devicePixelRatio : 1
                decodeWidth: window.screen?.width ?? window.implicitWidth
                decodeHeight: window.screen?.height ?? window.implicitHeight
                anchors.fill: parent
                source: root.state.source; fitMode: root.state.fit
                onResourceSettledChanged: { root.settled(window.screen.name, resourceSettled); window.showWhenReady(); }
                Component.onCompleted: { root.settled(window.screen.name, resourceSettled); window.showWhenReady(); }
                onFrameSubmitted: console.info("KOS_WALLPAPER_FRAME_SUBMITTED " + window.screen.name)
                onDecoded: console.info("KOS_WALLPAPER_DECODE_READY " + window.screen.name)
                onFallback: reason => console.info("KOS_WALLPAPER_FALLBACK " + reason)
            }
            onBackingWindowVisibleChanged: console.info("KOS_WALLPAPER_WINDOW " + screen.name + " " + backingWindowVisible)
            Component.onDestruction: { root.settled(modelData.name, false); console.info("KOS_WALLPAPER_DESTROYED"); }
        }
    }
}
