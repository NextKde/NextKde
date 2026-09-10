import QtQuick
import QtQuick.Controls

Button {
    id: root

    property string symbol: ""

    checkable: true
    flat: true
    hoverEnabled: true
    leftPadding: 14
    rightPadding: 14
    implicitHeight: Math.round(42 * AppTheme.densityScale)
    transformOrigin: Item.Center
    scale: !enabled ? 1 : (down ? AppTheme.pressScale
                               : (hovered ? AppTheme.hoverScale : 1))

    Behavior on scale {
        NumberAnimation { duration: AppTheme.motionFast; easing.type: Easing.OutCubic }
    }

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

    background: KosSurface {
        radius: AppTheme.smallRadius
        fillColor: root.checked
            ? AppTheme.withAlpha(AppTheme.accent, AppTheme.dark ? 0.18 : 0.13)
            : (root.hovered ? AppTheme.cardSurface : "transparent")
        strokeWidth: root.activeFocus || root.hovered ? 1 : 0
        strokeColor: root.checked
            ? AppTheme.withAlpha(AppTheme.accent, 0.34) : AppTheme.border
        elevation: root.checked ? 0.30 : (root.hovered ? 0.22 : 0)
        hovered: root.hovered
        pressed: root.down
        focused: root.activeFocus
        showInnerHighlight: root.checked || root.hovered
    }
}
