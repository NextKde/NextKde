import QtQuick
import QtQuick.Controls

RoundButton {
    id: root

    hoverEnabled: true
    implicitWidth: 46
    implicitHeight: 46
    padding: 8
    transformOrigin: Item.Center
    scale: !enabled ? 1 : (down ? AppTheme.pressScale
                               : (hovered ? AppTheme.hoverScale : 1))

    Behavior on scale {
        NumberAnimation { duration: AppTheme.motionFast; easing.type: Easing.OutCubic }
    }

    contentItem: Label {
        text: root.text
        font: root.font
        color: root.enabled
            ? (root.highlighted ? AppTheme.accentText : AppTheme.text)
            : AppTheme.withAlpha(AppTheme.text, 0.38)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: KosSurface {
        radius: width / 2
        fillColor: root.highlighted
            ? (root.down ? AppTheme.accentPressed
                         : (root.hovered ? AppTheme.accentHover : AppTheme.accent))
            : (root.down ? AppTheme.buttonPressed
                         : (root.hovered ? AppTheme.buttonHover : AppTheme.button))
        strokeWidth: 1
        strokeColor: root.highlighted
            ? AppTheme.withAlpha(AppTheme.accentText, 0.16)
            : AppTheme.border
        elevation: root.highlighted ? 0.72 : (root.hovered ? 0.64 : 0.46)
        hovered: root.hovered
        pressed: root.down
        focused: root.activeFocus
        opacity: root.enabled ? 1 : 0.64
    }
}
