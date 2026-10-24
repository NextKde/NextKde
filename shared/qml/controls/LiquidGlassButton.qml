import QtQuick
import QtQuick.Effects
import "../foundation" as Foundation

// iOS-style liquid glass button with pure QML rendering.
// No external texture needed - uses mathematical gradients to simulate refraction.
Item {
    id: root
    // §4.2 焦点：外环 2px accent，偏移 2；§5 Focus「圆角 +2」。
    activeFocusOnTab: true
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.enabled) root.triggered()
            event.accepted = true
        }
    }

    // Public API
    property string symbol: ""
    property bool primary: false
    property bool enabled: true
    property color accentColor: "#0a84ff"
    property color iconColor: "white"
    signal triggered()

    // Internal state
    property bool _pressed: false
    property bool _hovered: false

    // Size（§4.2 Icon-only：视觉 28/34，「同组同尺寸」——主次只靠变体区分不靠尺寸；
    // 取 lg=34，§3 control.lg。原 demo 52/40 不在 24/28/34/44 档且按变体分尺寸。）
    implicitWidth: 34
    implicitHeight: implicitWidth

    // Expansion animation (0 = rest, 1 = fully expanded glass)
    property real _expansion: _pressed ? 1.0 : (_hovered ? 0.3 : 0.0)
    Behavior on _expansion {
        NumberAnimation {
            // §3 motion.duration：按下 instant=100 / 其余过渡 fast=150（原 demo 200/350
            // 均不在 §3 五档内；§4.1「过渡 150ms；按下 100ms」）
            // §2.12 减动态：reduceMotion 时一步到位。
            duration: Foundation.AppTheme.reduceMotion ? 0 : (_pressed ? 100 : 150)
            easing.type: _pressed ? Easing.OutBack : Easing.OutQuint
            easing.overshoot: _pressed ? 1.4 : 1.0
        }
    }

    // Squash-stretch wobble on press
    property real _stretch: 0.0
    SequentialAnimation on _stretch {
        id: wobbleAnim
        running: false
        // §2.11 / §3 motion.duration：只允许 100/150/220/320/400 五档
        // （原 demo 80/120/100/80 中 80/120 不在档）。
        NumberAnimation { to: 0.15; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { to: -0.06; duration: 150; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.03; duration: 100; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 100; easing.type: Easing.OutQuad }
    }

    // §5 Disabled：整体 α .38（原 demo 0.5）；§4.2「禁用：α .38，无高光/阴影/hover」
    opacity: enabled ? 1.0 : 0.38
    // §5 Pressed：scale .96（§3 motion.pressScale）；Hover 只改背景，不加缩放
    // （原 demo 按压 .92 / hover 1.05）
    scale: _pressed ? 0.96 : 1.0
    Behavior on scale {
        // §2.12 减动态：reduceMotion 时不走过渡。
        NumberAnimation { duration: Foundation.AppTheme.reduceMotion ? 0 : (_pressed ? 100 : 150); easing.type: Easing.OutCubic }
    }

    // Drop shadow — §3 elevation.E1 `0 2 8 rgba(0,0,0,0.14)`（原 demo 无 blur 的
    // 0.25 实色椭圆且随 hover 淡出；§4.1「hover 只改背景」→ 阴影恒 E1、不随展开变化）。
    Rectangle {
        id: shadow
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2
        width: parent.width * 0.9
        height: parent.height * 0.9
        radius: width / 2
        color: Qt.rgba(0, 0, 0, 0.14)
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 8
            blur: 1.0
        }
    }

    // Glass body - multi-layer gradients simulate refraction
    Item {
        id: glassBody
        anchors.centerIn: parent
        width: parent.width * (0.85 + 0.35 * root._expansion) * (1 - 0.15 * root._stretch)
        height: parent.height * (0.85 + 0.35 * root._expansion) * (1 + 0.25 * root._stretch)

        // Layer 1: Base glass with radial gradient (edge bright, center dark)
        Rectangle {
            id: baseGlass
            anchors.fill: parent
            radius: width / 2

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.25 + 0.15 * root._expansion) }
                GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.12 + 0.08 * root._expansion) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.06 + 0.04 * root._expansion) }
                GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.10 + 0.06 * root._expansion) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.20 + 0.10 * root._expansion) }
            }

            // Inner rim light
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35 + 0.25 * root._expansion)
            }
        }

        // Layer 2: Chromatic aberration (RGB split edges)
        // Red channel offset
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 0.25, 0.25, 0.20 * root._expansion)
            x: -0.5
            visible: root._expansion > 0.1
        }
        // Cyan channel offset
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0.25, 0.85, 1, 0.20 * root._expansion)
            x: 0.5
            visible: root._expansion > 0.1
        }

        // Layer 3: Specular highlight (soft, top-positioned)
        Rectangle {
            id: specular
            anchors.top: parent.top
            anchors.topMargin: parent.height * 0.08
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.45
            height: parent.height * 0.28
            radius: width / 2

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.45 + 0.25 * root._expansion) }
                GradientStop { position: 0.6; color: Qt.rgba(1, 1, 1, 0.15 + 0.10 * root._expansion) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
            }
            opacity: 0.6 + 0.4 * root._expansion
        }

        // Layer 4: Accent tint (subtle color bleed when expanded)
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.accentColor
            opacity: 0.08 * root._expansion
        }

        // Layer 5: Inner glow (soft fill from edges)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(1, 1, 1, 0.08 * root._expansion)
        }
    }

    // Icon (crisp layer on top)
    Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.symbol === "▶" ? 1 : 0
        text: root.symbol
        color: root.iconColor
        style: (root.iconColor === "#ffffff" || root.iconColor === "white" || String(root.iconColor).toLowerCase() === "#ffffffff")
            ? Text.Outline : Text.Normal
        styleColor: Qt.rgba(0, 0, 0, 0.45)
        // §4.2 lg 档「图标 18」+ §4.3「按钮内 14–20」；原 demo 16/12（12 越下限）
        font.pixelSize: 18
        font.weight: Font.Medium
    }

    // Interaction
    MouseArea {
        id: mouseArea
        // §3 control.hit.touch=44 / §4.2「图标按钮：视觉 28/34，热区 ≥ 28（指针）/ 44（触控）」：
        // 视觉 34 不变，命中区向外扩到 ≥44×44（原 demo 与视觉同尺寸 34×34）。
        anchors.centerIn: parent
        width: Math.max(parent.width, 44)
        height: Math.max(parent.height, 44)
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onEntered: root._hovered = true
        onExited: root._hovered = false

        onPressed: {
            root._pressed = true
            root.forceActiveFocus()
            // §2.12 减动态：reduceMotion 时不播放挤压回弹。
            if (!Foundation.AppTheme.reduceMotion) wobbleAnim.restart()
        }

        onReleased: {
            root._pressed = false
        }

        onClicked: root.triggered()

        onCanceled: {
            root._pressed = false
        }
    }

    // §4.2 焦点外环：2px accent、距按钮外缘偏移 2（rect 外扩 4 + 2px 边 → 内缘留 2px）；
    // §5「圆角 +2」在圆形控件上取同心圆（环 rect 半径 = 宽/2）；§3 color.focusFallback 取色。
    // 失焦或禁用即移除。
    Rectangle {
        id: focusRing
        anchors.fill: parent
        anchors.margins: -4
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: LiquidStyle.focusColor(root.accentColor)
        visible: root.activeFocus && root.enabled
        z: 10
    }
}
