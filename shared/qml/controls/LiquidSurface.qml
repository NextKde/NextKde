import QtQuick
import QtQuick.Window
import "../foundation" as Foundation

Item {
    id: root
    property real radius: 20
    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.Window.window)
    property bool darkAppearance: Foundation.AppTheme.dark
    property color tintColor: darkAppearance ? "#141c30" : "#ffffff"
    property real tintStrength: 0.08
    property real blurStrength: 0.45
    property real readability: 0.47
    property real refractionStrength: 3
    property real magnification: 1.025
    property real edgeWidth: 12
    property real reflectionStrength: 1
    property color rimColor: darkAppearance ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.45)
    readonly property bool sampling: canSampleBackdrop && _mappingValid
        && optics.status !== ShaderEffect.Error
    readonly property bool canSampleBackdrop: backdrop !== null && backdrop.canSample(root)
        && width > 0 && height > 0 && GraphicsInfo.api !== GraphicsInfo.Software
    property bool _mappingValid: false
    property vector2d _sampleOrigin: Qt.vector2d(0, 0)
    property vector2d _sampleAxisX: Qt.vector2d(1, 0)
    property vector2d _sampleAxisY: Qt.vector2d(0, 1)

    function updateMapping() {
        if (!canSampleBackdrop) { _mappingValid = false; return }
        const source = backdrop.sourceItem
        const origin = mapToItem(source, 0, 0)
        const endX = mapToItem(source, width, 0)
        const endY = mapToItem(source, 0, height)
        _sampleOrigin = Qt.vector2d(origin.x / source.width, origin.y / source.height)
        _sampleAxisX = Qt.vector2d((endX.x - origin.x) / source.width, (endX.y - origin.y) / source.height)
        _sampleAxisY = Qt.vector2d((endY.x - origin.x) / source.width, (endY.y - origin.y) / source.height)
        _mappingValid = true
    }

    Component.onCompleted: Qt.callLater(updateMapping)
    onBackdropChanged: { _mappingValid = false; Qt.callLater(updateMapping) }
    onCanSampleBackdropChanged: Qt.callLater(updateMapping)
    onXChanged: updateMapping()
    onYChanged: updateMapping()
    onWidthChanged: updateMapping()
    onHeightChanged: updateMapping()
    Connections {
        target: root.Window.window
        enabled: root.visible && root.canSampleBackdrop
        // Also follows ancestor scrolling, rotation and animated scale.
        function onAfterAnimating() { root.updateMapping() }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.sampling
        radius: root.radius
        color: root.tintColor
        opacity: Math.max(0, Math.min(1, root.tintStrength))
    }
    ShaderEffect {
        id: optics
        anchors.fill: parent
        visible: root.canSampleBackdrop && root._mappingValid
        vertexShader: Qt.resolvedUrl("shaders/liquid_surface.vert.qsb")
        fragmentShader: Qt.resolvedUrl("shaders/liquid_surface.frag.qsb")
        property var source: root.canSampleBackdrop ? root.backdrop.texture : null
        property vector2d surfaceSize: Qt.vector2d(Math.max(1, root.width), Math.max(1, root.height))
        property vector2d sampleOrigin: root._sampleOrigin
        property vector2d sampleAxisX: root._sampleAxisX
        property vector2d sampleAxisY: root._sampleAxisY
        property real radius: root.radius
        property color tintColor: root.tintColor
        property real tintStrength: root.tintStrength
        property real blurRadius: Math.max(0, root.blurStrength) * 8
        property real readability: root.readability
        property real lightAppearance: root.darkAppearance ? 0 : 1
        property real refractionStrength: root.refractionStrength
        property real magnification: root.magnification
        property real edgeWidth: root.edgeWidth
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        opacity: Math.max(0, Math.min(1, root.reflectionStrength))
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.18) }
            GradientStop { position: 0.2; color: Qt.rgba(1, 1, 1, 0.035) }
            GradientStop { position: 0.7; color: "transparent" }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        }
        border.width: 1
        border.color: root.rimColor
    }
}
