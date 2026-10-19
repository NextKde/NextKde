import QtQuick
import QtQuick.Controls

// The hairline the reference puts between the calculator modes and "Convert".
//
// It takes about half a row's pitch with the line centred in it, which is what
// the measurement gives: 8.4% of the panel's width of extra gap against a row's
// 38 pixels.
//
// Written as a MenuItem rather than as a MenuSeparator because a row is what
// the menu's column already knows how to stretch — a separator carries no width
// of its own and would come out invisible. The line is drawn in the background
// for the same reason: the background is the one child the control guarantees
// spans the whole row.
MenuItem {
    id: root

    property var colors

    enabled: false
    implicitHeight: visible ? 19 : 0
    indicator: null

    contentItem: Item {
        implicitHeight: 19
    }

    background: Item {
        Rectangle {
            // The panel's own padding, which is what keeps the rule inside the
            // rows' highlight rather than running under the panel's edge.
            x: 9
            width: Math.max(0, parent.width - 18)
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: root.colors.menuSeparator
        }
    }
}
