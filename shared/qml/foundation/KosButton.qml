import QtQuick
import QtQuick.Controls

Button {
    id: root

    property bool destructive: false
    // D06: filled neutral capsule for a non-primary action (opt-in).
    property bool secondary: false
    // D06: force a white label on an emphasized button. Apple puts white on
    // the accent whatever the nominal contrast ratio says (opt-in, so the
    // app-wide `accentText` rule is untouched).
    property bool lightLabel: false
    // D06: macOS alert primaries are a flat fill — no drop shadow and no
    // 1px rim, unlike a toolbar/default emphasis (opt-in, so nothing else moves).
    property bool flatPrimary: false
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
        color: root.emphasized && root.lightLabel
            ? AppTheme.whiteSeed
            : !root.enabled
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
        radius: AppTheme.modernDesign ? height / 2 : Math.min(AppTheme.smallRadius, height / 2)
        fillColor: {
            if (root.emphasized)
                return root.down ? AppTheme.accentPressed
                    : (root.hovered ? AppTheme.accentHover : AppTheme.accent)
            if (root.flat && !root.hovered && !root.down)
                return "transparent"
            if (root.secondary)
                return root.down ? AppTheme.buttonNeutralPressed
                    : (root.hovered ? AppTheme.buttonNeutralHover
                                    : AppTheme.buttonNeutral)
            if (root.down)
                return AppTheme.buttonPressed
            return root.hovered ? AppTheme.buttonHover : AppTheme.button
        }
        strokeWidth: root.flatPrimary && root.emphasized
            ? 0
            : ((root.flat || root.secondary) && !root.hovered && !root.activeFocus ? 0 : 1)
        strokeColor: root.emphasized
            ? AppTheme.withAlpha(AppTheme.accentText, 0.16)
            : AppTheme.border
        elevation: root.secondary ? 0
            : (root.flatPrimary && root.emphasized ? 0
               : (root.flat && !root.hovered && !root.activeFocus ? 0
                  : (root.emphasized ? 0.68 : (root.hovered ? 0.62 : 0.42))))
        hovered: root.hovered
        pressed: root.down
        focused: root.activeFocus
        showInnerHighlight: (root.secondary || (root.flatPrimary && root.emphasized)) ? false : (!root.flat || root.hovered)
        opacity: root.enabled ? 1 : 0.68
    }
}
