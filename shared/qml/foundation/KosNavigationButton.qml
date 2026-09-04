import QtQuick
import QtQuick.Controls

Button {
    id: root

    property string symbol: ""

    checkable: true
    flat: true
    leftPadding: 14
    rightPadding: 14
    implicitHeight: Math.round(42 * AppTheme.densityScale)

    contentItem: Row {
        spacing: 10

        Label {
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            text: root.symbol
            color: root.checked ? AppTheme.accent : AppTheme.mutedText
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 17
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.checked ? AppTheme.text : AppTheme.mutedText
            font.weight: root.checked ? Font.DemiBold : Font.Normal
        }
    }

    background: Rectangle {
        radius: AppTheme.smallRadius
        color: root.checked
            ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.18 : 0.13)
            : (root.hovered ? AppTheme.cardSurface : "transparent")
        border.width: root.activeFocus ? 1 : 0
        border.color: AppTheme.withAlpha(AppTheme.accent, 0.58)
        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
    }
}
