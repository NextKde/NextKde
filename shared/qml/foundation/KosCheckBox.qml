import QtQuick
import QtQuick.Controls

CheckBox {
    id: root
    spacing: 10
    implicitHeight: AppTheme.controlHeight
    indicator: Rectangle {
        implicitWidth: 20; implicitHeight: 20
        x: root.leftPadding; y: (root.height - height) / 2
        radius: 6
        color: root.checked ? AppTheme.accent : AppTheme.fieldSurface
        border.width: root.activeFocus ? 2 : 1
        border.color: root.checked || root.activeFocus ? AppTheme.accent : AppTheme.borderHover
        Text {
            anchors.centerIn: parent
            text: root.checkState === Qt.PartiallyChecked ? "−" : "✓"
            visible: root.checkState !== Qt.Unchecked
            color: AppTheme.accentText; font.pixelSize: 14
        }
    }
    contentItem: Label {
        text: root.text; font: root.font
        leftPadding: root.indicator.width + root.spacing
        verticalAlignment: Text.AlignVCenter
        color: root.enabled ? AppTheme.text : AppTheme.mutedText
        elide: Text.ElideRight
    }
}
