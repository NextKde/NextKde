import QtQuick

// Both grids share image-only thumbnails. Never instantiate the desktop
// renderer or recursive particle textures inside a gallery delegate.
Image {
    id: root
    property string themeId: "starfield"
    // Each built-in theme folder owns its preview plate; the path mirrors the
    // one-folder-per-theme layout (assets/ inside themes/<id>/).
    readonly property url plate: Qt.resolvedUrl((themeId === "blackhole" ? "themes/blackhole"
        : themeId === "forest" ? "themes/forest"
        : themeId === "underwater" ? "themes/underwater"
        : themeId === "weather" ? "themes/weather"
        : "themes/starfield") + "/assets/preview.png")
    source: root.plate
    sourceSize: Qt.size(Math.max(1, Math.min(1024, Math.ceil(root.width * 2))),
        Math.max(1, Math.min(1024, Math.ceil(root.height * 2))))
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    smooth: true
}
