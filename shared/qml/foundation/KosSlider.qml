import QtQuick
import QtQuick.Controls

Slider {
    id: root

    implicitWidth: 220
    implicitHeight: AppTheme.controlHeight
    leftPadding: 2
    rightPadding: 2
    topPadding: 8
    bottomPadding: 8
    opacity: enabled ? 1 : 0.48

    // ── Ctrl+滚轮：精细步进 ────────────────────────────────────────────────
    // 光滚轮不接（滑块住在对话框里，那一下滚轮可能属于背后的面板）；按住 Ctrl
    // 才一档一档地走。stepSize 就是宿主声明的一档，没声明时按量程的 1% 走。
    // 走 Slider 自己的 value + moved()，宿主照旧在 onMoved 里回写。
    stepSize: (root.to - root.from) / 100
    property alias wheelStep: root.stepSize
    // 触控板给像素增量、鼠标给一格 120 的角度增量，分开累积（见 LiquidSlider）
    property real wheelPixelStep: 10
    property real _angleAccum: 0
    property real _pixelAccum: 0

    function _stepByWheel(delta) {
        if (!enabled || !visible || pressed || delta === 0)
            return
        const next = Math.max(root.from,
                              Math.min(root.to, root.value + delta * wheelStep))
        if (Math.abs(next - root.value) < 1e-9)
            return
        // Native setters preserve the host's QML value binding.
        if (delta > 0) root.increase()
        else root.decrease()
        root.moved()
    }

    function accumulateWheel(angleY, pixelY) {
        if (!enabled || !visible || pressed) return
        if (pixelY !== 0) {
            _pixelAccum += pixelY
            while (Math.abs(_pixelAccum) >= wheelPixelStep) {
                _stepByWheel(_pixelAccum > 0 ? 1 : -1)
                _pixelAccum -= (_pixelAccum > 0 ? wheelPixelStep : -wheelPixelStep)
            }
        } else if (angleY !== 0) {
            _angleAccum += angleY
            while (Math.abs(_angleAccum) >= 120) {
                _stepByWheel(_angleAccum > 0 ? 1 : -1)
                _angleAccum -= (_angleAccum > 0 ? 120 : -120)
            }
        }
    }

    // 滚轮挂在 MouseArea 自己的 onWheel 上（独立 WheelHandler 在这一层拿不到，
    // 见 LiquidSlider）。acceptedButtons: NoButton —— 只要滚轮，不抢 Slider 的拖动。
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        enabled: root.enabled
        onWheel: function(wheel) {
            if (!(wheel.modifiers & Qt.ControlModifier)) {
                wheel.accepted = false
                return
            }
            root.accumulateWheel(wheel.angleDelta.y, wheel.pixelDelta.y)
            wheel.accepted = true
        }
    }

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: 6
        radius: 3
        color: AppTheme.mix(AppTheme.button, AppTheme.mutedText, 0.12)

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: AppTheme.accent
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 20
        implicitHeight: 20
        radius: width / 2
        color: AppTheme.windowRaised
        border.width: root.activeFocus ? 3 : 1
        border.color: root.activeFocus ? AppTheme.accent : AppTheme.border
        scale: root.pressed ? 1.08 : 1

        Behavior on scale {
            NumberAnimation { duration: AppTheme.motionFast }
        }
    }
}
