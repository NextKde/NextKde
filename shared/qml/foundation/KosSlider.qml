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
    property real wheelStep: root.stepSize > 0
        ? root.stepSize
        : (root.to - root.from) / 100
    property real _wheelAccum: 0

    function _stepByWheel(delta) {
        if (!enabled || delta === 0)
            return
        const next = Math.max(root.from,
                              Math.min(root.to, root.value + delta * wheelStep))
        if (Math.abs(next - root.value) < 1e-9)
            return
        root.value = next
        root.moved()
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        enabled: root.enabled
        onWheel: function(wheel) {
            const dy = wheel.angleDelta.y !== 0
                ? wheel.angleDelta.y
                : wheel.pixelDelta.y * 8
            root._wheelAccum += dy
            // 攒够一格（120）才走一档，余量留着，下一格接着用
            while (Math.abs(root._wheelAccum) >= 120) {
                root._stepByWheel(root._wheelAccum > 0 ? 1 : -1)
                root._wheelAccum -= (root._wheelAccum > 0 ? 120 : -120)
            }
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
