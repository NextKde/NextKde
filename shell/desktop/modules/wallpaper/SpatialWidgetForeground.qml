import QtQuick

// This item lives in the desktop's Bottom-layer window. It has no input
// press handlers; hovering only changes paint, leaving clicks to the widget.
Item {
    id: root
    property var targetScreen: null
    property var widgetRects: []
    property real pointerX: 0
    property real pointerY: 0
    property bool suspended: false
    readonly property bool meshRendererAvailable: subject.meshRendererAvailable
    readonly property bool ready: subject.visualReady && SpatialWallpaperService.layeredReady
    visible: ready && !suspended

    DepthWallpaperLayer {
        id: subject
        anchors.fill: parent
        targetScreen: root.targetScreen
        foregroundOnly: true
        renderingEnabled: SpatialWallpaperService.layeredReady
            && !root.suspended && root.widgetRects.length > 0
        pointerX: root.pointerX
        pointerY: root.pointerY
    }
    // One full-screen render is sampled by every card; there is no fixed
    // widget-count limit and no separate 3D scene per card.
    ShaderEffectSource {
        id: subjectTexture
        sourceItem: subject
        hideSource: true
        live: true
        visible: false
        textureSize: subject.textureSize
    }
    Repeater {
        model: root.widgetRects
        delegate: ShaderEffect {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            // Keep the item mapped while transparent. Its hover observer
            // must remain active until the pointer actually leaves the card.
            opacity: subject.opacity * (widgetHover.hovered ? 0 : 1)
            Behavior on opacity { NumberAnimation { duration: 140 } }
            HoverHandler { id: widgetHover }
            property var source: subjectTexture
            property vector2d viewport: Qt.vector2d(root.width, root.height)
            property vector4d rect: Qt.vector4d(x, y, width, height)
            fragmentShader: Qt.resolvedUrl("shaders/spatial_widget_clip.frag.qsb")
        }
    }
}
