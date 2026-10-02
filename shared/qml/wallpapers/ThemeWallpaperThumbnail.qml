import QtQuick

// Gallery cards are still previews. Decode plates at card size rather than
// constructing full particle systems, animation shaders and float lookup maps.
Item {
    id: root
    property string themeId: "starfield"
    readonly property string plate: themeId === "blackhole" ? "assets/blackhole-cinematic-reference.png"
        : themeId === "forest" ? "assets/forest-cinematic.png"
        : themeId === "underwater" ? "assets/underwater-cinematic.png" : ""
    Image {
        anchors.fill: parent
        source: root.plate
        sourceSize: Qt.size(Math.max(1, Math.min(1024, Math.ceil(root.width * 2))),
            Math.max(1, Math.min(1024, Math.ceil(root.height * 2))))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
    Loader {
        anchors.fill: parent
        active: root.plate === ""
        sourceComponent: ThemeWallpaperScene {
            themeId: root.themeId
            economical: true
            particleCount: 24
            phase: 1.8
        }
    }
}
