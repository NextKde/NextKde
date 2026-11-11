import QtQuick

BundledIcon {
    property real level: 0
    property bool muted: false
    size: 16
    name: muted ? "audio.output.muted" : level > 0.66 ? "audio.output.high"
        : level > 0.33 ? "audio.output.normal" : level > 0 ? "audio.output.low" : "audio.output.silent"
}
