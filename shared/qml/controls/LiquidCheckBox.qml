import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

CheckBox {
    id: root
    implicitHeight: 34
    spacing: 10
    indicator: LiquidSurface {
        implicitWidth: 22
        implicitHeight: 22
        x: root.leftPadding
        y: (root.height - height) / 2
        radius: 7
        tintColor: root.checked ? Foundation.AppTheme.accent : "#ffffff"
        tintStrength: root.checked ? 0.38 : 0.05
        Text {
            anchors.centerIn: parent
            text: root.checkState === Qt.PartiallyChecked ? "−" : "✓"
            visible: root.checkState !== Qt.Unchecked
            color: Foundation.AppTheme.text
            font.pixelSize: 15
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
