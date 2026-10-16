import QtQuick
import QtQuick.Effects

// The frosted slab the app's floating panels sit on — the mode menu today, the
// unit picker later.
//
// What it blurs is the app's *own* content: the planes and the keypad are
// passed in as `backdrop` and re-rendered into a texture, so the panel never
// needs the compositor. That is the whole point of doing it here rather than
// through kwin's blur: a window this app owns can only ever have its own
// surfaces behind a popup, so there is nothing outside the app for the blur to
// reach for, and a self-contained effect cannot be broken by a compositor that
// declines to blur.
//
// Three layers, in order: a drop shadow, the blurred backdrop masked to the
// panel's rounded rect, and a translucent tint over it. The tint is what keeps
// the panel reading as a panel rather than as a hole — the blur alone is only
// ever as dark as what is behind it.
Item {
    id: root

    property var colors
    property Item backdrop: null
    property real radius: 29
    // How much of the panel's colour survives over the blur. Measured off the
    // reference: its slab sits at 31 where nothing is behind it and reaches 61
    // over the frosted keys, so the backdrop is carrying roughly half the
    // panel's brightness. 0.66 lands in the same place here — the panel reads
    // as a panel, and the keypad still comes through it as shapes.
    property real tintAlpha: 0.66
    property real shadowOffset: 6
    property real shadowOpacity: 0.32

    Rectangle {
        x: 0
        y: root.shadowOffset
        width: parent.width
        height: parent.height
        radius: root.radius
        color: "#000000"
        opacity: root.shadowOpacity
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 16; blur: 0.7 }
    }

    Loader {
        anchors.fill: parent
        active: root.backdrop !== null
        sourceComponent: Item {
            ShaderEffectSource {
                id: sample
                anchors.fill: parent
                sourceItem: root.backdrop
                // mapToItem has no geometry notifications of its own, so the
                // sampled rect is re-derived whenever anything above the panel
                // moves or resizes.
                sourceRect: {
                    let node = root
                    let geometry = 0
                    while (node) {
                        geometry += node.x + node.y + node.width + node.height
                        node = node.parent
                    }
                    const position = root.mapToItem(root.backdrop, 0, 0)
                    return Qt.rect(position.x, position.y, root.width, root.height)
                }
                textureSize: Qt.size(Math.ceil(root.width / 2), Math.ceil(root.height / 2))
                live: true
                visible: false
                smooth: true
            }

            Rectangle {
                id: shape
                anchors.fill: parent
                radius: root.radius
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: parent
                source: sample
                blurEnabled: true
                blurMax: 48
                // The reference's frosted content is a wash, not a legible
                // copy: the keys behind it have lost their edges entirely.
                blur: 0.8
                autoPaddingEnabled: false
                maskEnabled: true
                maskSource: shape
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.rgba(root.colors.menuSurface.r, root.colors.menuSurface.g,
                       root.colors.menuSurface.b, root.tintAlpha)
        border.color: root.colors.menuBorder
        border.width: 1
        antialiasing: true
    }
}
