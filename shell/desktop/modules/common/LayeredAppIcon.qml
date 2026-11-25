import QtQuick
import Quickshell.Widgets

// Same-canvas layers from an installed theme. Only the foreground receives the
// existing tonal tint shader; plate and highlights remain ordinary images.
Item {
    id: root
    required property var artwork
    property bool tinted: false
    property color tintColor: "#a855f7"
    property real opacityMultiplier: 1.0
    property int rasterSize: 64
    property bool smooth: true
    signal loadFailed()

    readonly property int imageStatus: !tinted ? clearImage.backer.status
        : baseImage.backer.status === Image.Error || foreground.backer.status === Image.Error || highlightsImage.backer.status === Image.Error
            ? Image.Error
            : baseImage.backer.status === Image.Ready && foreground.backer.status === Image.Ready && highlightsImage.backer.status === Image.Ready
                ? Image.Ready : Image.Loading
    readonly property real paintedWidth: tinted ? baseImage.backer.paintedWidth : clearImage.backer.paintedWidth
    readonly property real paintedHeight: tinted ? baseImage.backer.paintedHeight : clearImage.backer.paintedHeight
    onImageStatusChanged: if (imageStatus === Image.Error) Qt.callLater(reportFailure)
    Component.onCompleted: if (imageStatus === Image.Error) Qt.callLater(reportFailure)
    function reportFailure() {
        if (imageStatus === Image.Error) loadFailed()
    }

    opacity: opacityMultiplier
    IconImage {
        id: clearImage
        anchors.fill: parent
        visible: !root.tinted
        source: root.tinted ? "" : (root.artwork?.clear || "")
        smooth: root.smooth
        asynchronous: false
        backer.sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        backer.cache: IconThemeReloadService.pixmapCacheAllowed
    }
    IconImage {
        id: baseImage
        anchors.fill: parent
        visible: root.tinted
        source: root.tinted ? (root.artwork?.base || "") : ""
        smooth: root.smooth
        asynchronous: false
        backer.sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        backer.cache: IconThemeReloadService.pixmapCacheAllowed
    }
    IconImage {
        id: foreground
        anchors.fill: parent
        visible: false
        source: root.tinted ? (root.artwork?.foreground || "") : ""
        smooth: root.smooth
        asynchronous: false
        backer.sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        backer.cache: false
        layer.enabled: true
        layer.smooth: root.smooth
    }
    ShaderEffect {
        anchors.fill: parent
        visible: root.tinted
        property variant source: foreground
        property real opacityMult: 1.0
        property real sat: 0.0
        property real iconTintEnabled: 1.0
        property color iconTintColor: root.tintColor
        property real iconRecolorEnabled: 0.0
        property color iconRecolorColor: "white"
        fragmentShader: Qt.resolvedUrl("../../shaders/icon_effect.frag.qsb")
    }
    IconImage {
        id: highlightsImage
        anchors.fill: parent
        visible: root.tinted
        source: root.tinted ? (root.artwork?.highlights || "") : ""
        smooth: root.smooth
        asynchronous: false
        backer.sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        backer.cache: IconThemeReloadService.pixmapCacheAllowed
    }
}
