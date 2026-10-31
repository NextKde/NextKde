import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import "../foundation" as Foundation

// Shared floating-panel material. Foreground controls belong outside this item.
Item {
    id: root
    property LiquidBackdrop backdrop: null
    property real cornerRadius: 14
    property real materialOpacity: LiquidStyle.panelMaterialOpacity
    property bool reduceTransparency: Foundation.AppTheme.reduceTransparency
    property bool darkAppearance: Foundation.AppTheme.dark
    property color tintColor: darkAppearance ? "#000000" : "#FFFFFF"
    // Tint is independent of the glass-layer opacity.
    property real tintStrength: darkAppearance ? 0.24 : 0.18
    property real blurStrength: 0.7
    property real refractionStrength: 8
    // Optional body-and-arrow optics used by the shared Popover surface.
    property bool popoverShape: false
    property real arrowHeight: 8
    property real arrowWidth: 18
    property real arrowX: width / 2
    property bool arrowOnBottom: false
    property real highlightStrength: 0.32
    property vector2d lightDirection: Qt.vector2d(-0.6, -0.8)
    property bool shadowEnabled: true
    readonly property real effectiveRadius: Math.max(1, Math.min(cornerRadius, width / 2, height / 2))
    readonly property bool canSample: !reduceTransparency && visible && backdrop !== null
        && backdrop.canSample(root) && GraphicsInfo.api !== GraphicsInfo.Software
        && width > 0 && height > 0
    readonly property bool sampling: canSample && mappingValid && optics.item !== null
        && optics.item.status !== ShaderEffect.Error
    property bool mappingValid: false
    property vector2d sampleOrigin: Qt.vector2d(0, 0)
    property vector2d sampleAxisX: Qt.vector2d(1, 0)
    property vector2d sampleAxisY: Qt.vector2d(0, 1)

    function updateMapping() {
        if (!canSample) { mappingValid = false; return }
        const scene = backdrop.sourceItem
        const origin = mapToItem(scene, 0, 0)
        const endX = mapToItem(scene, width, 0)
        const endY = mapToItem(scene, 0, height)
        sampleOrigin = Qt.vector2d(origin.x / scene.width, origin.y / scene.height)
        sampleAxisX = Qt.vector2d((endX.x - origin.x) / scene.width, (endX.y - origin.y) / scene.height)
        sampleAxisY = Qt.vector2d((endY.x - origin.x) / scene.width, (endY.y - origin.y) / scene.height)
        mappingValid = true
    }
    Component.onCompleted: Qt.callLater(updateMapping)
    onCanSampleChanged: Qt.callLater(updateMapping)
    onBackdropChanged: { mappingValid = false; Qt.callLater(updateMapping) }
    onWidthChanged: updateMapping()
    onHeightChanged: updateMapping()
    Connections {
        target: root.Window.window
        enabled: root.canSample
        function onAfterAnimating() { root.updateMapping() }
    }

    // The shadow follows the alpha of the actual G2 material, including fallback.
    layer.enabled: shadowEnabled && GraphicsInfo.api !== GraphicsInfo.Software
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowOpacity: 0.16
        shadowBlur: 0.65
        shadowVerticalOffset: 6
        blurMax: 32
        autoPaddingEnabled: true
    }

    // Matching fourth-order superellipse outline for the opaque fallback.
    // Dense vector segments keep the contour error below a physical pixel.
    readonly property string contour: {
        const r = effectiveRadius, w = width, h = height
        let path = "M " + r + " 0 L " + (w-r) + " 0"
        const corners = [[w-r,r,-Math.PI/2], [w-r,h-r,0], [r,h-r,Math.PI/2], [r,r,Math.PI]]
        for (const c of corners) {
            for (let i = 0; i <= 64; ++i) {
                const a = c[2] + Math.PI/2 * i/64
                const x = c[0] + r * Math.sign(Math.cos(a)) * Math.sqrt(Math.abs(Math.cos(a)))
                const y = c[1] + r * Math.sign(Math.sin(a)) * Math.sqrt(Math.abs(Math.sin(a)))
                path += " L " + x + " " + y
            }
        }
        return path + " Z"
    }
    Shape {
        anchors.fill: parent
        visible: !root.sampling
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: root.tintColor
            PathSvg { path: root.contour }
        }
    }
    Loader {
        id: optics
        anchors.fill: parent
        active: root.canSample && root.mappingValid
        sourceComponent: ShaderEffect {
            vertexShader: Qt.resolvedUrl(root.popoverShape ? "shaders/liquid_popover.vert.qsb" : "shaders/liquid_dialog.vert.qsb")
            fragmentShader: Qt.resolvedUrl(root.popoverShape ? "shaders/liquid_popover.frag.qsb" : "shaders/liquid_dialog.frag.qsb")
            property var source: root.backdrop.texture
            property vector2d surfaceSize: Qt.vector2d(root.width, root.height)
            property vector2d sampleOrigin: root.sampleOrigin
            property vector2d sampleAxisX: root.sampleAxisX
            property vector2d sampleAxisY: root.sampleAxisY
            property real radius: root.effectiveRadius
            property color tintColor: root.tintColor
            property real tintStrength: root.tintStrength
            property real blurRadius: root.blurStrength * 8
            property real readability: 0.22
            property real lightAppearance: root.darkAppearance ? 0 : 1
            property real refractionStrength: root.refractionStrength
            property real magnification: 1.015
            property real edgeWidth: 18
            property real diffuseStrength: 0
            property real materialOpacity: root.materialOpacity
            property real arrowHeight: root.arrowHeight
            property real arrowWidth: root.arrowWidth
            property real arrowX: root.arrowX
            property real arrowOnBottom: root.arrowOnBottom ? 1 : 0
            property real highlightStrength: root.highlightStrength
            property vector2d lightDirection: root.lightDirection
        }
    }
}
