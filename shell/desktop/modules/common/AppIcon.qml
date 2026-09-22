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
    property bool   smooth:            true

    // Icon loads must stay on the GUI thread. QIcon::fromTheme() hands back
    // QIcons from a process-wide cache, and under the KDE platform theme every
    // one of them holds a KF6 KIconEngine, which is not thread-safe.
    // Asynchronous loading makes Qt run Quickshell's image provider on its
    // pixmap-reader thread, which then races the GUI thread's own icon lookups
    // and segfaults inside KIconEngine::createPixmap. Only enable this for
    // sources that never reach the icon provider (plain files, bundled assets).
    property bool   asynchronous:      false

    // The shader pass only earns its FBO when it actually rewrites pixels:
    // desaturation, tonal tint, or the dimmed monochrome opacity. In the
    // default color mode all three are identity, so the icon draws directly
    // and skips both the FBO allocation and the second rasterization.
    readonly property bool needsEffect: saturation !== 1.0
        || tintEnabled !== 0.0 || opacityMultiplier !== 1.0

    IconImage {
        id: iconImage
        anchors.fill: parent
        source: root.source
        smooth: root.smooth
        asynchronous: root.asynchronous
        backer.cache: false
        visible: !root.needsEffect
        // Provide a live texture directly to ShaderEffect. A separate
        // ShaderEffectSource keeps an extra QQuickItem alive across a
        // LayerShell window hide/show and can crash Qt Quick during cleanup.
        layer.enabled: root.needsEffect
        layer.smooth: root.smooth
    }

    ShaderEffect {
        anchors.fill: iconImage
        visible: root.needsEffect
        property variant source: iconImage
        property real opacityMult: root.opacityMultiplier
        property real sat: root.saturation
        property real iconTintEnabled: root.tintEnabled
        property color iconTintColor: root.tintColor
        fragmentShader: Qt.resolvedUrl("../../shaders/icon_effect.frag.qsb")
    }
}
