import QtQuick

// The convert view's display: what the amount comes to and its unit above a
// rule, the expression that amount is on and its unit under it.
//
// The two numbers share a right edge and each unit code shares a baseline with
// the number beside it, which is what keeps the pair reading as one column
// rather than as two rows that happen to be stacked. Both insets are the
// reference's own, measured off its content box: the numbers stop a sixth of
// the box short of its right edge and the codes sit nearly flush with it.
Item {
    id: root

    property var colors
    // The two unit codes, and the two lines of text. The display only lays them
    // out; the store owns which units are paired and the arithmetic between
    // them.
    property string fromUnit: ""
    property string toUnit: ""
    property string fromValue: "0"
    property string toValue: "0"

    signal fromUnitClicked()
    signal toUnitClicked()
    signal swapClicked()

    // --- proportions --------------------------------------------------
    // Every one of these is a fraction of the content box's own width, taken
    // off the reference (see LEDGER, round 21) so the block scales with the box
    // rather than with the window. The font sizes are the reference's ink
    // heights divided by this app's own glyph-to-em ratio, measured in round 20
    // — an ink height is not a font size, and treating it as one is how a
    // display ends up a fifth too small.
    readonly property real resultFont: Math.round(width * 0.164)
    readonly property real sourceFont: Math.round(width * 0.138)
    readonly property real unitFont: Math.round(width * 0.048)
    readonly property real chevronSize: Math.round(width * 0.047)
    readonly property real swapSize: Math.round(width * 0.066)
    readonly property real resultRuleGap: width * 0.0355
    readonly property real ruleSourceGap: width * 0.0568
    // The gap under the block, to the top of the keypad's first row.
    readonly property real keypadGap: width * 0.0509
    // The rule does not start at the box's left edge: the swap mark sits in the
    // space it leaves, straddling where the line begins.
    readonly property real ruleLeftInset: width * 0.0509
    readonly property real swapCentre: width * 0.0337
    readonly property real chipRightInset: width * 0.0059
    readonly property real numberChipGap: width * 0.026

    TextMetrics {
        id: resultMetrics
        font: resultText.font
        text: "0"
    }

    TextMetrics {
        id: sourceMetrics
        font: sourceText.font
        text: "0"
    }

    // The ink, not the box: a Text's box top is the font's ascent line, well
    // above the digits, and the whole block is spaced off the ink. Text
    // publishes its own ascent as baselineOffset, and TextMetrics measures the
    // ink from the baseline — hence the sum, which is the drop from the box top
    // down to the first painted pixel.
    readonly property real resultInk: resultMetrics.tightBoundingRect.height
    readonly property real sourceInk: sourceMetrics.tightBoundingRect.height
    readonly property real resultInkDrop: resultText.baselineOffset
                                          + resultMetrics.tightBoundingRect.y
    readonly property real sourceInkDrop: sourceText.baselineOffset
                                          + sourceMetrics.tightBoundingRect.y

    readonly property real chipColumn: Math.max(topChip.implicitWidth,
                                                bottomChip.implicitWidth)
    // The reference's own inset, widened only when a long unit code would
    // otherwise run the chip into the number beside it.
    readonly property real numberRightInset: Math.max(width * 0.167,
        chipRightInset + chipColumn + numberChipGap)
    readonly property real numberWidth: Math.max(0, width - numberRightInset)
    readonly property real ruleY: resultInk + resultRuleGap
    readonly property real lowerInkTop: ruleY + 1 + ruleSourceGap

    implicitHeight: lowerInkTop + sourceInk

    Text {
        id: resultText
        x: 0
        y: -root.resultInkDrop
        width: root.numberWidth
        text: root.toValue
        color: root.colors.displayText
        font.pixelSize: root.resultFont
        font.weight: Font.Light
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
    }

    Text {
        id: sourceText
        x: 0
        y: root.lowerInkTop - root.sourceInkDrop
        width: root.numberWidth
        text: root.fromValue
        color: root.colors.displayExpression
        font.pixelSize: root.sourceFont
        font.weight: Font.Light
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
    }

    ConvertUnitChip {
        id: topChip
        colors: root.colors
        unit: root.toUnit
        fontSize: root.unitFont
        chevronSize: root.chevronSize
        x: root.width - root.chipRightInset - width
        y: resultText.y + resultText.baselineOffset - codeBaseline
        onClicked: root.toUnitClicked()
    }

    ConvertUnitChip {
        id: bottomChip
        colors: root.colors
        unit: root.fromUnit
        fontSize: root.unitFont
        chevronSize: root.chevronSize
        x: root.width - root.chipRightInset - width
        y: sourceText.y + sourceText.baselineOffset - codeBaseline
        onClicked: root.fromUnitClicked()
    }

    Rectangle {
        x: root.ruleLeftInset
        y: root.ruleY
        width: Math.max(0, root.width - root.ruleLeftInset)
        height: 1
        color: root.colors.convertRule
    }

    // The swap control rides the rule's left end, half of it past where the line
    // starts, which is where the reference puts it: it is centred on the space
    // the rule leaves rather than sitting inside the line.
    CalculatorIcon {
        id: swapIcon
        x: root.swapCentre - width / 2
        y: root.ruleY + 0.5 - height / 2
        name: "swap"
        size: root.swapSize
        strokeWidth: 1.9
        color: root.colors.keyOperator

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: root.swapClicked()
        }
    }
}
