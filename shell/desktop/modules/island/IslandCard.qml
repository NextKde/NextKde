import QtQuick
import qs.desktop.modules.common

// IslandCard — the raised, layered card the island uses for a widget and for
// a pinned application.
//
// The reference is macOS Stage Manager (台前调度): a card is not a painted
// rectangle, it is a thin plate floating above a stack of thinner plates,
// with a cast shadow that grows as it rises and a slight turn away from the
// light when it is picked up. Three separate cues carry that reading, and
// all three are reproduced here rather than approximated with one:
//
//   1. the stack — two plates peek out below-right of the card body, spread
//      apart by the lift, so the card reads as the front of a deck;
//   2. the turn  — a small Y-axis rotation, driven by `tilt`, which Qt
//      renders as a genuine Y-axis rotation of the whole subtree;
//   3. the cast  — KosCardShadow, which evaluates the card's own
//      superelliptical outline, so the shadow's hole and the card's edge
//      describe one curve instead of two that agree by convention.
//
// Drag translation is NOT part of this component. A card inside a positioned
// container cannot move itself: the parent re-applies its position, and a
// transform that fought the layout also made the pointer coordinates inside
// the card depend on the card's own offset -- a feedback loop that halved
// the travel and made the tilt jitter. The island's content moves the card
// through its position binding and keeps the pointer in a stable space.
Item {
    id: root

    // 0 = resting on the island, 1 = fully lifted. Shadow, stack spread and
    // scale all follow it, which is what sells the depth.
    property real lift: 0

    // -1 .. 1. The direction the card is turned towards. Drives the Y-axis
    // rotation, so a dragged card turns into the direction of travel.
    property real tilt: 0

    // Degrees around the card's own Y axis. The island uses it for the deck's
    // entrance: each tile starts edge-on and rotates flat, which is what makes
    // the icons read as being turned over rather than faded in.
    property real flipAngle: 0

    // Which way this panel folds: -1, 0 or 1. The seam is where the shade
    // goes -- without it a row of alternately rotated cards reads as a row of
    // slightly narrow cards, not as one folded sheet.
    property int foldLean: 0

    // Camera distance, in card widths. The rotation above already gives the
    // panel depth (rotating about Y moves points in z); this matrix is what
    // divides by that depth, which is the difference between a card that
    // merely gets narrower and one that recedes. Larger is flatter; below ~1
    // the near edge starts to blow up.
    property real foldDepth: 2.4

    // 0 = flat, 1 = the full two-plate stack. The app tiles use 1; the
    // widget cards use a little less so a row of them does not look busy.
    property real depth: 1

    property color bodyColor: Qt.rgba(1, 1, 1, 0.06)
    property color bodyBorderColor: Qt.rgba(1, 1, 1, 0.10)
    property color highlightColor: Qt.rgba(1, 1, 1, 0.14)
    // The plate behind the card. Kept separate from bodyColor so a tile can
    // read as glass in front and as a sliver of glass behind.
    property color stackColor: Qt.rgba(1, 1, 1, 0.10)

    property real cornerRadius: 22
    property real cornerExponent: AppearanceTokens.shape.cornerExponent

    // Contact shadow: tight and dark at rest, so the card reads as standing
    // on a surface rather than floating above it, then longer and softer as
    // it is lifted -- the same way a book pulled off a shelf casts a shadow
    // that leaves the shelf line behind.
    property real shadowOffsetX: 2 + lift * 7
    property real shadowOffsetY: 9 + lift * 15
    property real shadowSoftness: 13 + lift * 19
    property color shadowColor: Qt.rgba(0, 0, 0, 0.34 + lift * 0.26)

    implicitWidth: 100
    implicitHeight: 100

    // --- The stack --------------------------------------------------------
    // Two plates behind the body, each one smaller and further away. They are
    // painted first so the body covers all but their lower-right edge, which
    // is what makes the card look like it is sitting on top of something.
    Repeater {
        model: 2

        delegate: Rectangle {
            required property int index

            // The thickness of the slab. The reference card shows a second,
            // darker plate peeking out to the lower right, which is what
            // makes it read as an object with an edge instead of a picture
            // pasted on the panel.
            readonly property real step: (index + 1) * (4.5 + root.lift * 5.5)

            x: step
            y: step
            width: root.width
            height: root.height
            radius: root.cornerRadius
            color: root.stackColor
            opacity: root.depth * (index === 0 ? 1.0 : 0.55)
            visible: root.depth > 0.01
            z: -2 + index * 0.1
        }
    }

    // --- The cast shadow --------------------------------------------------
    KosCardShadow {
        cardWidth: root.width
        cardHeight: root.height
        cornerRadius: root.cornerRadius
        cornerExponent: root.cornerExponent
        offsetX: root.shadowOffsetX
        offsetY: root.shadowOffsetY
        softness: root.shadowSoftness
        shadowColor: root.shadowColor
        x: root.width / 2 - width / 2
        y: root.height / 2 - height / 2
        z: -1
    }

    // --- The card body ----------------------------------------------------
    // Its outline is drawn by the mask rather than by Rectangle.border: a
    // straight border is cut off wherever the mask's corner arc departs from
    // the rectangle edge.
    Rectangle {
        id: body
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.bodyColor
        layer.enabled: root.cornerExponent > 2.0
        layer.effect: SquircleMask {
            cornerRadius: root.cornerRadius
            cornerExponent: root.cornerExponent
            maskWidth: root.width
            maskHeight: root.height
            borderWidth: 1
            borderColor: root.bodyBorderColor
        }

        // The plate's own thickness: a vertical sheen that is brightest just
        // under the top edge and fades out by the middle, the same way a
        // glass or brushed surface catches a light from above.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10 + root.lift * 0.08) }
                GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.012) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.05) }
            }
        }

        // The fold seam. Drawn inside the body so the card's own mask trims
        // it to the silhouette.
        Rectangle {
            anchors.fill: parent
            visible: root.foldLean !== 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: root.foldLean > 0 ? "transparent" : Qt.rgba(0, 0, 0, 0.34)
                }
                GradientStop { position: 0.55; color: "transparent" }
                GradientStop {
                    position: 1.0
                    color: root.foldLean > 0 ? Qt.rgba(0, 0, 0, 0.34) : "transparent"
                }
            }
        }

        // The hairline highlight along the top edge.
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: root.cornerRadius * 0.75
                rightMargin: root.cornerRadius * 0.75
                topMargin: 1
            }
            height: 1
            color: root.highlightColor
        }
    }

    // --- The turn ---------------------------------------------------------
    // A real Y-axis rotation, not a horizontal squash: Qt transforms the
    // whole subtree through the axis, so the icon and the plate turn
    // together and the stack behind them stays put, which is what reads as
    // depth rather than as scaling.
    transform: [
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: root.flipAngle
        },
        // Perspective. Applied after the rotation so it divides by the depth
        // the rotation just created; with the origin at the card's centre the
        // divide is centred too, and the near edge grows while the far edge
        // shrinks -- which is what makes two adjacent panels read as one
        // folded sheet. Row 4 is the projection row: w = 1 - z / d.
        Matrix4x4 {
            matrix: Qt.matrix4x4(
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, -1 / Math.max(1, root.width) / root.foldDepth, 1)
        },
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: root.tilt * 16
        },
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 1; y: 0; z: 0 }
            angle: -root.lift * 7
        },
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: 1 + root.lift * 0.05
            yScale: 1 + root.lift * 0.05
        }
    ]
}
