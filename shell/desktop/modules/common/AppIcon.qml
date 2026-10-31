import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell.Widgets

// One renderer for application artwork across Dock, QuickSearch and Launcher.
// Layout owns width/height; this component owns source loading consistency.
// Supports grayscale, transparency, tonal tint and flat tray ink via ShaderEffect.
Item {
    id: root
    property string source: ""
    readonly property int imageStatus: renderer.item?.imageStatus ?? Image.Null

    // Icon appearance controls
    property real   opacityMultiplier: 1.0
    property real   saturation:        1.0
    property real   tintEnabled:       0.0
    property color  tintColor:         "#a855f7"
    property bool   recolorEnabled:    false
    property color  recolorColor:      "white"
    property bool   smooth:            true

    // Icon loads must stay on the GUI thread. QIcon::fromTheme() hands back
    // QIcons from a process-wide cache, and under the KDE platform theme every
    // one of them holds a KF6 KIconEngine, which is not thread-safe.
    // Asynchronous loading makes Qt run Quickshell's image provider on its
    // pixmap-reader thread, which then races the GUI thread's own icon lookups
    // and segfaults inside KIconEngine::createPixmap. Only enable this for
    // sources that never reach the icon provider (plain files, bundled assets).
    property bool   asynchronous:      false

    // The icon provider handles display scaling itself. Raw artwork (including
    // bundled SVG data URLs) needs an explicit size in physical pixels;
    // IconImage otherwise rasterizes it at the smaller logical display size.
    readonly property int rasterSize: Math.max(1, Math.ceil(
        Math.min(width, height)
        * (source.startsWith("image://") ? 1 : Math.max(1, Screen.devicePixelRatio))))

    // The shader pass only earns its FBO when it actually rewrites pixels:
    // desaturation, tonal tint, or the dimmed monochrome opacity. In the
    // default color mode these inputs are identity, so the icon draws directly
    // and skips both the FBO allocation and the second rasterization.
    readonly property bool needsEffect: saturation !== 1.0
        || tintEnabled !== 0.0 || opacityMultiplier !== 1.0 || recolorEnabled

    // The artwork is two components rather than one tree with a binding on
    // `layer.enabled`, and that is load-bearing. Enabling a layer on an item
    // that has already painted never renders that layer: the icon stays blank
    // until something else rebuilds it, which is why the Dock only brought an
    // icon back after it was clicked, while icons created while the mode was
    // already on were fine. Swapping the Loader destroys the old tree and
    // builds the new one in the same frame, so entering or leaving the effect
    // path always yields artwork that was born in the state it is shown in.
    Loader {
        id: renderer
        anchors.fill: parent
        sourceComponent: root.needsEffect ? effectIcon : directIcon
    }

    // IconImage exposes image metrics through backer, not on its wrapper.
    // Both renderer paths report the same aspect-fitted artwork dimensions.
    readonly property real paintedWidth: renderer.item ? renderer.item.paintedWidth : 0
    readonly property real paintedHeight: renderer.item ? renderer.item.paintedHeight : 0

    Component {
        id: directIcon

        IconImage {
            readonly property int imageStatus: backer.status
            readonly property real paintedWidth: backer.paintedWidth
            readonly property real paintedHeight: backer.paintedHeight
            source: root.source
            smooth: root.smooth
            asynchronous: root.asynchronous
            backer.sourceSize: Qt.size(root.rasterSize, root.rasterSize)
            // Direct rendering can safely reuse Qt Quick's decoded pixmap.
            backer.cache: IconThemeReloadService.pixmapCacheAllowed
        }
    }

    Component {
        id: effectIcon

        Item {
            readonly property int imageStatus: effectImage.backer.status
            readonly property real paintedWidth: effectImage.backer.paintedWidth
            readonly property real paintedHeight: effectImage.backer.paintedHeight
            IconImage {
                id: effectImage
                anchors.fill: parent
                source: root.source
                smooth: root.smooth
                asynchronous: root.asynchronous
                backer.sourceSize: Qt.size(root.rasterSize, root.rasterSize)
                // The effect path owns a live layer texture and cannot share
                // Qt Quick's decoded pixmap with anyone.
                backer.cache: false
                visible: false
                // Provide a live texture directly to ShaderEffect. A separate
                // ShaderEffectSource keeps an extra QQuickItem alive across a
                // LayerShell window hide/show and can crash Qt Quick during
                // cleanup.
                layer.enabled: true
                layer.smooth: root.smooth
            }

            ShaderEffect {
                anchors.fill: parent
                property variant source: effectImage
                property real opacityMult: root.opacityMultiplier
                property real sat: root.saturation
                property real iconTintEnabled: root.tintEnabled
                property color iconTintColor: root.tintColor
                property real iconRecolorEnabled: root.recolorEnabled ? 1.0 : 0.0
                property color iconRecolorColor: root.recolorColor
                fragmentShader: Qt.resolvedUrl("../../shaders/icon_effect.frag.qsb")
            }
        }
    }
}
