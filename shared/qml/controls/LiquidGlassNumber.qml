import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "../foundation" as Foundation

// Display-only typography. The host owns formatting and the sibling backdrop.
Item {
    id: root
    property string text: "18°"
    property font font: Qt.font({ family: Qt.application.font.family, pixelSize: 144, weight: Font.Black })
    property LiquidBackdrop backdrop: LiquidStyle.backdropFor(root.Window.window)
    property real thickness: 5
    property real refractionStrength: 8
    property real blurRadius: 1.5
    property real tintStrength: 0.08
    property color tintColor: "#f1f6ff"
    property real reflectionStrength: 0.75
    property real shadowOpacity: 0.16
    property color fallbackColor: Foundation.AppTheme.text
    property bool reduceTransparency: Foundation.AppTheme.reduceTransparency
    readonly property real padding: Math.max(12, thickness * 2 + 4)
    readonly property bool canSampleBackdrop: !reduceTransparency && visible
        && width > 0 && height > 0 && GraphicsInfo.api !== GraphicsInfo.Software
        && backdrop !== null && backdrop.canSample(root)
    readonly property bool sampling: canSampleBackdrop && _mappingValid
        && optics.item !== null && optics.item.status !== ShaderEffect.Error
    property bool _mappingValid: false
    property vector2d _sampleOrigin: Qt.vector2d(0, 0)
    property vector2d _sampleAxisX: Qt.vector2d(1, 0)
    property vector2d _sampleAxisY: Qt.vector2d(0, 1)

    implicitWidth: glyph.implicitWidth + padding * 2
    implicitHeight: glyph.implicitHeight + padding * 2
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    function updateMapping() {
        if (!canSampleBackdrop) { _mappingValid = false; return }
        const source = backdrop.sourceItem
        const origin = mapToItem(source, 0, 0)
        const xEnd = mapToItem(source, width, 0)
        const yEnd = mapToItem(source, 0, height)
        _sampleOrigin = Qt.vector2d(origin.x / source.width, origin.y / source.height)
        _sampleAxisX = Qt.vector2d((xEnd.x-origin.x) / source.width, (xEnd.y-origin.y) / source.height)
        _sampleAxisY = Qt.vector2d((yEnd.x-origin.x) / source.width, (yEnd.y-origin.y) / source.height)
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
        enabled: root.canSampleBackdrop
        // Includes ancestor scrolling and 2D transforms; no animation owned here.
        function onAfterAnimating() { root.updateMapping() }
    }

    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        Text {
            id: glyph
            anchors.centerIn: parent
            text: root.text
            font: root.font
            color: "white"
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }
    ShaderEffectSource {
        id: glyphMask
        sourceItem: root.canSampleBackdrop ? maskItem : null
        width: root.width; height: root.height
        hideSource: true
        visible: false
        live: true
        smooth: true
    }
    MultiEffect {
        id: bevelMask
        width: root.width; height: root.height
        source: glyphMask
        visible: false
        layer.enabled: root.canSampleBackdrop
        blurEnabled: true
        blurMax: 16
        blur: Math.max(0.01, Math.min(1, root.thickness / 16))
        autoPaddingEnabled: false
    }
    Loader {
        id: optics
        anchors.fill: parent
        active: root.canSampleBackdrop && root._mappingValid
        sourceComponent: ShaderEffect {
            vertexShader: Qt.resolvedUrl("shaders/liquid_number.vert.qsb")
            fragmentShader: Qt.resolvedUrl("shaders/liquid_number.frag.qsb")
            property var source: root.backdrop ? root.backdrop.texture : null
            property var maskSource: glyphMask
            property var bevelSource: bevelMask
            property vector2d surfaceSize: Qt.vector2d(Math.max(1, width), Math.max(1, height))
            property vector2d sampleOrigin: root._sampleOrigin
            property vector2d sampleAxisX: root._sampleAxisX
            property vector2d sampleAxisY: root._sampleAxisY
            property real thickness: Math.max(0, root.thickness)
            property real refractionStrength: Math.max(0, root.refractionStrength)
            property real blurRadius: Math.max(0, root.blurRadius)
            property real tintStrength: Math.max(0, Math.min(1, root.tintStrength))
            property color tintColor: root.tintColor
            property real reflectionStrength: Math.max(0, root.reflectionStrength)
            property real shadowOpacity: Math.max(0, Math.min(1, root.shadowOpacity))
        }
    }
    Text {
        anchors.centerIn: parent
        visible: !root.sampling
        text: root.text
        font: root.font
        color: root.fallbackColor
        textFormat: Text.PlainText
        Accessible.ignored: true
    }
}
