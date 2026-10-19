import QtQuick

// The unit beside each of the convert view's two numbers: the code, and the
// up/down chevron that opens the picker.
//
// The chevron stands taller than the code and is centred on it, so the chip's
// own height is the code's and the chevron simply overflows. That keeps the
// chip's top edge on the code's ascent line, which is where the display hangs
// it — an Item has no baseline of its own, so the parent anchors to the top and
// offsets by the ascent published here.
Item {
    id: root

    property var colors
    property string unit: ""
    property real fontSize: 14
    property real chevronSize: 14
    // Reference: the chevron stands 12 device px off the code, against a code
    // 76 wide — 16% of it.
    property real gap: 5

    signal clicked()

    // Where the code's baseline sits inside the chip, so the caller can line the
    // code up with the number beside it instead of guessing at the box. Named
    // `codeBaseline` rather than `baselineOffset` because Item already has a
    // property by that name and shadowing it makes the engine warn on every
    // load; a Text's own baselineOffset is its ascent, which is what is wanted
    // here.
    readonly property real codeBaseline: label.y + label.baselineOffset

    implicitWidth: label.width + (root.unit.length > 0 ? root.gap + chevron.width : 0)
    implicitHeight: label.implicitHeight

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: root.unit
        color: root.colors.convertUnit
        font.pixelSize: root.fontSize
    }

    CalculatorIcon {
        id: chevron
        visible: root.unit.length > 0
        anchors.verticalCenter: parent.verticalCenter
        x: label.width + root.gap
        name: "chevron"
        size: root.chevronSize
        strokeWidth: 2.3
        color: root.colors.convertUnit
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
