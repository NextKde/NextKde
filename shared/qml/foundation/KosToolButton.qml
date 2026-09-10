import QtQuick
import QtQuick.Controls

ToolButton {
    id: root

    property bool destructive: false

    hoverEnabled: true
    implicitWidth: AppTheme.controlHeight
    implicitHeight: AppTheme.controlHeight
    padding: 7
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
            ? ((root.checkable && root.checked) ? AppTheme.accent
               : (root.destructive ? AppTheme.destructive : AppTheme.text))
            : AppTheme.withAlpha(AppTheme.text, 0.38)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: KosSurface {
        radius: Math.min(AppTheme.smallRadius, height / 2)
        fillColor: root.destructive && (root.hovered || root.down)
            ? AppTheme.withAlpha(AppTheme.destructive, root.down ? 0.20 : 0.11)
            : (root.down ? AppTheme.buttonPressed
               : (root.hovered || (root.checkable && root.checked)
                  ? AppTheme.buttonHover : "transparent"))
        strokeWidth: root.activeFocus || root.hovered
            || (root.checkable && root.checked) ? 1 : 0
        strokeColor: root.destructive ? AppTheme.withAlpha(AppTheme.destructive, 0.32)
                                      : AppTheme.border
        elevation: root.hovered || (root.checkable && root.checked) ? 0.42 : 0
        hovered: root.hovered
        pressed: root.down
        focused: root.activeFocus
        showInnerHighlight: root.hovered || (root.checkable && root.checked)
    }
}
