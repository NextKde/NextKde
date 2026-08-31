import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets

// One renderer for application artwork across Dock, QuickSearch and Launcher.
// Layout owns width/height; this component owns source loading consistency.
// Supports grayscale + selective transparency + tonal tint via ShaderEffect.
Item {
    id: root
    property string source: ""

    // Icon appearance controls
    property real   opacityMultiplier: 1.0
    property real   saturation:        1.0
    property real   tintEnabled:       0.0
    property color  tintColor:         "#a855f7"
    property bool   asynchronous:      true
    property bool   smooth:            true

    IconImage {
        id: iconImage
        anchors.fill: parent
        source: root.source
        smooth: root.smooth
        asynchronous: root.asynchronous
        backer.cache: false
        visible: false
    }

    ShaderEffect {
        anchors.fill: iconImage
        property variant source: ShaderEffectSource { sourceItem: iconImage; hideSource: false }
        property real opacityMult: root.opacityMultiplier
        property real sat: root.saturation
        property real iconTintEnabled: root.tintEnabled
        property color iconTintColor: root.tintColor
        fragmentShader: Qt.resolvedUrl("../../shaders/icon_effect.frag.qsb")
    }
}
