pragma ComponentBehavior: Bound

import QtQuick

// The history column: a heading per bucket with its lines under it, exactly as
// the reference draws it — heading, hairline, lines, hairline. Both headings
// render whether or not their bucket has anything in it.
Item {
    id: root

    property var colors
    property var rows: []

    // The edit state is the iOS sheet's, not the macOS column's: macOS only
    // ever shows the trash. Resting, the bar is an "Edit" pill on the left and
    // that trash on the right; editing, the pill becomes a filled orange tick
    // and the trash becomes the destructive pill.
    property bool editing: false
    // Selected entry indices, keyed by the store's own index. Reassigned whole
    // rather than mutated so bindings on it re-evaluate.
    property var selected: ({})

    signal clearRequested()
    signal removeRequested(var indices)

    readonly property int selectionCount: {
        var count = 0
        for (var key in selected) {
            if (selected[key])
                count++
        }
        return count
    }

    // Geometry read off the reference at its own scale and lifted by the same
    // factor the keypad uses, so the column's rhythm matches the keys beside it.
    readonly property int sideInset: 44
    readonly property int headingTop: 20
    readonly property int headingHeight: 64
    readonly property int entryHeight: 124
    readonly property int expressionTop: 40
    readonly property int resultTop: 69
    readonly property int contentTop: 86

    readonly property int headingFontSize: 17
    readonly property int expressionFontSize: 21
    readonly property int resultFontSize: 24

    // The selection circles sit in the left gutter, centred in it — which is
    // where the reference puts them too (its ring centre falls 6% off its own
    // gutter centre). Diameter is the reference's 50/143 of the gutter.
    readonly property int ringDiameter: 18
    // The edit bar's controls share the trash's centre line rather than the
    // iOS bar's own offset: on the phone the bar hugs the sheet's top edge,
    // but here the strip above it already belongs to the window's chrome.
    readonly property int barDiameter: 30
    readonly property int barTop: 22

    function selectedIndices() {
        var out = []
        for (var key in selected) {
            if (selected[key])
                out.push(Number(key))
        }
        return out
    }

    function toggle(index) {
        var next = {}
        for (var key in selected)
            next[key] = selected[key]
        if (next[index])
            delete next[index]
        else
            next[index] = true
        selected = next
    }

    // The destructive pill's one action: drop whatever is ticked, or everything
    // when nothing is. The selection is dropped first — removing lines shifts
    // every index after them, so a selection that outlived its own removal
    // would point at the wrong entries.
    function commitSelection() {
        var indices = selectedIndices()
        selected = ({})
        if (indices.length > 0)
            removeRequested(indices)
        else
            clearRequested()
    }

    // The column is a slide-over; closing it ends the edit, the same way
    // dismissing the sheet does.
    onVisibleChanged: {
        if (!visible) {
            editing = false
            selected = ({})
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.colors.historyPlane
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + root.contentTop + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            y: root.contentTop
            width: parent.width

            Repeater {
                model: root.rows

                delegate: Item {
                    id: row
                    required property var modelData

                    readonly property bool isEntry: modelData.kind !== "heading"
                    readonly property bool isSelected: root.editing && isEntry
                        && root.selected[modelData.index] === true

                    width: column.width
                    height: isEntry ? root.entryHeight : root.headingHeight

                    Text {
                        x: root.sideInset
                        y: row.isEntry ? root.expressionTop : root.headingTop
                        text: row.isEntry ? row.modelData.expression : row.modelData.title
                        color: row.isEntry
                            ? root.colors.historyExpression
                            : root.colors.historyHeader
                        font.pixelSize: row.isEntry
                            ? root.expressionFontSize : root.headingFontSize
                        font.weight: row.isEntry ? Font.Normal : Font.DemiBold
                        width: parent.width - root.sideInset * 2
                        elide: Text.ElideRight
                    }

                    Text {
                        x: root.sideInset
                        y: root.resultTop
                        visible: row.isEntry
                        text: row.isEntry ? row.modelData.result : ""
                        color: root.colors.historyResult
                        font.pixelSize: root.resultFontSize
                        width: parent.width - root.sideInset * 2
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        id: selection
                        visible: root.editing && row.isEntry
                        x: root.sideInset / 2 - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.ringDiameter
                        height: root.ringDiameter
                        radius: root.ringDiameter / 2
                        color: row.isSelected ? root.colors.chromeButtonActive
                                              : "transparent"
                        border.width: row.isSelected ? 0 : 1.5
                        border.color: root.colors.selectionRing

                        CalculatorIcon {
                            anchors.centerIn: parent
                            visible: row.isSelected
                            name: "check"
                            size: 11
                            strokeWidth: 2.4
                            color: root.colors.textOnOperator
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.editing && row.isEntry
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(row.modelData.index)
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 1
                        color: root.colors.historyDivider
                    }
                }
            }
        }
    }

    // --- edit bar -----------------------------------------------------
    // Level with the window dots the chrome draws over the column's top strip.
    //
    // It is declared after the list on purpose. The list is a Flickable that
    // fills the whole column, and a later sibling is the one that gets the
    // click, so the bar has to come second or the scroller swallows every
    // press that lands on it.
    //
    CalculatorPill {
        id: editPill
        visible: !root.editing
        anchors {
            left: parent.left
            leftMargin: 20
            top: parent.top
            topMargin: root.barTop
        }
        label: qsTr("Edit")
        fill: root.colors.historyPill
        labelColor: root.colors.historyPillText
        onClicked: {
            root.selected = ({})
            root.editing = true
        }
    }

    Rectangle {
        id: doneDisc
        visible: root.editing
        anchors {
            left: parent.left
            leftMargin: 20
            top: parent.top
            topMargin: root.barTop
        }
        width: root.barDiameter
        height: root.barDiameter
        radius: root.barDiameter / 2
        color: root.colors.chromeButtonActive

        CalculatorIcon {
            anchors.centerIn: parent
            name: "check"
            // The reference's tick inks out 42% of the disc, so at 30px the
            // mark is 12.6px and the path fills 71% of its own box.
            size: 18
            strokeWidth: 2.4
            color: root.colors.textOnOperator
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.editing = false
        }
    }

    // The trash sits in the column's own top strip, level with the window
    // dots the chrome draws over it.
    CalculatorIcon {
        id: trash
        visible: !root.editing
        anchors {
            top: parent.top
            topMargin: 26
            right: parent.right
            rightMargin: 20
        }
        name: "trash"
        size: 21
        color: trashArea.containsMouse
            ? root.colors.iconTintActive : root.colors.iconTint
        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: trashArea
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearRequested()
        }
    }

    CalculatorPill {
        id: clearPill
        visible: root.editing
        anchors {
            right: parent.right
            rightMargin: 20
            top: parent.top
            topMargin: root.barTop
        }
        // The reference only ever shows the pill with nothing selected, so the
        // "delete what is selected" label is extrapolated: with a selection the
        // pill has to mean something other than "clear everything", and this is
        // the slot the reference already gives the destructive action.
        label: root.selectionCount > 0
            ? qsTr("Delete (%1)").arg(root.selectionCount)
            : qsTr("Clear All")
        fill: root.colors.historyPill
        labelColor: root.colors.destructive
        onClicked: root.commitSelection()
    }

}
