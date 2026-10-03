import QtQuick

// Thin host for the theme wallpaper pipeline. Owns the shell-facing inputs
// (the API ThemeWallpaperLayer binds) and dispatches to the per-theme scene
// file implementing ThemeSceneContract. Adding a theme is one scene file plus
// one branch in sceneUrl(); the host carries no per-theme logic.
Item {
    id: root
    property string themeId: "starfield"
    property real phase: 0
    property bool foreground: false
    property bool economical: false
    property int particleCount: 80
    property var widgetRects: []
    property vector4d pointer: Qt.vector4d(-10,-10,0,0)
    property vector4d clickPulse: Qt.vector4d(-10,-10,-100,0)
    property int weatherCode: 0
    property real windStrength: 0.15
    property real windDirection: 0
    property bool isDay: true
    property bool weatherAvailable: false
    property string temperature: "--°"
    property string city: "大气光场"
    signal frameReady()
    clip: true

    // Resolves marketplace pack themes: id -> file:// URL of the pack's entry
    // QML, or null/"" when the id is not an installed pack. Injected by the
    // deskcenter layer (ThemeWallpaperService.entryUrl) so this shared module
    // keeps no dependency on qs.desktop. Packs take priority over built-ins;
    // a built-in scene remains the fallback for every known id.
    property var packResolver: null

    function sceneUrl(id) {
        const pack = packResolver ? String(packResolver(id) || "") : ""
        if (pack) return pack
        // Built-in themes live one folder per theme under themes/, in exactly
        // the same layout as an installed pack; "builtin" only means the
        // folder ships with the shell instead of arriving via the packs root.
        switch (id) {
        case "blackhole": return Qt.resolvedUrl("themes/blackhole/main.qml")
        case "weather": return Qt.resolvedUrl("themes/weather/main.qml")
        case "underwater": return Qt.resolvedUrl("themes/underwater/main.qml")
        case "forest": return Qt.resolvedUrl("themes/forest/main.qml")
        default: return Qt.resolvedUrl("themes/starfield/main.qml")
        }
    }

    Loader {
        id: themeLoader
        anchors.fill: parent
        source: root.sceneUrl(root.themeId)
        onLoaded: item.host = root
    }
    Connections {
        target: themeLoader.item
        function onFrameReady() { root.frameReady() }
    }
}
