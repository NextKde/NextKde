import QtQuick

// Compact iOS-style slider for continuous color ramps. The caller owns the
// value so preview updates can remain local and persistence can happen only
// after the pointer is released.
Item {
    id: root

    implicitWidth: 250
    implicitHeight: 26

    property real value: 0.5
    property var rampColors: []
    property color thumbColor: "#ffffff"
    property bool enabled: true

    signal previewChanged(real value)
    signal commitRequested(real value)

    readonly property real clampedValue: Math.max(0, Math.min(1, value))
    property real thumbDiameter: 18
    property real trackHeight: 8
    readonly property real trackInset: thumbDiameter / 2
    readonly property real travel: Math.max(1, width - trackInset * 2)
    readonly property real thumbCenterX: trackInset + clampedValue * travel

    opacity: enabled ? 1 : 0.45

    // ── Ctrl+滚轮：精细步进（与 LiquidSlider 同一条规约）──────────────────
    // 光滚轮不接，留给滑块所在的面板滚动；按住 Ctrl 才一档一档地走。
    property real wheelStep: 0.01
    // 触控板给像素增量、鼠标给一格 120 的角度增量，分开累积（见 LiquidSlider）
    property real wheelPixelStep: 10
    property real _angleAccum: 0
    property real _pixelAccum: 0
    property bool _wheelPending: false

    function stepByWheel(delta) {
        if (!enabled || delta === 0)
            return
        const next = Math.max(0, Math.min(1, clampedValue + delta * wheelStep))
        if (Math.abs(next - clampedValue) < 1e-9)
            return
        _wheelPending = true
        previewChanged(next)
        wheelCommitTimer.restart()
    }

    function accumulateWheel(angleY, pixelY) {
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
            root.commitRequested(root.clampedValue)
        }
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        enabled: root.enabled
        onWheel: function(wheel) {
            root.accumulateWheel(wheel.angleDelta.y, wheel.pixelDelta.y)
            wheel.accepted = true
        }
    }

    function rampColor(index) {
        return rampColors.length > index ? rampColors[index] : "transparent"
    }

    function valueAt(pointerX) {
        return Math.max(0, Math.min(1, (pointerX - trackInset) / travel))
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.trackInset
        anchors.rightMargin: root.trackInset
        anchors.verticalCenter: parent.verticalCenter
        height: root.trackHeight
        radius: height / 2
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.16)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0 / 6; color: root.rampColor(0) }
            GradientStop { position: 1 / 6; color: root.rampColor(1) }
            GradientStop { position: 2 / 6; color: root.rampColor(2) }
            GradientStop { position: 3 / 6; color: root.rampColor(3) }
            GradientStop { position: 4 / 6; color: root.rampColor(4) }
            GradientStop { position: 5 / 6; color: root.rampColor(5) }
            GradientStop { position: 6 / 6; color: root.rampColor(6) }
        }
    }

    Rectangle {
        x: root.thumbCenterX - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.thumbDiameter
        height: width
        radius: width / 2
        color: "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.18)
        scale: pointerArea.pressed ? 1.12 : 1

        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: width / 2
            color: root.thumbColor
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.12)
        }
    }

    MouseArea {
        id: pointerArea
        anchors.fill: parent
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor

        onPressed: function(mouse) {
            // 拖动接管：取消还没落下的那次步进提交
            root._wheelPending = false
            wheelCommitTimer.stop()
            root.previewChanged(root.valueAt(mouse.x))
        }
        onPositionChanged: function(mouse) {
            if (pressed)
                root.previewChanged(root.valueAt(mouse.x))
        }
        // The owner's preview handler updates `value` through a binding. On a
        // release immediately following a drag that binding can still expose
        // the previous value for this event turn, which persisted the old
        // colour and snapped the thumb back. Commit the pointer position
        // directly instead.
        onReleased: function(mouse) {
            root.commitRequested(root.valueAt(mouse.x))
        }
    }
}
