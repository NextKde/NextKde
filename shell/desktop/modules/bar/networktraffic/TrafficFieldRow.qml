import QtQuick

// Label/value row, 22 px tall when both fit on one line. The title is 12
// Regular muted, the value 12 Semibold ink and right aligned. Totals carry a
// 10x10 colour swatch ahead of the title.
//
// The split follows the text rather than two fixed columns: translated titles
// and values are often longer than the English ones, and a fixed half/half
// split elided both even when the other half sat empty. When the pair does not
// fit on one line the title keeps its width (up to 60% of the row) and the
// value wraps onto a second line, growing the row.
Item {
    id: root
    property string title: ""
    property string value: "—"
    property color ink: "white"
    property color mutedInk: Qt.rgba(1, 1, 1, 0.7)
    property color swatchColor: "transparent"
    property bool showSwatch: false
    property string valueObjectName: ""

    readonly property real titleX: showSwatch ? 14 : 0
    readonly property real available: Math.max(0, width - titleX - 8)
    // Natural widths come from TextMetrics, so wrapping the value never feeds
    // back into the split.
    readonly property real titleNatural: Math.ceil(titleMetrics.advanceWidth)
    readonly property real valueNatural: Math.ceil(valueMetrics.advanceWidth)
    readonly property real titleWidth: titleNatural + valueNatural <= available
        ? available - valueNatural
        : Math.min(titleNatural, available * 0.6)

    implicitHeight: valueText.lineCount > 1 ? Math.ceil(valueText.contentHeight) + 6 : 22

    TextMetrics { id: titleMetrics; font: titleText.font; text: root.title }
    TextMetrics { id: valueMetrics; font: valueText.font; text: root.value }

    Rectangle {
        visible: root.showSwatch
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 10
        height: 10
        radius: 2.5
        color: root.swatchColor
    }
    Text {
        id: titleText
        x: root.titleX
        anchors.verticalCenter: parent.verticalCenter
        width: root.titleWidth
        text: root.title
        color: root.mutedInk
        font.pixelSize: 12
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
    Text {
        id: valueText
        objectName: root.valueObjectName
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.available - root.titleWidth
        text: root.value
        color: root.ink
        font.pixelSize: 12
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignRight
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }
}
