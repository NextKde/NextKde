import QtQuick

// Shared settled composition. No transitions, service singletons or IPC.
Image {
    property string fitMode: "crop"
    property real pixelRatio: 1
    sourceSize: Qt.size(Math.max(1, Math.ceil(width * pixelRatio * 1.06)),
                        Math.max(1, Math.ceil(height * pixelRatio * 1.06)))
    fillMode: fitMode === "fit" ? Image.PreserveAspectFit
        : fitMode === "stretch" ? Image.Stretch
        : fitMode === "center" ? Image.Pad : Image.PreserveAspectCrop
    horizontalAlignment: Image.AlignHCenter
    verticalAlignment: Image.AlignVCenter
    autoTransform: true
    asynchronous: true
    cache: false
    smooth: true
}
