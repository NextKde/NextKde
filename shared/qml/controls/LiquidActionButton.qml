import QtQuick
import QtQuick.Controls
import "../foundation" as Foundation

Button {
    id: root
    property bool secondary: false
    property bool destructive: false
    hoverEnabled: true
    // §4.2 尺寸档 lg：高 34、水平内边距 16。
    implicitHeight: 34
    implicitWidth: Math.max(76, contentItem.implicitWidth + 32)
    leftPadding: 16
    rightPadding: 16
    // §4.1：hover 只改背景不改 scale；§5 Pressed：scale .96、100ms。
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic } }
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
        tintColor: root.destructive ? Foundation.AppTheme.destructive
            : root.highlighted || root.checked ? Foundation.AppTheme.accent
            : Foundation.AppTheme.dark ? "#17223b" : "#ffffff"
        // §4.2 Destructive：danger tint .18；hover/pressed 仍走下方 hoverFill/pressFill 叠层。
        tintStrength: root.destructive ? 0.18
            : root.highlighted || root.checked
                ? (root.down ? 0.30 : root.hovered ? 0.26 : 0.21)
            : root.secondary ? 0.03 : 0.05
        opacity: root.flat && !root.hovered && !root.checked && !root.activeFocus ? 0.45 : 1
        // §4.1：hover 叠 hoverFill（light 黑 .06 / dark 白 .08）、pressed 叠 pressFill
        // （light 黑 .10 / dark 白 .12）；Primary tinted 变体走上面 tint .26/.30 分支。
        // 过渡 150ms（§3 motion.fast）。
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            visible: root.enabled && (root.down || root.hovered)
                     && !(root.highlighted || root.checked)
            color: root.down
                ? (Foundation.AppTheme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
                : (Foundation.AppTheme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06))
            Behavior on color { ColorAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : 150 } }
        }
        // §4.2/§5 Focus：外环 2px accent，偏移 2（margins −4 扣描边 2 留白恰 2px），
        // 圆角 +2（胶囊 radius 随环高度自然 +2）；失焦或禁用即移除。
        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: height / 2
            color: "transparent"
            border.width: 2
            border.color: LiquidStyle.focusColor(Foundation.AppTheme.accent)
            visible: root.activeFocus && root.enabled
        }
    }
}
