import QtQuick

// Both grids share image-only thumbnails. Never instantiate the desktop
// renderer or recursive particle textures inside a gallery delegate.
Image {
    id: root
    property string themeId: "starfield"
    readonly property string plate: themeId === "blackhole" ? "assets/blackhole-cinematic-reference.png"
        : themeId === "forest" ? "assets/forest-cinematic.png"
        : themeId === "underwater" ? "assets/underwater-cinematic.png"
        : themeId === "weather" ? "assets/weather-thumbnail.png"
        : "assets/starfield-thumbnail.png"
    source: root.plate
    sourceSize: Qt.size(Math.max(1, Math.min(1024, Math.ceil(root.width * 2))),
        Math.max(1, Math.min(1024, Math.ceil(root.height * 2))))
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    smooth: true
}
