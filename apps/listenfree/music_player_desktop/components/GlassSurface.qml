import QtQuick
import QtQuick.Window
import QtQuick.Effects

Item {
    id: root

    property bool blockInput: false
    MouseArea { anchors.fill: parent; enabled: root.blockInput; acceptedButtons: Qt.AllButtons; hoverEnabled: true; onWheel: wheel => wheel.accepted = true }
    property real cornerRadius: 24
    property color tint: AppTheme.cardStrong
    property color edgeColor: AppTheme.border
    property real shadowOpacity: 0.16
    property real shadowOffset: frosted ? 5 : 7
    property Item backdrop: null
    property real backdropBlur: 32
    property bool opaqueBackdropBase: true
    property bool frosted: false
    property bool softShadow: frosted
    property real tintStrength: .16
    property real exclusionStrength: .04
    property real noiseStrength: .01

    Rectangle {
        x: 0; y: root.shadowOffset; width: parent.width; height: parent.height
        radius: root.cornerRadius
        color: root.softShadow ? "#000000" : AppTheme.darkMode ? "#52000000" : "#26000000"
        opacity: root.shadowOpacity
        layer.enabled: root.softShadow
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: .6 }
    }

    Loader {
        anchors.fill: parent
        active: root.backdrop !== null && root.visible
        sourceComponent: Item {
            // Cover the sharp scene before drawing its blurred sample. Without
            // this base, alpha in the sample exposes a second, unblurred copy.
            Rectangle { anchors.fill: parent; radius: root.cornerRadius; visible: root.opaqueBackdropBase; color: Qt.rgba(root.tint.r,root.tint.g,root.tint.b,1) }
            ShaderEffectSource {
                id: sample
                anchors.fill: parent
                sourceItem: root.backdrop
                sourceRect: {
                    // mapToItem itself has no geometry notifications. Observe
                    // ancestors so a move/resize also relocates the sampled area.
                    let node = root
                    let geometry = 0
                    while (node) { geometry += node.x + node.y + node.width + node.height; node = node.parent }
                    const position = root.mapToItem(root.backdrop, 0, 0)
                    return Qt.rect(position.x, position.y, root.width, root.height)
                }
                textureSize: Qt.size(Math.ceil(root.width / 2), Math.ceil(root.height / 2))
                live: true; visible: false; smooth: true
            }
            Rectangle { id: shape; anchors.fill: parent; radius: root.cornerRadius; visible: false; layer.enabled: true }
            MultiEffect {
                id: blurred
                anchors.fill: parent; source: sample
                blurEnabled: true; blurMax: 48; blur: root.backdropBlur / 48
                autoPaddingEnabled: false
                saturation: root.frosted ? 0 : -.3
                maskEnabled: !root.frosted; maskSource: shape
                maskThresholdMin: .5; maskSpreadAtMin: 1
                visible: !root.frosted
            }
            ShaderEffectSource {
                id: blurredTexture
                sourceItem: root.frosted ? blurred : null
                textureSize: Qt.size(Math.ceil(root.width/2),Math.ceil(root.height/2))
                hideSource: true; visible: false; smooth: true
            }
            ShaderEffect {
                anchors.fill: parent; visible: root.frosted
                property var source: blurredTexture
                property color tint: root.tint
                property vector2d surfaceSize: Qt.vector2d(width,height)
                property real radius: root.cornerRadius
                property real tintStrength: root.tintStrength
                property real exclusionStrength: root.exclusionStrength
                property real noiseStrength: root.noiseStrength
                fragmentShader: "qrc:/shaders/frosted-glass.frag.qsb"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.frosted
        radius: root.cornerRadius
        // One physical-pixel highlight; nested outlines read as a grey frame.
        border.width: 1 / Screen.devicePixelRatio
        border.pixelAligned: false
        border.color: Qt.alpha(root.edgeColor, root.edgeColor.a * .55)
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.lighter(root.tint, 1.08) }
            GradientStop { position: 0.52; color: root.tint }
            GradientStop { position: 1.0; color: Qt.darker(root.tint, 1.06) }
        }
    }
}
