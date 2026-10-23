import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

Button {
    id: root
    property bool secondary: false
    property bool destructive: false
    hoverEnabled: true
    implicitHeight: 36
    implicitWidth: Math.max(76, contentItem.implicitWidth + 28)
    leftPadding: 14
    rightPadding: 14
    scale: down ? 0.96 : hovered ? 1.02 : 1
    Behavior on scale { NumberAnimation { duration: Foundation.AppTheme.motionFast; easing.type: Easing.OutCubic } }
    opacity: enabled ? 1 : 0.38
    contentItem: Label {
        text: root.text
        font: root.font
        color: root.destructive ? Foundation.AppTheme.destructive : Foundation.AppTheme.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: LiquidSurface {
        radius: height / 2
        tintColor: root.highlighted || root.checked ? Foundation.AppTheme.accent
            : Foundation.AppTheme.dark ? "#17223b" : "#ffffff"
        tintStrength: root.highlighted || root.checked ? 0.24 : root.down ? 0.18
            : root.hovered ? 0.12 : root.secondary ? 0.03 : 0.05
        opacity: root.flat && !root.hovered && !root.checked && !root.activeFocus ? 0.45 : 1
        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: Foundation.AppTheme.focusRing
            visible: root.activeFocus
        }
    }
}
