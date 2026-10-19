pragma ComponentBehavior: Bound

import QtQuick

// The key grid. Both keypads are this component with a different key table,
// cell size and key shape — the geometry lives here so a key never has to know
// which keypad it belongs to.
Item {
    id: root

    property var colors
    property var keys: []
    property real cellWidth: 80
    property real cellHeight: 80

    // Basic keys are circles inset inside their cell; scientific keys are
    // capsules inset inside theirs — the same shape at two sizes, which is what
    // the two references draw.
    property bool round: true
    property real gap: 5
    property real cornerRadius: 2

    property real fontSize: 32
    // The scientific keypad writes its six function columns a step smaller than
    // its number block — measured, 33 device px against 40 — so the label size
    // is the role's as much as the key's. Zero means "the keypad has one size",
    // which is what the basic keypad is.
    property real functionFontSize: 0
    property bool scientific: false
    property bool secondActive: false
    property bool radians: false

    signal keyPressed(string key)
    signal historyToggled()

    implicitWidth: cellWidth * 4
    implicitHeight: cellHeight * 5

    // The role a key carries is the colour group its own reference paints it
    // in, so neither of these has to know which keypad is being drawn: the
    // scientific table marks its whole dark group — the delete key included —
    // as "scientific", and only the basic table's AC / ± / % are "function".
    function roleFill(role) {
        if (role === "operator")
            return root.colors.keyOperator
        if (role === "scientific")
            return root.colors.sciKey
        if (role === "sciLight")
            return root.colors.sciKeyLight
        if (role === "function")
            return root.colors.keyFunction
        return root.scientific ? root.colors.sciKeyNumber : root.colors.keyNumber
    }

    // The reference writes white on every dark cell: the digits, the operators,
    // and the whole scientific keypad — whose function group is dark there too.
    // The basic keypad's light grey function keys are the only cells it writes
    // in black.
    function roleText(role) {
        if (role === "operator")
            return root.colors.textOnOperator
        if (role === "function")
            return root.colors.textOnFunction
        return root.colors.textOnNumber
    }

    // "2nd" swaps the six trig keys for their inverses, and the angle key
    // names the unit a press would switch to — the reference reads "Rad",
    // which is what it reads while the calculator is in degrees.
    function labelFor(key) {
        if (key.key === "Rad")
            return root.radians ? qsTr("Deg") : qsTr("Rad")
        if (root.secondActive && key.alternate)
            return key.alternate.label
        return key.label
    }

    function codeFor(key) {
        if (root.secondActive && key.alternate)
            return key.alternate.key
        return key.key
    }

    Repeater {
        model: root.keys

        delegate: CalculatorButton {
            required property var modelData

            x: (modelData.column || 0) * root.cellWidth
            y: (modelData.row || 0) * root.cellHeight
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            colSpan: modelData.columnSpan || 1
            rowSpan: modelData.rowSpan || 1
            // The wide key is a capsule on the basic keypad and a squircle once
            // it becomes the history toggle, matching the reference's two
            // shapes for the same key.
            round: root.round && !modelData.badge
            gap: root.gap
            cornerRadius: modelData.badge ? height * 0.3 : root.cornerRadius
            label: root.labelFor(modelData)
            iconName: modelData.icon || ""
            fontSize: root.functionFontSize > 0 && modelData.role === "scientific"
                ? root.functionFontSize : root.fontSize
            fill: root.roleFill(modelData.role)
            textColor: root.roleText(modelData.role)
            // Only "2nd" shows a latched state; the angle key reports itself
            // through its label alone, the way the reference's does.
            checked: modelData.key === "2nd" && root.secondActive
            onClicked: modelData.key === "@history"
                       ? root.historyToggled() : root.keyPressed(root.codeFor(modelData))
        }
    }
}
