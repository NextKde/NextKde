import QtQuick
import "UnitTable.js" as Units

// The unit picker: the sheet that opens when either unit code in the convert
// display is clicked.
//
// Its geometry is the reference's own, measured off ios-unit-picker.webp and
// carried as fractions of the sheet's width (see LEDGER, round 22). The one
// deliberate departure is the sheet's height. The reference's sheet covers 93%
// of an 871-logical-pixel phone screen; this window's content box is 520 tall,
// so the sheet is 484 and the list shows five rows where the reference shows
// eight. Everything above and below the list keeps its measured size and the
// list absorbs the whole difference, which is what the reference's own scroll
// would do on a shorter screen.
//
// Nothing here is committed until the sheet is done with: the chips and the
// rows edit the sheet's own pair, and only the tick disc or a row hands the
// result back. That is what the reference's disc is for, and it also means
// browsing the other twelve categories cannot cost you the pair you opened on.
Item {
    id: root

    // It covers the whole content box when it is up, so it must not be up
    // until something asks it to be.
    visible: false

    property var colors
    property Item backdrop
    // Which row of the convert display is being edited, so a category change
    // knows which of its two units the sheet should fall back to.
    property bool editingTop: false

    property string categoryId: "currency"
    property string selectedCode: ""
    property string query: ""

    signal unitChosen(string code, string categoryId)
    signal dismissed()

    readonly property var chips: Units.chipList()
    readonly property var rows: query.length > 0 ? Units.search(query)
                                                 : Units.unitRows(categoryId)
    readonly property var openCategory: Units.category(categoryId)
    // Only the currency table carries a stamp; the others are definitions and
    // have nothing to date.
    readonly property string source: openCategory && openCategory.source
                                     ? openCategory.source : ""
    readonly property string updated: openCategory && openCategory.updated
                                      ? openCategory.updated : ""

    // --- proportions --------------------------------------------------
    // Fractions of the sheet's width, off the reference's 923. Its vertical
    // positions are carried the same way rather than as fractions of the
    // sheet's height, because the sheet is not the same shape here: see the
    // note at the top.
    readonly property real radius: Math.round(width * 0.0688)
    readonly property real titleFont: Math.round(width * 0.0423)
    readonly property real titleInkTop: width * 0.0780
    readonly property real doneSize: Math.round(width * 0.1127)
    readonly property real doneCentreY: width * 0.0970
    readonly property real doneRightInset: width * 0.0412
    readonly property real chipTop: width * 0.1842
    readonly property real chipHeight: width * 0.0704
    readonly property real chipFont: Math.round(width * 0.0347)
    readonly property real chipPad: width * 0.0320
    readonly property real chipGap: width * 0.0022
    readonly property real chipLeft: width * 0.0460
    readonly property real headerRuleY: width * 0.2806
    readonly property real rowPitch: width * 0.1729
    readonly property real nameFont: Math.round(width * 0.0408)
    readonly property real codeFont: Math.round(width * 0.0339)
    readonly property real rowInkLeft: width * 0.1018
    readonly property real nameInkTop: width * 0.0487
    readonly property real codeInkTop: width * 0.1018
    readonly property real tickSize: width * 0.0333
    readonly property real tickCentreX: width * 0.0590
    readonly property real ruleLeft: width * 0.0997
    readonly property real ruleRightInset: width * 0.0423
    readonly property real footerFont: Math.round(width * 0.0314)
    readonly property real footerLeft: width * 0.0639
    readonly property real footerRightInset: width * 0.0607
    readonly property real footerInkDrop: width * 0.0229
    readonly property real searchLeft: width * 0.0715
    readonly property real searchRightInset: width * 0.0726
    readonly property real searchHeight: width * 0.1148
    readonly property real searchBottom: width * 0.0780
    readonly property real searchPad: width * 0.0477
    readonly property real searchGap: width * 0.0217
    readonly property real searchIcon: width * 0.0596
    readonly property real searchFont: Math.round(width * 0.0423)

    // 1862/2000 of the reference's screen, and the gap the reference leaves
    // between the footer band's top and the search field's top.
    readonly property real sheetHeight: height * 0.931
    readonly property real footerGap: width * 0.0586
    readonly property real footerTop: sheetHeight - searchBottom - searchHeight
                                      - footerGap

    function open(category, code, top) {
        editingTop = top
        categoryId = category
        // A code that does not belong to the category it was handed with — or
        // none at all — falls back to the pair that category opens on, so the
        // sheet always opens with one row marked.
        selectedCode = Units.unit(category, code) ? code
            : (top ? Units.defaultTo(category) : Units.defaultFrom(category))
        query = ""
        searchInput.text = ""
        visible = true
        Qt.callLater(root.reveal)
    }

    // The reference's list opens with the unit being edited already at the top
    // of the visible rows: its first row is 人民币, ticked, and 人民币 sits far
    // down a pinyin-ordered list of currencies. So the list is scrolled to the
    // selection rather than left at its own start.
    function reveal() {
        for (var i = 0; i < rows.length; i++)
            if (rows[i].code === selectedCode && rows[i].categoryId === categoryId) {
                unitList.positionViewAtIndex(i, ListView.Beginning)
                return
            }
    }

    function close() {
        visible = false
    }

    // Browsing. A category the open code does not belong to falls back to the
    // pair that category opens on, which is what the convert display itself
    // would show if the category were switched there.
    function selectCategory(id) {
        if (id === categoryId)
            return
        categoryId = id
        query = ""
        searchInput.text = ""
        if (!Units.unit(id, selectedCode))
            selectedCode = editingTop ? Units.defaultTo(id) : Units.defaultFrom(id)
        Qt.callLater(root.reveal)
    }

    // A row was clicked: that unit, from whatever category the row came from,
    // and the sheet is done.
    function choose(code, category) {
        selectedCode = code
        if (category && category !== categoryId)
            categoryId = category
        visible = false
        unitChosen(code, categoryId)
    }

    function accept() {
        visible = false
        unitChosen(selectedCode, categoryId)
    }

    // --- the strip the sheet does not cover ---------------------------
    // The reference's sheet runs off the bottom of a phone screen and there is
    // nothing left above it to tap; here a seventh of the content box stays
    // visible, and tapping it is how the sheet is dismissed without choosing.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.close()
            root.dismissed()
        }
    }

    // --- the sheet ----------------------------------------------------
    // Clipped to its own height: the glass panel is drawn a corner-radius
    // taller than the sheet so that its bottom corners fall outside the clip
    // and the slab ends square, the way a sheet that runs to the edge of the
    // screen does in the reference.
    Item {
        id: sheet

        x: 0
        y: root.height - root.sheetHeight
        width: root.width
        height: root.sheetHeight
        clip: true

        CalculatorGlassPanel {
            width: parent.width
            height: parent.height + root.radius
            radius: root.radius
            colors: root.colors
            backdrop: root.backdrop
            // The reference's sheet is opaque enough that the keypad behind it
            // is a tone rather than a shape, which is far more than the mode
            // menu asks of the same panel: at the menu's own tint the operator
            // column bled through as a recognisable orange blob.
            tintAlpha: 0.94
        }

        // The reference's three bands: the header and the footer carry the
        // sheet's own tone and the list between them is a step deeper.
        Rectangle {
            x: 0
            y: root.headerRuleY + 1
            width: parent.width
            height: Math.max(0, root.footerTop - root.headerRuleY - 1)
            color: root.colors.pickerListShade
        }

        Rectangle {
            x: 0
            y: root.footerTop
            width: parent.width
            height: Math.max(0, parent.height - root.footerTop)
            color: root.colors.pickerFooterShade
        }

        // Stop the sheet's own body from dismissing it; only the strip above
        // it should.
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        // --- title ---
        TextMetrics {
            id: titleMetrics
            font: title.font
            text: qsTr("单位")
        }

        Text {
            id: title
            x: 0
            y: root.titleInkTop - (baselineOffset + titleMetrics.tightBoundingRect.y)
            width: parent.width
            text: qsTr("单位")
            color: root.colors.pickerText
            font.pixelSize: root.titleFont
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        // --- the tick disc ---
        // Filled accent with the tick knocked out of it, and the sheet's one
        // commit control.
        Item {
            id: done
            x: parent.width - root.doneRightInset - width
            y: root.doneCentreY - height / 2
            width: root.doneSize
            height: root.doneSize

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.colors.pickerAccent
            }

            CalculatorIcon {
                anchors.centerIn: parent
                name: "check"
                size: root.doneSize * 0.42
                strokeWidth: 2.6
                color: "#FFFFFF"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.accept()
            }
        }

        // --- category chips ---
        ListView {
            id: chipRow
            x: 0
            y: root.chipTop
            width: parent.width
            height: root.chipHeight
            orientation: ListView.Horizontal
            spacing: root.chipGap
            leftMargin: root.chipLeft
            rightMargin: root.chipLeft
            clip: true
            model: root.chips

            delegate: Item {
                required property var modelData

                width: chipLabel.implicitWidth + root.chipPad * 2
                height: chipRow.height

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: modelData.id === root.categoryId
                        ? root.colors.pickerAccent : "transparent"
                }

                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: modelData.id === root.categoryId
                        ? root.colors.pickerChipText : root.colors.pickerAccent
                    font.pixelSize: root.chipFont
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectCategory(modelData.id)
                }
            }
        }

        // The hairline the chip row sits on. It starts where the list's own
        // hairlines do, not at the sheet's edge.
        Rectangle {
            x: root.ruleLeft
            y: root.headerRuleY
            width: Math.max(0, parent.width - root.ruleLeft - root.ruleRightInset)
            height: 1
            color: root.colors.pickerRule
        }

        // --- the unit list ---
        ListView {
            id: unitList
            x: 0
            y: root.headerRuleY + 1
            width: parent.width
            height: Math.max(0, root.footerTop - root.headerRuleY - 1)
            clip: true
            model: root.rows
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                required property var modelData
                // Main.qml carries `pragma ComponentBehavior: Bound`, so the
                // delegate's own index is not a context property and has to be
                // asked for by name.
                required property int index

                width: unitList.width
                height: root.rowPitch

                readonly property bool chosen: modelData.code === root.selectedCode
                    && modelData.categoryId === root.categoryId

                TextMetrics {
                    id: nameMetrics
                    font: rowName.font
                    text: "国"
                }

                TextMetrics {
                    id: codeMetrics
                    font: rowCode.font
                    text: "M"
                }

                // Every row but the first carries the rule above it, so the
                // list has no line at its own top edge.
                Rectangle {
                    visible: index > 0
                    x: root.ruleLeft
                    y: 0
                    width: Math.max(0, parent.width - root.ruleLeft
                                       - root.ruleRightInset)
                    height: 1
                    color: root.colors.pickerRule
                }

                CalculatorIcon {
                    visible: parent.chosen
                    x: root.tickCentreX - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"
                    size: root.tickSize
                    strokeWidth: 2.6
                    color: root.colors.pickerAccent
                }

                Text {
                    id: rowName
                    x: root.rowInkLeft
                    // Hung off its own ink rather than its box: a Text's box top
                    // is the font's ascent line, and the reference's row offsets
                    // are measured to the glyphs.
                    y: root.nameInkTop
                       - (baselineOffset + nameMetrics.tightBoundingRect.y)
                    text: modelData.label
                    color: parent.chosen ? root.colors.pickerAccent
                                         : root.colors.pickerText
                    font.pixelSize: root.nameFont
                }

                Text {
                    id: rowCode
                    x: root.rowInkLeft
                    y: root.codeInkTop
                       - (baselineOffset + codeMetrics.tightBoundingRect.y)
                    text: modelData.code
                    color: parent.chosen ? root.colors.pickerAccent
                                         : root.colors.pickerCode
                    font.pixelSize: root.codeFont
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.choose(modelData.code, modelData.categoryId)
                }
            }
        }

        // --- footer ---
        // The reference's own stamp, on the band the search field sits in.
        // Nothing but the currency table has a source to name, so the band is
        // empty on the other twelve.
        TextMetrics {
            id: footerMetrics
            font: footerSource.font
            text: "yahoo!finance"
        }

        Text {
            id: footerSource
            x: root.footerLeft
            y: root.footerTop + root.footerInkDrop
               - (baselineOffset + footerMetrics.tightBoundingRect.y)
            text: root.source
            color: root.colors.pickerCode
            font.pixelSize: root.footerFont
        }

        Text {
            id: footerUpdated
            y: footerSource.y
            width: parent.width - root.footerRightInset
            text: root.updated.length > 0 ? qsTr("%1 更新").arg(root.updated) : ""
            color: root.colors.pickerCode
            font.pixelSize: root.footerFont
            horizontalAlignment: Text.AlignRight
        }

        // --- search ---
        Rectangle {
            id: searchField
            x: root.searchLeft
            y: parent.height - root.searchBottom - height
            width: Math.max(0, parent.width - root.searchLeft
                               - root.searchRightInset)
            height: root.searchHeight
            radius: height / 2
            color: root.colors.pickerField

            CalculatorIcon {
                id: magnifier
                x: root.searchPad
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                size: root.searchIcon
                strokeWidth: 2
                color: root.colors.pickerFieldText
            }

            Text {
                visible: searchInput.text.length === 0
                x: magnifier.x + magnifier.width + root.searchGap
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("搜索所有单位")
                color: root.colors.pickerFieldText
                font.pixelSize: root.searchFont
            }

            TextInput {
                id: searchInput
                x: magnifier.x + magnifier.width + root.searchGap
                width: Math.max(0, parent.width - x - root.searchPad)
                anchors.verticalCenter: parent.verticalCenter
                color: root.colors.pickerText
                font.pixelSize: root.searchFont
                selectByMouse: true
                clip: true
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.close()
            }
        }
    }
}
