import QtQuick
import "modules/common"

// Smoke host for SquircleMask.qml. Loaded offscreen by run.mjs.
//
// There is no assertion on pixels here and there cannot be: this environment
// has no GPU context (QOffscreenIntegration's QRhiGles2 cannot create one
// without DRM, a display, or Xvfb), so ShaderEffect output is not observable.
// Concretely, that means this fixture catches a QML error, a missing or stale
// .qsb, and a call site naming a property the mask does not expose -- but not a
// shader uniform that no QML property feeds, because no pipeline is ever
// created. Verifying that the mask actually shapes a card needs a real session:
// set AppearanceTokens.shape.cornerExponent above 2.0 and look at a card.
Item {
    id: root

    width: 260
    height: 80

    // Mirrors how a real host wires this up: the mask's uniforms are bound to
    // an enclosing item's properties (NotificationWindow.qml does exactly this
    // for its cards), which only works because an inline layer.effect shares
    // the enclosing id scope.
    Rectangle {
        id: card

        width: 220
        height: 64
        radius: 18
        readonly property bool continuous: true
        readonly property color outline: Qt.rgba(1, 1, 1, 0.5)

        color: "transparent"
        layer.enabled: card.continuous
        layer.effect: SquircleMask {
            cornerRadius: card.radius
            cornerExponent: 4
            maskWidth: card.width
            maskHeight: card.height
            borderWidth: 1
            borderColor: card.outline
        }

        Rectangle {
            anchors.fill: parent
            radius: card.continuous ? 0 : card.radius
            color: Qt.rgba(0.1, 0.15, 0.22, 0.4)
        }
    }

    // Exponent 2 is the shipping default and must stay loadable, including the
    // path where maskWidth/maskHeight fall back to the effect's own size.
    Rectangle {
        y: 70
        width: 120
        height: 40

        layer.enabled: true
        layer.effect: SquircleMask {
            cornerRadius: 12
            cornerExponent: 2
        }
    }

    // Give the scene graph a frame to build the layer pipelines, so a failure
    // inside the effect surfaces before the shell exits.
    Timer {
        interval: 300
        running: true
        onTriggered: {
            console.log("SQUIRCLE_MASK_PASS")
            Qt.quit()
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.error("SQUIRCLE_MASK_FAIL: timeout")
            Qt.quit()
        }
    }
}
