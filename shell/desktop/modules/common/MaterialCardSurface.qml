import Quickshell
import QtQuick

// The Material form's card surface.
//
// Every desktop card gets its whole surface from here: the paint it draws and the
// region the compositor frosts behind it. The only thing a host may vary is the
// outline -- the rounded rectangle every card uses, or MaterialFlower's
// silhouette, which the clock draws. Colour, opacity and the frost itself are
// shared, so the clock is an ordinary card whose shape was cut to a flower, not a
// card with its own finish.
//
// There is deliberately no LiquidGlassPanel here and no SurfaceShape
// declaration, and that pair is what selects the Material finish: the compositor
// ties its liquid material (refraction, glints, liquid noise) to a declared
// shape, so a surface that declares none stays on the plain blur pipeline -- one
// frost for all seven cards. The glass forms declare a shape per card and keep
// the full finish.
Item {
    id: root

    // The positioned wrapper whose x/y are the card's surface coordinates; both
    // regions read them verbatim, exactly like RoundedBlurRegion.
    required property Item blurAnchor
    property real radius: 16
    // The card's paint. One value for every card, in whichever shape the outline
    // takes.
    property color fillColor: "transparent"
    property real fillOpacity: 1.0
    // The flower silhouette instead of the rounded rectangle.
    property bool flowerShaped: false
    property int flowerLobes: 12
    property real flowerAmplitude: 0.075

    // The outline the compositor frosts. Every card publishes one: the form is one
    // effect across all of them, and the shape is the only difference between a
    // card and the clock.
    readonly property var blurRegion: root.flowerShaped ? flowerRegion : rectRegion

    // The paint, in the outline's shape.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.flowerShaped
        color: root.fillColor
        opacity: root.fillOpacity
        border.width: 0
    }

    // The same paint, cut to the flower. Geometry is the polar curve
    // FlowerBlurRegion frosts, so the frost edge lands on the outline that is
    // actually drawn -- centred, and 18px smaller than the card's short side.
    MaterialFlower {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) - 18
        height: width
        visible: root.flowerShaped
        lobes: root.flowerLobes
        amplitude: root.flowerAmplitude
        fillColor: Qt.rgba(root.fillColor.r, root.fillColor.g,
            root.fillColor.b, root.fillOpacity)
        // No outline: no other card has one, and a stroke is exactly what would
        // make the clock read as a different surface at a glance.
        outlineWidth: 0
    }

    RoundedBlurRegion {
        id: rectRegion
        item: root.blurAnchor
        radius: root.radius
    }

    FlowerBlurRegion {
        id: flowerRegion
        item: root.blurAnchor
        active: root.flowerShaped
        lobes: root.flowerLobes
        amplitude: root.flowerAmplitude
    }
}
