pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Kos.Ui
import "CalculatorKeys.js" as KeyTables

KosApplicationWindow {
    id: root

    modernDesign: true
    visible: true
    title: qsTr("Calculator")

    // --- view state ---------------------------------------------------
    // Both views are entered by clicking, never by dragging. The window has
    // exactly two sizes and neither of them is the user's to pick: min and max
    // are pinned to the target below, so kwin never starts an interactive
    // resize and there is no drag for the app to fight. That is also what the
    // reference app does — its standard and scientific calculators are two
    // fixed sizes — and it means the app never has to guess that a drag has
    // ended, which wayland does not report.
    property bool scientific: false
    property bool historyVisible: false
    // The third mode. It is a mode rather than a second axis — the reference
    // ticks it alongside "Basic", but its own convert screen is a phone-width
    // keypad with a two-row display, and there is no reference for what a
    // scientific keypad under that display would look like. So Convert puts the
    // basic keypad back and remembers nothing about which axis was showing.
    property bool converting: false

    // --- window sizing ------------------------------------------------
    readonly property int basicWidth: 360
    readonly property int scientificWidth: 1000
    // One height for both views. At 1000 wide this puts the scientific display
    // strip at 22.8% of the content box against the reference's 26.2%; the 760
    // this used to be was the real cause of the blank display above the number
    // (see LEDGER, round 14).
    readonly property int windowHeight: 560

    // Reference proportions, measured off the landscape scientific reference
    // (2000x923 device, i.e. 871x402 logical): a cell is 72.54 wide by 47.04
    // tall, and the capsule inside it is inset 4.09 on every side — which is
    // what makes the key 64.5 by 38.8 and its corners a half-height radius.
    readonly property real scientificCellAspect: 0.648
    readonly property real scientificKeyInset: 0.0564

    readonly property int historyPaneWidth: 340
    readonly property int paneSeamWidth: 1
    readonly property int gridBottomInset: 7

    // The window is a kwin-rounded panel and this app draws no corner of its
    // own: the chrome planes stop `chromeMargin` short of every edge, so
    // nothing of ours reaches the corner kwin cuts. KosApplicationWindow's
    // windowCornerRadius is untouched — the margin is what keeps the two from
    // meeting.
    readonly property int chromeMargin: 20

    // The 20px band around the content box must not read as a border: the
    // shared background paints AppTheme.windowSurface (a different tone from
    // the keypad plane), so it is retinted to the same plane colour.
    background: Rectangle {
        color: palette.plane
    }

    // The one place the window's size is decided. Pinning min and max to the
    // same number is what makes the window undraggable: kwin is handed
    // matching size hints, never begins an interactive resize, and so there is
    // no drag to fight and nothing to snap back to. The history column rides
    // on top of whichever width is current rather than being a size of its
    // own.
    readonly property int windowWidth: (scientific ? scientificWidth : basicWidth)
        + (historyVisible ? historyPaneWidth + paneSeamWidth : 0)
    minimumWidth: windowWidth
    maximumWidth: windowWidth
    minimumHeight: windowHeight
    maximumHeight: windowHeight
    onWindowWidthChanged: width = windowWidth
    Component.onCompleted: {
        width = windowWidth
        height = windowHeight
    }

    // --- keypad geometry ----------------------------------------------
    // Everything the keypad lays out against is measured inside the window's
    // margin: the planes are the content box, not the window.
    readonly property real contentWidth: width - chromeMargin * 2
    readonly property real contentHeight: height - chromeMargin * 2

    readonly property real keypadPaneX: historyVisible
        ? historyPaneWidth + paneSeamWidth : 0
    readonly property real keypadPaneWidth: contentWidth - keypadPaneX

    // The reference gives its display strip 26.2% of the window height, top of
    // window to top of keypad. This is that plus the clearance the expression
    // line needs under the mode button the window keeps in its top-right
    // corner: at the reference's own figure the line clears the button by three
    // pixels and reads as crammed against it. The keys pay for the difference,
    // 74.3 against the reference's 74.9 logical pixels — which is to say, they
    // do not really pay at all.
    readonly property real displayHeight: contentHeight * 0.272
    readonly property real basicCell: Math.min(keypadPaneWidth / 4,
        (contentHeight - gridBottomInset - displayHeight) / 5)

    // Scientific cells grow with width but are capped so the 10x5 grid plus a
    // usable display strip always fit the fixed window height — past the cap
    // the grid stops growing and stays centred (same policy as basicCell).
    readonly property real scientificCellWidth: Math.min(keypadPaneWidth / 10,
        (contentHeight - gridBottomInset - displayHeight) / 5 / scientificCellAspect)
    readonly property real scientificCellHeight: scientificCellWidth * scientificCellAspect
    readonly property real scientificGridHeight: scientificCellHeight * 5

    readonly property real activeCell: scientific ? scientificCellWidth : basicCell
    readonly property real gridHeight: scientific ? scientificGridHeight : basicCell * 5
    readonly property real gridTop: contentHeight - gridBottomInset - gridHeight
    // The keypad is centred in its pane, so this is both its own width and the
    // line its rightmost column ends on.
    readonly property real keypadWidth: scientific ? scientificCellWidth * 10
                                                   : basicCell * 4

    readonly property real displayFontSize: Math.round(contentHeight * 0.157)
    // The expression line is 0.366 of the result's own glyph height in the
    // reference (26 device px against 71), which the two sharing one family
    // makes a font-size ratio as well.
    readonly property real expressionFontSize: Math.round(displayFontSize * 0.366)
    // And the air between the two is 0.88 of the expression's glyph height
    // there (23 device px against 26), so the pair reads as a stacked block
    // rather than a caption glued to the number.
    readonly property real expressionGap: Math.round(displayFontSize * 0.24)
    readonly property real keyFontSize: Math.round(activeCell * 0.41)
    // The scientific keypad's two sizes, as fractions of its cell. Measured off
    // the landscape reference, where the digits, AC, % and the operators ink
    // out 28 device px tall against the function columns' 21 — the label is a
    // property of the key's role there, not of the keypad.
    readonly property real scientificKeyFontSize:
        Math.round(scientificCellWidth * 0.240)
    readonly property real scientificFunctionFontSize:
        Math.round(scientificCellWidth * 0.198)
    readonly property int displayRightInset: 25
    // The reference leaves 3.9% of its window height between the result's
    // glyphs and the keypad's first row; a Text item's box bottom sits a
    // descent below its glyphs, so the anchor needs a margin that much smaller.
    readonly property int displayBottomInset: 2

    // The result's own glyph height, read off the font rather than assumed: the
    // expression line is hung off the top of the digits, and a Text item's box
    // top is the font's ascent line, not the cap line.
    TextMetrics {
        id: displayDigits
        font: display.font
        text: "0"
    }

    CalculatorPalette { id: palette }
    HistoryStore { id: history }

    CalculatorEngine {
        id: engine
        onCalculated: function(expression, result) {
            history.add(expression, result)
        }
    }

    ConvertStore {
        id: converter
        amount: engine.value
    }

    // --- keyboard -----------------------------------------------------
    // The reference is a pointer-driven keypad, but a calculator that ignores
    // the number row is unusable; the mapping is the obvious one.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            // While the unit picker is up its own search field is what the
            // keyboard belongs to, and digits typed into it must not also land
            // on the calculator behind. Escape is the one key that still means
            // something out here: it puts the sheet away.
            if (unitPicker.visible) {
                if (event.key === Qt.Key_Escape)
                    unitPicker.close()
                event.accepted = event.key === Qt.Key_Escape
                return
            }
            var text = event.text
            if (text.length === 1 && "0123456789.".indexOf(text) >= 0) {
                engine.press(text)
            } else if (text === "+" || text === "-") {
                engine.press(text)
            } else if (text === "*") {
                engine.press("×")
            } else if (text === "/") {
                engine.press("÷")
            } else if (text === "^") {
                engine.press("^")
            } else if (text === "(" || text === ")") {
                engine.press(text)
            } else if (text === "%") {
                engine.press("percent")
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                       || text === "=") {
                engine.press("=")
            } else if (event.key === Qt.Key_Escape) {
                engine.press("ac")
            } else if (event.key === Qt.Key_Backspace) {
                engine.backspace()
            } else {
                event.accepted = false
                return
            }
            event.accepted = true
        }
    }

    // --- window chrome ------------------------------------------------
    // Plain rectangles, inset by the window margin. No chromeMask and no layer
    // effect: the app does not clip its own corners, the compositor rounds the
    // window instead.
    Item {
        id: windowChrome
        anchors.fill: parent
        anchors.margins: root.chromeMargin

        // One plane for the whole content box. The landscape reference does
        // read its display off a band a shade below its keypad, but that band
        // is an artefact of the phone's wallpaper gradient showing through its
        // glass — the basic and history shots have no band at all — and
        // reproducing it here would give the scientific view a seam the other
        // two do not have. The user asked for the three views to read alike, so
        // the band is gone and the display sits on the keypad's own plane.
        Rectangle {
            anchors.fill: parent
            color: palette.plane
        }

        HistoryPane {
            id: historyPane
            visible: root.historyVisible
            width: root.historyPaneWidth
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            colors: palette
            rows: history.rows
            onClearRequested: history.clear()
            onRemoveRequested: function(indices) { history.removeMany(indices) }
        }

        Rectangle {
            visible: root.historyVisible
            x: root.historyPaneWidth
            width: root.paneSeamWidth
            anchors {
                top: parent.top
                bottom: parent.bottom
            }
            color: palette.historySeam
        }

        // --- display ---
        Text {
            id: display
            visible: !root.converting
            // The number and the keypad share a right edge in the landscape
            // reference — the keypad fills that window, so its right cell edge
            // is the pane's. In the basic view the keypad is narrower than the
            // pane and the reference gives the number an inset of its own.
            readonly property real rightInset: root.scientific
                ? 0 : root.displayRightInset
            anchors {
                right: parent.right
                rightMargin: display.rightInset
                bottom: keypad.top
                bottomMargin: root.displayBottomInset
            }
            text: engine.display
            color: palette.displayText
            font.weight: Font.Light
            horizontalAlignment: Text.AlignRight
            // Long results shrink rather than run under the window dots.
            font.pixelSize: Math.min(root.displayFontSize,
                (root.keypadPaneWidth - display.rightInset * 2)
                / Math.max(1, text.length) * 1.9)
        }

        // The line the sum is on, above the number it currently comes to. It
        // shares the result's right edge and is hung off the top of its digits.
        Text {
            id: expressionLine
            visible: text.length > 0 && !root.converting
            anchors {
                right: display.right
                baseline: display.baseline
                baselineOffset: -(displayDigits.tightBoundingRect.height
                                  + root.expressionGap)
            }
            text: engine.expression
            color: palette.displayExpression
            font.pixelSize: root.expressionFontSize
            font.weight: Font.Light
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            width: Math.min(implicitWidth,
                root.keypadPaneWidth - root.displayRightInset * 2)
        }

        // --- convert display ---
        // Sits in the display strip in place of the single-line one. Its rule
        // spans the whole content box — that is what the reference draws — so
        // it takes the pane's width rather than the keypad's, and only its
        // numbers stop where the keys do.
        ConvertDisplay {
            id: convertDisplay
            visible: root.converting
            x: root.keypadPaneX
            width: root.keypadPaneWidth
            anchors {
                bottom: keypad.top
                bottomMargin: convertDisplay.keypadGap
            }
            colors: palette
            fromUnit: converter.fromUnit
            toUnit: converter.toUnit
            fromValue: engine.expression.length > 0 ? engine.expression
                                                    : engine.display
            toValue: engine.formatNumber(converter.result)
            onSwapClicked: converter.swap()
            // The two codes open the picker on whichever row was clicked, so a
            // category change inside it falls back to the right one of the
            // category's two units.
            onFromUnitClicked: unitPicker.open(converter.categoryId,
                converter.fromUnit, false)
            onToUnitClicked: unitPicker.open(converter.categoryId,
                converter.toUnit, true)
        }

        // --- keypad ---
        Keypad {
            id: keypad
            x: root.keypadPaneX + (root.keypadPaneWidth - width) / 2
            y: root.gridTop
            width: root.keypadWidth
            height: root.gridHeight
            cellWidth: root.scientific ? root.scientificCellWidth : root.basicCell
            cellHeight: root.scientific ? root.scientificCellHeight : root.basicCell
            round: true
            gap: root.scientific ? root.scientificCellWidth * root.scientificKeyInset
                                 : 5
            cornerRadius: 2
            fontSize: root.scientific ? root.scientificKeyFontSize
                                      : root.keyFontSize
            functionFontSize: root.scientific ? root.scientificFunctionFontSize : 0
            scientific: root.scientific
            secondActive: engine.second
            radians: engine.radians
            colors: palette
            keys: root.scientific
                ? KeyTables.scientificKeys()
                : KeyTables.basicKeys(root.historyVisible)
            onKeyPressed: function(key) { engine.press(key) }
            onHistoryToggled: root.historyVisible = !root.historyVisible
        }
    }

    // --- unit picker ---
    // A sibling of the content box rather than a child of it: it frosts that box
    // through the same panel the mode menu uses, and a panel cannot sample the
    // item it is inside. It sits below the traffic lights and the two
    // title-strip buttons, which live in the margin the sheet never reaches.
    UnitPicker {
        id: unitPicker
        anchors.fill: parent
        anchors.margins: root.chromeMargin
        z: 9
        colors: palette
        backdrop: windowChrome
        // The sheet's search field takes the keyboard while it has focus, and
        // hiding the field does not hand it back on its own: without this, a
        // click in the search box followed by any way out of the sheet leaves
        // the keyboard typing into a field nobody can see, and the calculator
        // behind it looks dead.
        onVisibleChanged: if (!visible) keyCatcher.forceActiveFocus()
        onUnitChosen: function(code, category) {
            if (category !== converter.categoryId)
                converter.categoryId = category
            if (unitPicker.editingTop)
                converter.toUnit = code
            else
                converter.fromUnit = code
        }
    }

    // --- window dots ---
    // Red, amber, green in the window's top-right corner, at the calendar's
    // own geometry (14px dots, 14 apart, 14.5 from the right edge, 10.5 from
    // the top). They belong to the window frame rather than to the inset
    // content, so they anchor to the window and read against the glass above
    // the planes. The reference greys the third dot — zoom — out while the
    // history column is open, so the zoom action is unavailable in that state.
    Row {
        id: dots
        anchors {
            right: parent.right
            rightMargin: 14.5
            top: parent.top
            topMargin: 10.5
        }
        spacing: 14
        z: 10

        Repeater {
            model: [
                { tint: "#ff5f57", action: "close" },
                { tint: "#febc2e", action: "minimise" },
                { tint: "#28c840", action: "zoom" }
            ]

            delegate: Rectangle {
                required property var modelData

                width: 14
                height: 14
                radius: 7
                color: modelData.action === "zoom" && root.historyVisible
                    ? "#8e8e93" : modelData.tint
                opacity: 0.9

                MouseArea {
                    anchors.fill: parent
                    enabled: !(modelData.action === "zoom" && root.historyVisible)
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (modelData.action === "close")
                            root.close()
                        else if (modelData.action === "minimise")
                            root.showMinimized()
                        else
                            root.toggleFullScreen()
                    }
                }
            }
        }
    }

    // --- title-strip buttons ------------------------------------------
    // The reference puts history behind a clock in the top-left corner and the
    // mode menu behind a calculator badge in the top-right. On the desktop the
    // right-hand one has to sit to the left of the traffic lights, which are
    // this window's own controls; the left corner is free, so the clock keeps
    // the position the reference gives it.
    //
    // Neither button resizes the window by itself — only the mode it selects
    // does, and both modes are entered by clicking.
    CalculatorChromeButton {
        id: historyButton
        anchors {
            left: parent.left
            leftMargin: 10
            top: parent.top
            topMargin: 8
        }
        colors: palette
        iconName: "clock"
        active: root.historyVisible
        z: 10
        onClicked: root.historyVisible = !root.historyVisible
    }

    CalculatorChromeButton {
        id: modeButton
        anchors {
            right: dots.left
            rightMargin: 10
            top: parent.top
            topMargin: 8
        }
        colors: palette
        iconName: "calculator"
        active: appMenu.visible
        z: 10
        // The reference hangs its menu flush with the badge's top edge and lets
        // the panel cover the badge. That cannot be copied here: the panel is
        // translucent by design, so a button underneath it bleeds through as a
        // bright smudge in its corner rather than disappearing. The panel
        // therefore hangs just below the button instead, which is also where a
        // desktop menu belongs.
        onClicked: appMenu.popup(modeButton,
            modeButton.width - appMenu.width, modeButton.height + 6)
    }

    // --- mode menu ----------------------------------------------------
    // The reference's own mode switch, minus the one mode this app cannot
    // carry: "Math Notes" is a pencil-and-handwriting surface on iOS and has no
    // desktop counterpart to copy.
    CalculatorMenu {
        id: appMenu
        colors: palette
        // The menu frosts the app's own planes and keypad rather than asking
        // kwin to blur what is behind the window.
        backdrop: windowChrome

        CalculatorMenuItem {
            colors: palette
            iconName: "basic"
            text: qsTr("Basic")
            selected: !root.scientific && !root.converting
            onTriggered: {
                root.scientific = false
                root.converting = false
            }
        }

        CalculatorMenuItem {
            colors: palette
            iconText: "f(x)"
            text: qsTr("Scientific")
            selected: root.scientific
            onTriggered: {
                root.scientific = true
                root.converting = false
            }
        }

        // The reference sets Convert off from the two calculators above it
        // rather than listing it with them: it is the one entry that is not a
        // keypad.
        CalculatorMenuSeparator { colors: palette }

        CalculatorMenuItem {
            colors: palette
            iconName: "convert"
            text: qsTr("Convert")
            selected: root.converting
            onTriggered: {
                root.converting = true
                root.scientific = false
            }
        }
    }
}
