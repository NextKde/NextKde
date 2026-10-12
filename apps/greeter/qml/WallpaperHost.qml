import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../wallpapers" as Wallpapers

Item {
    id: root
    property url source: ""
    property real decodeWidth: width
    property real decodeHeight: height
    property string fitMode: "crop"
    property real pixelRatio: root.Window.window ? root.Window.window.devicePixelRatio : 1
    // Only application-owned built-ins. Never accept a QML URL from a manifest.
    property string trustedTheme: ""
    property bool themeFailed: false
    property string verifiedTheme: ""
    property bool decodeFailed: false
    property bool submitted: false
    signal windowVisible(bool visible)
    signal frameSubmitted()
    readonly property bool themeAllowed: ["starfield", "blackhole", "weather", "forest", "underwater"].includes(trustedTheme)
    readonly property bool resourceReady: image.status === Image.Ready
    readonly property bool resourceSettled: source.toString() === "" || resourceReady || decodeFailed || image.status === Image.Error
    readonly property var composition: ({
        painted: [image.paintedWidth, image.paintedHeight],
        offset: [(width - image.paintedWidth) / 2, (height - image.paintedHeight) / 2],
        decodeBudget: [image.sourceSize.width, image.sourceSize.height],
        decodedSize: [image.implicitWidth, image.implicitHeight],
        dpr: image.pixelRatio
    })
    signal decoded()
    signal fallback(string reason)
    signal themeResourceReady()
    clip: true
    onTrustedThemeChanged: Qt.callLater(requestTheme)
    function requestTheme() {
        themeFailed = false; verifiedTheme = ""; submitted = false;
        if (themeAllowed) { themeDeadline.restart(); themeCheck.running = true; }
        else if (trustedTheme !== "") fallback("untrusted-theme");
    }
    Connections {
        target: root.Window.window
        function onVisibleChanged() { root.windowVisible(root.Window.window.visible); }
        function onFrameSwapped() {
            if (!root.submitted) { root.submitted = true; root.frameSubmitted(); }
        }
    }
    Rectangle { anchors.fill: parent; color: "#16283b" }
    Wallpapers.StaticWallpaperImage {
        id: image
        anchors.fill: parent
        source: root.decodeFailed ? "" : root.source
        fitMode: root.fitMode
        pixelRatio: root.pixelRatio
        sourceSize: Qt.size(Math.max(1, Math.ceil(root.decodeWidth * root.pixelRatio * 1.06)),
                            Math.max(1, Math.ceil(root.decodeHeight * root.pixelRatio * 1.06)))
        visible: status === Image.Ready
        onStatusChanged: {
            if (status === Image.Ready) { deadline.stop(); root.submitted = false; root.decoded(); }
            else if (status === Image.Error) { deadline.stop(); root.fallback("decode-error"); }
        }
    }
    onSourceChanged: { decodeFailed = false; submitted = false; deadline.restart(); }
    Timer {
        id: deadline; interval: 3000
        onTriggered: { if (!root.resourceReady) { root.decodeFailed = true; root.fallback("decode-timeout"); } }
    }
    Process {
        id: themeCheck
        command: ["/usr/bin/python3", Quickshell.shellDir + "/companion/theme.py", root.trustedTheme]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (result.theme !== root.trustedTheme) return;
                    if (result.ready) root.verifiedTheme = result.theme;
                    else { root.themeFailed = true; root.fallback("theme-dependencies"); }
                } catch (_) { root.themeFailed = true; root.fallback("theme-check-error"); }
            }
        }
    }
    Loader {
        id: theme
        anchors.fill: parent
        active: root.themeAllowed && root.verifiedTheme === root.trustedTheme && !root.themeFailed
        visible: false
        sourceComponent: Wallpapers.ThemeWallpaperScene {
            themeId: root.trustedTheme
            packResolver: null
            phase: 0; foreground: false; economical: true; particleCount: 0
            widgetRects: []; pointer: Qt.vector4d(-10,-10,0,0)
            clickPulse: Qt.vector4d(-10,-10,-100,0)
            weatherAvailable: false; weatherCode: 0; isDay: true
            windStrength: 0.15; windDirection: 0; temperature: "--°"; city: "大气光场"
            onFrameReady: { theme.visible = true; themeDeadline.stop(); root.themeResourceReady(); }
        }
        onStatusChanged: if (status === Loader.Error) { root.themeFailed = true; root.fallback("theme-error"); }
    }
    Timer {
        id: themeDeadline; interval: 3000; running: root.themeAllowed
        onTriggered: { themeCheck.running = false; root.themeFailed = true; root.fallback("theme-timeout"); }
    }
}
