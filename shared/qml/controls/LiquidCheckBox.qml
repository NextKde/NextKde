import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

CheckBox {
    id: root
    implicitHeight: 34
    spacing: 10
    // Hosts that draw their own row (calendar sidebar categories) need the
    // same box at a smaller size and with the category colour instead of the
    // accent; defaults keep every existing call site unchanged.
    property real indicatorSize: 22
    property real indicatorRadius: 7
    property color fillColor: Foundation.AppTheme.accent
    property real fillStrength: 0.38
    property real uncheckedFillStrength: 0.05
    property color checkColor: Foundation.AppTheme.text
    property bool checkVisible: true
    property real indicatorBorderWidth: 0
    property color indicatorBorderColor: fillColor
    indicator: LiquidSurface {
        implicitWidth: root.indicatorSize
        implicitHeight: root.indicatorSize
        x: root.leftPadding
        y: (root.height - height) / 2
        radius: root.indicatorRadius
        tintColor: root.checked ? root.fillColor : "#ffffff"
        tintStrength: root.checked ? root.fillStrength : root.uncheckedFillStrength
        Text {
            anchors.centerIn: parent
            text: root.checkState === Qt.PartiallyChecked ? "−" : "✓"
            visible: root.checkVisible && root.checkState !== Qt.Unchecked
            color: root.checkColor
            font.pixelSize: Math.round(root.indicatorSize * 0.68)
        }
        Rectangle {
            anchors.fill: parent
            radius: root.indicatorRadius
            color: "transparent"
            border.width: root.checked ? 0 : root.indicatorBorderWidth
            border.color: root.indicatorBorderColor
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: 9
            color: "transparent"
            border.width: 2
            border.color: Foundation.AppTheme.focusRing
            visible: root.activeFocus
        }
    }
    contentItem: Label {
        text: root.text
        font: root.font
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
        color: Foundation.AppTheme.text
    }
    opacity: enabled ? 1 : 0.38
}
