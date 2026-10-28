import QtQuick
import QtQuick.Window
import QtQuick.Effects

Item {
    id: root
    property Item sourceItem: null
    property bool active: true
    property bool registerAsDefault: true
    property bool hideSource: false
    property real resolutionScale: 1
    property int maximumTextureSize: 2048
    readonly property var hostWindow: root.Window.window
    readonly property bool available: active && sourceItem !== null && hostWindow !== null
        && sourceItem.Window.window === hostWindow
        && sourceItem.width > 0 && sourceItem.height > 0
        && sourceExcludesCapture()
    // Optional continuous prefilter for large glass panels; default is unchanged.
    property real blur: 0
    readonly property alias rawTexture: capture
    readonly property var texture: blur > 0 ? softened : capture

    function sourceExcludesCapture() {
        for (let ancestor = root; ancestor; ancestor = ancestor.parent) {
            if (ancestor === sourceItem) return false
        }
        return true
    }

    // Keep the capture separate from every consumer; never capture a whole window.
    function canSample(item) {
        if (!available || !item || item.Window.window !== hostWindow) return false
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            if (ancestor === sourceItem) return false
        }
        return true
    }

    visible: false
    Component.onCompleted: LiquidStyle.registerBackdrop(root)
    Component.onDestruction: LiquidStyle.unregisterBackdrop(root)

    MultiEffect {
        id: softened
        width: root.sourceItem ? root.sourceItem.width : 1
        height: root.sourceItem ? root.sourceItem.height : 1
        source: capture; visible: false; layer.enabled: root.blur > 0
        blurEnabled: root.blur > 0; blurMax: 64
        blur: Math.max(0, Math.min(1, root.blur)); autoPaddingEnabled: false
    }

    ShaderEffectSource {
        id: capture
        sourceItem: root.available ? root.sourceItem : null
        sourceRect: Qt.rect(0, 0, sourceItem ? sourceItem.width : 1, sourceItem ? sourceItem.height : 1)
        readonly property real captureScale: Math.min(
            Math.max(0.1, root.resolutionScale) * (root.hostWindow && root.hostWindow.screen ? root.hostWindow.screen.devicePixelRatio : 1),
            Math.max(1, root.maximumTextureSize) / Math.max(1, sourceRect.width, sourceRect.height))
        textureSize: Qt.size(Math.max(1, Math.ceil(sourceRect.width * captureScale)),
                             Math.max(1, Math.ceil(sourceRect.height * captureScale)))
        hideSource: root.hideSource
        live: true
        recursive: false
        smooth: true
        wrapMode: ShaderEffectSource.ClampToEdge
        visible: false
    }
}
