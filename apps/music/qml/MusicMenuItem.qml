import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui

MenuItem {
    id: root
    property bool destructive: false
    implicitHeight: visible ? 38 : 0
    leftPadding: 12
    rightPadding: 12
    topPadding: 6
    bottomPadding: 6
    indicator: null
    contentItem: RowLayout {
        spacing: 10
        Label {
            visible: root.checkable
            text: root.checked ? "✓" : ""
            Layout.preferredWidth: 16
            color: AppTheme.accent
        }
        Label {
            Layout.fillWidth: true
            text: root.text
            font: root.font
            color: !root.enabled ? AppTheme.withAlpha(AppTheme.text, 0.38)
                : root.destructive ? AppTheme.destructive : AppTheme.text
            elide: Text.ElideRight
        }
    }
    background: Rectangle {
        radius: AppTheme.smallRadius
        color: root.highlighted || root.down
            ? AppTheme.withAlpha(root.destructive ? AppTheme.destructive : AppTheme.accent, 0.12)
            : "transparent"
        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
    }
}
