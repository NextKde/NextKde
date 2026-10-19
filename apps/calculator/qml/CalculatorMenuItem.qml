import QtQuick
import QtQuick.Controls
import Kos.Ui

// One line of the mode menu: a tick column, a mark column, the label.
//
// The tick is ours rather than AbstractButton's. A checkable MenuItem writes
// `checked` imperatively on every click, which severs the binding that ties it
// to the calculator's own state — so the item the user did *not* click keeps a
// stale tick and the menu ends up with two of them. `selected` is a plain
// property the menu never writes, so the binding survives.
//
// The three columns are placed at fixed x rather than by a layout: their
// positions are what was measured off the reference (tick centre at 16, mark
// centre at 41, label at 64, all from the panel's content edge), and a layout
// would only redistribute them by its own spacing rules.
MenuItem {
    id: root

    property var colors
    property bool selected: false

    // The mark column is either a glyph this app already draws or a literal
    // string: "f(x)" is a typographic mark rather than a shape, so it is set in
    // text the way the reference sets it, and everything else is traced.
    property string iconName: ""
    property string iconText: ""
    property real iconSize: 21

    // Reference row pitch is 16.8% of the panel width, i.e. 38px.
    implicitHeight: visible ? 38 : 0
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0
    indicator: null

    contentItem: Item {
        implicitHeight: 38

        Text {
            x: 6
            width: 20
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.selected ? "✓" : ""
            color: root.colors.menuCheck
            font.pixelSize: 12
        }

        Item {
            x: 29
            width: 24
            height: 24
            anchors.verticalCenter: parent.verticalCenter

            CalculatorIcon {
                anchors.centerIn: parent
                visible: root.iconName.length > 0
                name: root.iconName
                size: root.iconSize
                strokeWidth: 2.0
                color: root.colors.menuText
            }

            Text {
                anchors.centerIn: parent
                visible: root.iconText.length > 0
                text: root.iconText
                color: root.colors.menuText
                font.pixelSize: 14
                font.italic: true
            }
        }

        Text {
            x: 64
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.colors.menuText
            font.pixelSize: 12
        }
    }

    // The row's feedback is the shell's own glass plate — the very component
    // its context menu uses — rather than a flat white wash: a vertical
    // gradient fill, a one-pixel rim and a specular glint along the flat part
    // of the top edge. A flat wash reads as a lighter rectangle laid on the
    // panel; the plate reads as a lens over it, which is what the reference's
    // frosted row is actually doing.
    //
    // Full strength here rather than the shell's 0.90: this panel is glass over
    // the keypad rather than an opaque surface, so the plate has to carry the
    // whole highlight on its own.
    background: SelectionHighlight {
        cornerRadius: 8
        dark: root.colors.dark
        hovered: root.highlighted
        pressed: root.down
        selected: root.selected
        fillStrength: 1.4
    }
}
