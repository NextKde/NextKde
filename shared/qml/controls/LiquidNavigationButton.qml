import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

Button {
    id: root
    checkable: true
    // §4 侧栏「行高 30/26」+ §3 layout.sidebarRow=30（原 demo 值 38 不在档）。
    implicitHeight: 30
    leftPadding: 12
    rightPadding: 12
    hoverEnabled: true
    font.weight: checked ? Font.DemiBold : Font.Normal
    // §5 Pressed：scale .96、100ms（§3 motion.instant）。
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }
    contentItem: Text {
        text: root.text
        color: Foundation.AppTheme.text
        font: root.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: Item {
        LiquidSurface {
            anchors.fill: parent
            // §4 侧栏「行圆角 8」（§3 radius.sm，原 demo 值 10 偏离）。
            radius: 8
            tintColor: Foundation.AppTheme.accent
            tintStrength: root.checked ? 0.21 : 0.05
            visible: root.checked
        }
        // §4.1 Plain：hover 叠 hoverFill（light 黑 .06 / dark 白 .08）、
        // pressed 叠 pressFill（light 黑 .10 / dark 白 .12）；过渡 150ms（§3 motion.fast）。
        Rectangle {
            anchors.fill: parent
            radius: 8
            visible: root.enabled && !root.checked && (root.hovered || root.down)
            color: root.down
                ? (Foundation.AppTheme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
                : (Foundation.AppTheme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
            Behavior on color { ColorAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : 150 } }
        }
        // §5 Focus：外环 2px accent，偏移 2，圆角 +2；失焦或禁用即移除。
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: 10
            border.width: 2
            border.color: LiquidStyle.focusColor(Foundation.AppTheme.accent)
            color: "transparent"
            visible: root.activeFocus && root.enabled
        }
    }
    opacity: enabled ? 1 : 0.38
}
