import QtQuick
import QtQuick.Effects

// iOS-style liquid glass slider with true refraction.
// Uses ShaderEffect to bend the track colors through the glass thumb,
// with chromatic aberration and specular highlights.
Item {
    id: root

    SystemPalette {
        id: controlPalette
        colorGroup: SystemPalette.Active
    }

    implicitWidth: 240
    implicitHeight: 44

    property real value: 0.0
    property bool enabled: true
    property color accentColor: "#0a84ff"
    property color trackColor: Qt.rgba(0.5, 0.5, 0.55, 0.35)
    readonly property bool darkAppearance: {
        const color = controlPalette.window
        return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722 < 0.5
    }
    property color thumbColor: darkAppearance ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(1, 1, 1, 0.72)
    property color thumbBorderColor: darkAppearance
        ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.16)
    property real trackHeight: 6
    property real thumbWidth: 32
    property real thumbHeight: 16
    property bool chromaticAberration: false
    property bool wobbleEnabled: false

    // ── Form ──────────────────────────────────────────────────────────────
    // A tonal shell draws the Material 3 slider: a 4dp inactive track, a 16dp
    // active track that reaches the handle, a 4x44dp handle, and a state layer
    // under the pointer. The iOS form below (glass lens, chromatic aberration,
    // hover lift) is the liquid finish this form must not have, so it is hidden
    // rather than blended with it. Hosts set this instead of picking a
    // different control, so both forms share one interaction. It follows the
    // application-wide form by default.
    property bool materialForm: ControlForm.materialForm

    // Internal state
    property bool _pressed: false
    property bool _hovered: false
    property real _dragOffset: 0
    // 提交后短暂屏蔽 x 动画：外部服务异步写回（带量化偏差，如 54% -> 54.18%）时
    // 拇指直接跳变对齐，避免松开后滑一小步；之后恢复外部变化时的平滑动画
    property bool _suppressXAnimation: false
    Timer {
        id: suppressXAnimTimer
        interval: 400
        onTriggered: root._suppressXAnimation = false
    }

    // Geometry
    readonly property real visualValue: Math.max(0, Math.min(1, value))
    readonly property real edgeInset: thumbWidth / 2
    readonly property real travel: Math.max(1, width - edgeInset * 2)
    readonly property real thumbCenterX: edgeInset + visualValue * travel

    // Expansion animation (0 = rest white pill, 1 = fully expanded glass lens)
    property real _expansion: 0.0
    Behavior on _expansion {
        NumberAnimation {
            duration: root._pressed ? 270 : 460
            easing.type: root._pressed ? Easing.OutBack : Easing.OutQuint
            easing.overshoot: root._pressed ? 1.36 : 1.0
        }
    }

    // Squash-stretch wobble
    property real _stretch: 0.0
    SequentialAnimation on _stretch {
        id: wobbleAnim
        running: false
        NumberAnimation { to: 0.175; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { to: -0.08; duration: 150; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.04; duration: 120; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.0; duration: 100; easing.type: Easing.OutQuad }
    }

    signal previewChanged(real value)
    signal commitRequested(real value)
    signal canceled()

    function cancelInteraction() {
        const active = _pressed || _wheelPending
        _wheelPending = false
        wheelCommitTimer.stop()
        _angleAccum = 0
        _pixelAccum = 0
        if (!active) return
        _pressed = false
        _expansion = 0
        _dragOffset = 0
        canceled()
    }
    onEnabledChanged: { if (!enabled) cancelInteraction() }
    onVisibleChanged: { if (!visible) cancelInteraction() }

    // ── Ctrl+滚轮：精细步进 ────────────────────────────────────────────────
    // 光滚轮不碰滑块：滑块大多住在可滚动的面板里，那一下滚轮属于面板。按住 Ctrl
    // 才是"我要调这个滑块"：鼠标一格（±120）走一档，触控板的小增量先攒够一档再
    // 走，否则触控板会刷出一串碎步。wheelStep 是一档走多少行程，默认 1%；设置页
    // 按真实单位传（每档一格整数 / 1% 之类），窄区间才不至于每档都被舍入掉。
    property real wheelStep: 0.01
    // 一次滚轮事件有两种量级：鼠标是"一格 = angleDelta 的 ±120"；触控板在 Wayland 上
    // pixelDelta 与 angleDelta 一起给，量级小一个数量级（实测 |angle| ≈ 12 × |px|，
    // 所以鼠标那一格的量 ≈ 10px）。各按自己的量级累积，两种设备一档的手感才对得上：
    // 用同一个阈值，触控板要么"转不动"，要么两格才走一档。
    property real wheelPixelStep: 10
    property real _angleAccum: 0
    property real _pixelAccum: 0
    property bool _wheelPending: false

    // 收一档。基准取当前显示值（visualValue），与拖动同一条规矩：宿主把请求夹住
    // 或量化过（如不透明度有 10% 下限）时，下一次步进从夹住后的位置继续，不会在
    // 边界上攒一堆空档。preview 立刻生效，提交去抖合并——每转一格就写一次平台
    // 服务太贵。
    function stepByWheel(delta) {
        if (!enabled || !visible || _pressed || delta === 0)
            return
        const next = Math.max(0, Math.min(1, visualValue + delta * wheelStep))
        if (Math.abs(next - visualValue) < 1e-9)
            return
        _wheelPending = true
        previewChanged(next)
        wheelCommitTimer.restart()
    }

    // 喂进一次滚轮增量。pixelY 非 0 = 触控板（连续滚动），按像素攒；否则按鼠标的
    // 一格（120）攒。攒够一档才走，余量留着给下一次。
    function accumulateWheel(angleY, pixelY) {
        if (!enabled || !visible || _pressed) return
        if (pixelY !== 0) {
            _pixelAccum += pixelY
            while (Math.abs(_pixelAccum) >= wheelPixelStep) {
                stepByWheel(_pixelAccum > 0 ? 1 : -1)
                _pixelAccum -= (_pixelAccum > 0 ? wheelPixelStep : -wheelPixelStep)
            }
        } else if (angleY !== 0) {
            _angleAccum += angleY
            while (Math.abs(_angleAccum) >= 120) {
                stepByWheel(_angleAccum > 0 ? 1 : -1)
                _angleAccum -= (_angleAccum > 0 ? 120 : -120)
            }
        }
    }

    Timer {
        id: wheelCommitTimer
        interval: 180
        onTriggered: {
            if (!root._wheelPending)
                return
            root._wheelPending = false
            // 与松手提交一致：提交当前显示值
            root.commitRequested(root.value)
        }
    }

    opacity: enabled ? 1.0 : 0.45

    function positionForPointer(pointerX) {
        return Math.max(0, Math.min(1, (pointerX - edgeInset) / travel))
    }

    function triggerWobble() {
        if (wobbleEnabled)
            wobbleAnim.restart()
    }

    // Track container - this is what gets refracted through the glass
    Item {
        id: trackContainer
        anchors.fill: parent
        visible: !root.materialForm

        // Track background
        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: root.trackHeight
            radius: height / 2
            color: root.trackColor

            // Inner shadow for depth
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.12) }
                    GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.03) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.06) }
                }
            }
        }

        // Progress fill
        Rectangle {
            id: progress
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, Math.min(parent.width, root.thumbCenterX))
            height: root.trackHeight
            radius: height / 2
            color: root.accentColor

            // Glass sheen on progress
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.45) }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.12) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.0) }
                }
            }
        }
    }

    // The glass thumb/lens - uses layered optics for true translucent glass refraction
    Item {
        id: glassThumb
        // 中心固定在 thumbCenterX：x/width 用固定基准尺寸，展开形变走 transform Scale，
        // 避免收缩动画期间 x 绑定重算 + Behavior 滞后导致拇指中心偏移
        x: root.thumbCenterX - root.thumbWidth / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.thumbWidth
        height: root.thumbHeight
        visible: !root.materialForm

        transform: Scale {
            origin.x: root.thumbWidth / 2
            origin.y: root.thumbHeight / 2
            xScale: (1 + (root.wobbleEnabled ? 0.35 : 0.06) * root._expansion) * (1 - (root.wobbleEnabled ? 0.2 : 0) * root._stretch)
            yScale: (1 + (root.wobbleEnabled ? 0.35 : 0.06) * root._expansion) * (1 + (root.wobbleEnabled ? 0.4 : 0) * root._stretch)
        }

        Behavior on x {
            NumberAnimation {
                duration: root._pressed || root._suppressXAnimation ? 0 : 200
                easing.type: Easing.OutQuint
            }
        }

        // Layer 0: Ambient drop shadow for tactile physical depth
        Rectangle {
            anchors.fill: parent
            anchors.verticalCenterOffset: root._pressed ? 2.0 : (root._hovered ? 1.4 : 0.8)
            radius: height / 2
            color: root._pressed
                ? Qt.rgba(0, 0, 0, 0.32)
                : (root._hovered ? Qt.rgba(0, 0, 0, 0.24) : Qt.rgba(0, 0, 0, 0.16))
            z: -1
            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 160 } }
        }

        // Layer 1: Base translucent frosted glass matrix
        // Keeps the thumb legible while allowing underlying track & accent color to shine through
        Rectangle {
            id: basePill
            anchors.fill: parent
            radius: height / 2

            readonly property real baseAlpha: root.thumbColor.a < 0.95
                ? root.thumbColor.a
                : (root.darkAppearance ? 0.36 : 0.70)

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(
                        root.thumbColor.r,
                        root.thumbColor.g,
                        root.thumbColor.b,
                        Math.min(0.96, basePill.baseAlpha * (root._pressed ? 1.25 : (root._hovered ? 1.12 : 1.0))))
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(
                        root.thumbColor.r * 0.96,
                        root.thumbColor.g * 0.96,
                        root.thumbColor.b * 0.96,
                        Math.min(0.90, basePill.baseAlpha * 0.72 * (root._pressed ? 1.25 : (root._hovered ? 1.12 : 1.0))))
                }
            }

            border.width: 1
            border.color: root._pressed
                ? (root.darkAppearance ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.35))
                : (root._hovered
                    ? (root.darkAppearance ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.25))
                    : (root.thumbBorderColor.a > 0.01
                        ? root.thumbBorderColor
                        : (root.darkAppearance ? Qt.rgba(1, 1, 1, 0.32) : Qt.rgba(0, 0, 0, 0.16))))
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        // Layer 2: Liquid refraction & track accent transmission
        Rectangle {
            id: refractionLayer
            anchors.fill: parent
            radius: height / 2
            opacity: 0.50 + 0.40 * root._expansion
            Behavior on opacity { NumberAnimation { duration: 180 } }

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: root.visualValue > 0.05
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                                  root.darkAppearance ? (0.35 + 0.15 * root._expansion) : (0.22 + 0.12 * root._expansion))
                        : (root.darkAppearance ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(0, 0, 0, 0.08))
                }
                GradientStop {
                    position: 0.4
                    color: root.darkAppearance ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.25)
                }
                GradientStop {
                    position: 0.7
                    color: root.darkAppearance ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.20)
                }
                GradientStop {
                    position: 1.0
                    color: root.visualValue > 0.95
                        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b,
                                  root.darkAppearance ? (0.30 + 0.15 * root._expansion) : (0.18 + 0.12 * root._expansion))
                        : Qt.rgba(root.trackColor.r, root.trackColor.g, root.trackColor.b, 0.25)
                }
            }
        }

        // Layer 3: Top specular chamfer reflection (macOS glass convex curvature)
        Rectangle {
            id: specularHighlight
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: root._dragOffset * 0.12
            width: parent.width * 0.55
            height: Math.max(2, parent.height * 0.26)
            radius: height / 2

            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, root._pressed ? 0.75 : (root._hovered ? 0.65 : 0.45))
                }
                GradientStop {
                    position: 0.6
                    color: Qt.rgba(1, 1, 1, root._pressed ? 0.28 : (root._hovered ? 0.20 : 0.12))
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(1, 1, 1, 0.0)
                }
            }
            opacity: root.darkAppearance ? 0.85 : 0.95
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        // Layer 4: Delicate inner specular rim (bevel reflection)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: root._pressed
                ? Qt.rgba(1, 1, 1, 0.45)
                : (root._hovered ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.16))
            Behavior on border.color { ColorAnimation { duration: 160 } }
        }

        // Layer 5: Accent color glow on selection / press
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.accentColor
            opacity: root._pressed ? 0.16 : (root._hovered ? 0.08 : 0.03)
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        // Layer 6: Optional chromatic aberration (when explicitly enabled)
        Item {
            anchors.fill: parent
            visible: root.chromaticAberration && (root._hovered || root._pressed)
            opacity: root._expansion

            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 0.2, 0.2, 0.22 * root._expansion)
                x: -0.5
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(0.2, 0.9, 1, 0.22 * root._expansion)
                x: 0.5
            }
        }
    }

    // ── Material 3 form ───────────────────────────────────────────────────
    // Metrics scale with whatever height a host gives the slider, so a 30px
    // control centre row keeps the desktop's compact rhythm while a 44px row is
    // the Material spec exactly.
    Item {
        id: materialLayer
        anchors.fill: parent
        visible: root.materialForm

        readonly property real m3Scale: Math.min(1, root.height / 44)
        readonly property real inactiveTrack: Math.max(2, 4 * m3Scale)
        readonly property real activeTrack: Math.max(6, 16 * m3Scale)
        readonly property real handleWidth: Math.max(3, 4 * m3Scale)
        readonly property real handleHeight: Math.min(root.height, 44 * m3Scale)
        readonly property real handleX: root.thumbCenterX - handleWidth / 2

        // Inactive track: one thin capsule across the travel.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.edgeInset
            width: Math.max(0, root.width - root.edgeInset * 2)
            height: materialLayer.inactiveTrack
            radius: height / 2
            color: root.trackColor
        }

        // Active track: thicker, and it stops at the handle.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: root.edgeInset
            width: Math.max(0, materialLayer.handleX - root.edgeInset)
            height: materialLayer.activeTrack
            radius: height / 2
            color: root.accentColor
        }

        // State layer: M3 shows a halo at 10% on hover and 16% while pressed.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: materialLayer.handleX + materialLayer.handleWidth / 2 - width / 2
            width: height
            height: Math.min(root.height, 40 * materialLayer.m3Scale)
            radius: height / 2
            color: root.accentColor
            opacity: root._pressed ? 0.16 : (root._hovered ? 0.10 : 0.0)
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // Handle: a vertical capsule, not the iOS lens.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: materialLayer.handleX
            width: materialLayer.handleWidth
            height: materialLayer.handleHeight
            radius: width / 2
            color: root.accentColor
        }
    }

    // Mouse interaction
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        // 滚轮挂在 MouseArea 自己的 onWheel 上：MouseArea 盖满整个控件，独立的
        // WheelHandler 拿不到滚轮（实测滚轮完全收不到，见其提交说明），在这一层才
        // 收得到。只认 Ctrl（触控板两指滚动 + Ctrl 走的也是这条路）；不按 Ctrl 就
        // 放行，让所在面板照旧滚动。
        onWheel: function(wheel) {
            if (!(wheel.modifiers & Qt.ControlModifier)) {
                wheel.accepted = false
                return
            }
            root.accumulateWheel(wheel.angleDelta.y, wheel.pixelDelta.y)
            wheel.accepted = true
        }

        property real startX: 0
        property real startValue: 0

        // A light thumb lift on hover alone (before any press) matches
        // macOS's slider feel; press still drives the full lens expansion.
        onEntered: {
            root._hovered = true
            if (!root._pressed && !root.materialForm)
                root._expansion = 0.40
        }
        onExited: {
            root._hovered = false
            if (!root._pressed)
                root._expansion = 0.0
        }

        onPressed: function(mouse) {
            root._pressed = true
            root._expansion = 1.0
            root.triggerWobble()
            // 拖动接管：取消还没落下的那次步进提交
            root._wheelPending = false
            wheelCommitTimer.stop()
            root._angleAccum = 0
            root._pixelAccum = 0
            startX = mouse.x
            startValue = root.value
            root.previewChanged(root.positionForPointer(mouse.x))
        }

        onPositionChanged: function(mouse) {
            if (!pressed) return
            root._dragOffset = mouse.x - startX
            root.previewChanged(root.positionForPointer(mouse.x))
        }

        onReleased: function() {
            if (!root._pressed) return
            root._pressed = false
            root._expansion = (containsMouse && !root.materialForm) ? 0.40 : 0.0
            root._dragOffset = 0
            // 提交后屏蔽 x 动画 400ms，等外部服务异步写回对齐（见 _suppressXAnimation）
            root._suppressXAnimation = true
            suppressXAnimTimer.restart()
            // 提交当前显示值，而不是用松开瞬间的鼠标位置重新计算：
            // 松手时鼠标常会无意识前带 1~2px，重算会让 thumb 松开后再滑一小步
            root.commitRequested(root.value)
        }

        onCanceled: root.cancelInteraction()
    }
}
