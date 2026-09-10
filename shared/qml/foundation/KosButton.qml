import QtQuick
import QtQuick.Controls

Button {
    id: root

    property bool destructive: false
    readonly property bool emphasized: highlighted || (checkable && checked)

    hoverEnabled: true
    implicitHeight: AppTheme.controlHeight
    implicitWidth: Math.max(72, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: 16
    rightPadding: 16
    topPadding: 7
    bottomPadding: 7
    transformOrigin: Item.Center
    scale: !enabled ? 1 : (down ? AppTheme.pressScale
                               : (hovered ? AppTheme.hoverScale : 1))

    Behavior on scale {
        NumberAnimation { duration: AppTheme.motionFast; easing.type: Easing.OutCubic }
    }

    contentItem: Label {
        text: root.text
        font: root.font
        color: !root.enabled
            ? AppTheme.withAlpha(AppTheme.text, 0.42)
            : (root.emphasized ? AppTheme.accentText
                               : (root.destructive ? AppTheme.destructive : AppTheme.text))
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight

        Behavior on color { ColorAnimation { duration: AppTheme.motionFast } }
    }

    background: KosSurface {
        implicitWidth: 72
        implicitHeight: AppTheme.controlHeight
        radius: Math.min(AppTheme.smallRadius, height / 2)
        fillColor: {
            if (root.emphasized)
                return root.down ? AppTheme.accentPressed
                    : (root.hovered ? AppTheme.accentHover : AppTheme.accent)
            if (root.flat && !root.hovered && !root.down)
                return "transparent"
            if (root.down)
                return AppTheme.buttonPressed
            return root.hovered ? AppTheme.buttonHover : AppTheme.button
        }
        strokeWidth: root.flat && !root.hovered && !root.activeFocus ? 0 : 1
        strokeColor: root.emphasized
            ? AppTheme.withAlpha(AppTheme.accentText, 0.16)
            : AppTheme.border
        elevation: root.flat && !root.hovered && !root.activeFocus ? 0
            : (root.emphasized ? 0.68 : (root.hovered ? 0.62 : 0.42))
        hovered: root.hovered
        pressed: root.down
        focused: root.activeFocus
        showInnerHighlight: !root.flat || root.hovered
        opacity: root.enabled ? 1 : 0.68
    }
}
