import Quickshell
import QtQuick

// The Material form's card surface.
//
// Every desktop card gets its whole surface from here: the paint it draws and
// the region the compositor frosts behind it. The only thing a host may vary is
// the outline -- a rounded rectangle, or one of the shapes in MaterialShape.mjs,
// which is how one widget becomes a flower and the next a cookie. Colour,
// opacity and the frost itself are shared, so a shaped card is an ordinary card
// whose outline was cut differently, not a card with its own finish.
//
// There is deliberately no LiquidGlassPanel here and no SurfaceShape
// declaration, and that pair is what selects the Material finish: the compositor
// ties its liquid material (refraction, glints, liquid noise) to a declared
// shape, so a surface that declares none stays on the plain blur pipeline -- one
// frost for every card. The glass forms declare a shape per card and keep the
// full finish.
Item {
    id: root

    // The positioned wrapper whose x/y are the card's surface coordinates; both
    // regions read them verbatim, exactly like RoundedBlurRegion.
    required property Item blurAnchor
    property real radius: 16
    // The card's paint. One value for every card, in whichever shape the
    // outline takes.
    property color fillColor: "transparent"
    property real fillOpacity: 1.0
    // The outline: an empty string is the rounded rectangle above, anything else
    // is a name from MaterialShape.mjs. The shape fills the card on both axes --
    // see MaterialShape.qml -- so a wide card gets a wide petal rather than a
    // round one with empty margins.
    property string shape: ""
    // The shape's depth; see MaterialShape.strength.
    property real shapeStrength: 1

    readonly property bool shaped: root.shape.length > 0

    // The outline the compositor frosts. Every card publishes one: the form is
    // one effect across all of them, and the outline is the only difference
    // between one card and the next.
    readonly property var blurRegion: root.shaped ? shapeRegion : rectRegion

    // The paint, in the outline's shape.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.shaped
        color: root.fillColor
        opacity: root.fillOpacity
        border.width: 0
    }

    // The same paint, cut to the outline. No stroke: no other card has one, and
    // an outline is exactly what would make a shaped card read as a different
    // surface at a glance.
    MaterialShape {
        anchors.fill: parent
        visible: root.shaped
        shape: root.shape
        strength: root.shapeStrength
        fillColor: Qt.rgba(root.fillColor.r, root.fillColor.g,
            root.fillColor.b, root.fillOpacity)
        outlineWidth: 0
    }

    RoundedBlurRegion {
        id: rectRegion
        item: root.blurAnchor
        radius: root.radius
    }

    MaterialShapeBlurRegion {
        id: shapeRegion
        item: root.blurAnchor
        active: root.shaped
        shape: root.shape
        strength: root.shapeStrength
    }
}
