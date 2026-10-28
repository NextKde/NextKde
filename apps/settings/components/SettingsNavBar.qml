import QtQuick
import QtQuick.Layouts
import Kos.Demo as Demo

// Model/signal adapter only: geometry, optics and jelly motion stay in Demo.
Demo.LiquidSegmentedControl {
    id: root
    required property var colors
    property var model: []
    property bool disabled: false
    enabled: !disabled
    property string size: "tiny"
    property real barHeight: 24
    property real itemWidthOverride: 0
    signal selectionChanged(int index)
    labels: model.map(item => String(item.label ?? item.id ?? ""))
    onSelectionRequested: index => selectionChanged(index)
    implicitHeight: barHeight
    implicitWidth: Math.ceil(Math.max(1, labels.length) * Math.max(44, itemWidthOverride,
        ...labels.map(label => metrics.advanceWidth(label) + 24)) + 4)
    Layout.minimumWidth: 0
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: barHeight
    selectionColor: colors.dark ? "#636363" : "#D1D1D1"
    backgroundColor: colors.dark ? "#3A3A3C" : "#EDEDF0"
    textColor: colors.dark ? colors.primaryText : "#000000"
    mutedTextColor: textColor
    fontWeight: Font.Medium
    selectedFontWeight: Font.Medium
    FontMetrics { id: metrics; font.pixelSize: 11; font.weight: Font.Medium }
}
