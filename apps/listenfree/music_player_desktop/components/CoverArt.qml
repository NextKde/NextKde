import QtQuick
import QtQuick.Window
import QtQuick.Effects

Item {
    id: root

    property url source: Qt.resolvedUrl("../assets/album_Cover_2.png")
    property url fallbackSource: ""
    property bool usingFallback: false
    property int recoveryAttempt: 0
    readonly property url effectiveSource: AppTheme.artworkUrl(root.usingFallback ? root.fallbackSource : root.source,root.sourcePixelSize)
    onEffectiveSourceChanged: { recoveryTimer.stop(); recoveryAttempt = 0; sourceStateTimer.restart() }
    readonly property bool missingArtwork: sourceImage.status !== Image.Ready || (sourceImage.implicitWidth <= 1 && sourceImage.implicitHeight <= 1)
    onSourceChanged: usingFallback = false
    onFallbackSourceChanged: { usingFallback = false; sourceStateTimer.restart() }
    function tryFallback() {
        if (!usingFallback && String(fallbackSource).length && String(fallbackSource) !== String(source)
                && (sourceImage.status === Image.Null || sourceImage.status === Image.Error
                    || (sourceImage.status === Image.Ready && sourceImage.implicitWidth <= 1 && sourceImage.implicitHeight <= 1)))
            usingFallback = true
    }
    function needsRecovery() {
        // Read Image directly: its status/size signals can run before the
        // derived missingArtwork binding has observed the successful decode.
        return root.visible && root.recoveryAttempt < 2
            && String(root.effectiveSource).indexOf("image://covers/") === 0
            && (sourceImage.status === Image.Error || (sourceImage.status === Image.Ready
                && sourceImage.implicitWidth <= 1 && sourceImage.implicitHeight <= 1))
    }
    function recoverIfMissing() {
        if (needsRecovery()) recoveryTimer.restart()
        else recoveryTimer.stop()
    }
    onVisibleChanged: recoverIfMissing()
    Component.onCompleted: sourceStateTimer.restart()
    Component.onDestruction: { sourceStateTimer.stop(); recoveryTimer.stop() }
    // Let source/status/size bindings settle together. The timer belongs to
    // this delegate, so a queued check cannot outlive its QML context.
    Timer {
        id: sourceStateTimer
        interval: 0
        onTriggered: { root.tryFallback(); root.recoverIfMissing() }
    }
    Timer {
        id: recoveryTimer
        interval: root.recoveryAttempt === 0 ? 350 : 1100
        // A pending retry must never discard an image that has since loaded.
        onTriggered: if (root.needsRecovery()) ++root.recoveryAttempt
    }
    readonly property Item dynamicTexture: motionLoader.item && motionLoader.item.ready ? motionLoader.item.output : null
    // Shape fills consume a cropped texture in logical item coordinates; the
    // layer normalizes source image dimensions and @2x density before sampling.
    readonly property Item artworkTexture: sourceImage
    property bool textureOnly: false
    readonly property Item dynamicFirstFrame: motionLoader.item && motionLoader.item.ready && motionLoader.item.frameCaptured ? motionLoader.item.firstFrame : null
    property url motionSource: ""
    property bool motionPlaying: true
    property string artworkTier: width <= 64 ? "Thumbnail" : width <= 128 ? "Small" : width <= 320 ? "Medium" : "Large"
    property real cornerRadius: 12
    // Compatibility for existing callers; covers now use bare rounded artwork.
    property bool showShadow: false
    // Hint the decoder so each usage tier can bound image memory explicitly.
    property int sourcePixelSize: AppTheme.artworkPixels(artworkTier, Screen.devicePixelRatio)

    // Keep a full-size backing even for successfully loaded transparent images.
    // It shares the cover bounds and has no inset shadow or outline.
    Rectangle {
        objectName: "coverPlaceholder"
        visible: !root.textureOnly
        anchors.fill: parent
        radius: root.cornerRadius
        color: "#8597a5"
        IconGlyph { anchors.centerIn: parent; width: Math.min(30,parent.width * .5); height: width; kind: "music"; glyphColor: "#e0ffffff"; visible: root.missingArtwork }
    }

    Image {
        id: sourceImage
        objectName: "coverSourceImage"
        anchors.fill: parent
        // A successful 1px missing-cover response is cached by Qt too. Retry
        // with a distinct key; keep retries uncached so a temporary failure
        // cannot poison subsequent delegates. Real covers keep normal caching.
        source: root.recoveryAttempt === 0 ? root.effectiveSource
            : String(root.effectiveSource) + (String(root.effectiveSource).indexOf("?") >= 0 ? "&" : "?") + "lf_retry=" + root.recoveryAttempt
        cache: root.recoveryAttempt === 0
        // Let the current source binding finish before choosing another URL.
        onStatusChanged: sourceStateTimer.restart()
        onImplicitWidthChanged: sourceStateTimer.restart()
        onImplicitHeightChanged: sourceStateTimer.restart()
        sourceSize.width: root.sourcePixelSize
        sourceSize.height: root.sourcePixelSize
        fillMode: Image.PreserveAspectCrop
        smooth: true
        mipmap: true
        visible: false
        // Only shape-fill consumers need a pre-cropped offscreen texture.
        // Ordinary covers sample the decoded Image directly below.
        layer.enabled: root.textureOnly
        layer.smooth: true
    }

    ShaderEffect {
        objectName: "staticCoverEffect"
        anchors.fill: parent
        visible: !root.textureOnly && !root.dynamicTexture
        property Item source: sourceImage
        property size surfaceSize: Qt.size(width, height)
        property real radius: root.cornerRadius
        fragmentShader: "qrc:/shaders/cover-rounded.frag.qsb"
    }

    Loader {
        id: motionLoader
        anchors.fill: parent
        active: AppTheme.videoAvailable && root.visible && root.motionSource.toString().length > 0
        Component.onCompleted: if (AppTheme.videoAvailable) setSource("CoverVideo.qml", {host: root})
    }

    Loader {
        anchors.fill: parent
        active: !root.textureOnly && !!root.dynamicTexture
        sourceComponent: Item {
            Rectangle {
                id: motionMask
                anchors.fill: parent
                radius: root.cornerRadius
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: root.dynamicTexture
                maskEnabled: true
                maskSource: motionMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
    }

}
