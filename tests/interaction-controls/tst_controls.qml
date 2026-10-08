import QtQuick
import QtTest
import "../../shared/qml/controls" as Controls
import "../../shared/qml/foundation" as Foundation

Item {
    width: 560; height: 320
    property bool confirmed: false
    property int toggles: 0
    property bool requested: false
    property int triggers: 0
    property bool dragging: false
    property real confirmedValue: 0.4
    property real preview: confirmedValue
    property int commits: 0
    property int ancestorWheel: 0
    property real rampPreview: 0.5
    property int rampCommits: 0
    property int kosMoved: 0

    // 不带 Ctrl 的滚轮该穿给滑块所在的面板，所以这里放一个祖先捕手：它收到
    // 一次，就证明滑块没有把普通滚轮私吞。
    WheelHandler {
        acceptedModifiers: Qt.NoModifier
        onWheel: function(wheel) { ancestorWheel++; wheel.accepted = true }
    }

    Controls.LiquidGlassSwitch {
        id: sw; x: 30; y: 20
        checked: confirmed
        onToggled: function(value) { toggles++; requested = value }
    }
    Controls.LiquidGlassButton {
        id: button; x: 180; y: 20
        onTriggered: triggers++
    }
    Item {
        id: sliderHost; y: 100; width: 300; height: 44
        Controls.LiquidSlider {
            id: slider; anchors.fill: parent; value: preview
            onPreviewChanged: function(value) { dragging = true; preview = value }
            onCommitRequested: { dragging = false; commits++ }
            onCanceled: { dragging = false; preview = confirmedValue }
        }
    }
    Item {
        id: rampHost; x: 30; y: 170; width: 250; height: 26
        Controls.ColorRampSlider {
            id: ramp; anchors.fill: parent; value: rampPreview
            onPreviewChanged: function(value) { rampPreview = value }
            onCommitRequested: { rampCommits++ }
        }
    }
    Item {
        id: kosHost; x: 30; y: 220; width: 220; height: 40
        Foundation.KosSlider {
            id: kos; anchors.fill: parent
            from: 0.0; to: 1.0; stepSize: 0.01; value: 0.5
            onMoved: kosMoved++
        }
    }
    TestCase {
        name: "InteractionControls"; when: windowShown
        function init() {
            confirmed = false; toggles = 0; triggers = 0; commits = 0
            ancestorWheel = 0; rampCommits = 0; kosMoved = 0
            rampPreview = 0.5; kos.value = 0.5
            // 清掉上一个用例可能还挂着的步进提交，免得它落进本用例的计数
            slider._wheelPending = false
            ramp._wheelPending = false
            sliderHost.visible = true; slider.enabled = true
            preview = confirmedValue; dragging = false
            wait(250)
        }
        // 滚轮事件：按住 modifiers 才该生效的那个
        function wheel(target, dy, modifiers) {
            mouseWheel(target, target.width / 2, target.height / 2, 0, dy,
                       Qt.NoButton, modifiers)
        }
        function test_async_checked_binding() {            mouseClick(sw)
            compare(toggles, 1); verify(requested)
            verify(!sw.checked, "wait for confirmed state")
            confirmed = true; verify(sw.checked)
            confirmed = false; verify(!sw.checked, "external updates retain binding")
        }
        function test_release_outside_data() {
            return [{tag: "switch", button: false}, {tag: "button", button: true}]
        }
        function test_release_outside(data) {
            const target = data.button ? button : sw
            mousePress(target, 10, 10)
            mouseMove(target, target.width + 60, 10, 20)
            mouseRelease(target, target.width + 60, 10)
            compare(toggles + triggers, 0)
            verify(!target._pressed)
            mouseClick(target)
            compare(toggles + triggers, 1)
        }
        function test_single_position_animation() {
            const thumb = findChild(sw, "switch-glass-thumb")
            const shadow = findChild(sw, "switch-thumb-shadow")
            confirmed = true
            for (let i = 0; i < 8; ++i) {
                wait(20)
                fuzzyCompare(thumb.x + thumb.width / 2, shadow.x + shadow.width / 2, 0.1)
                fuzzyCompare(thumb.x + thumb.width / 2, 3 + sw._thumbX + sw.thumbWidth / 2, 0.1)
            }
        }
        function test_cancel_slider_data() {
            return [{tag: "hide", hide: true}, {tag: "disable", hide: false}]
        }
        function test_cancel_slider(data) {
            mousePress(slider, 220, 20)
            verify(dragging)
            if (data.hide) sliderHost.visible = false
            else slider.enabled = false
            tryCompare(slider, "_pressed", false)
            verify(!dragging)
            compare(preview, confirmedValue)
            compare(commits, 0, "cancel must not commit")
            confirmedValue = 0.7
            if (!dragging) preview = confirmedValue
            compare(slider.value, 0.7)
        }

        // ── Ctrl+滚轮：精细步进 ──────────────────────────────────────────
        // 普通滚轮不归滑块（面板还要滚），按住 Ctrl 才一档一档地调。
        function test_plain_wheel_passes_through() {
            preview = 0.5
            wheel(slider, 120, Qt.NoModifier)
            wait(80)
            fuzzyCompare(preview, 0.5, 1e-9)
            compare(commits, 0, "普通滚轮不该动值")
            compare(ancestorWheel, 1, "普通滚轮要穿给所在的面板")
        }
        function test_ctrl_wheel_steps_one_notch() {
            preview = 0.5
            wheel(slider, 120, Qt.ControlModifier)
            wait(60)
            fuzzyCompare(preview, 0.51, 1e-6)
            compare(ancestorWheel, 0, "Ctrl 滚轮归滑块，不再穿出去")
            tryCompare(slider, "_wheelPending", false)
            compare(commits, 1, "一次步进只提交一次")
        }
        function test_ctrl_wheel_down_clamps_at_end() {
            preview = 0.005
            wheel(slider, -120, Qt.ControlModifier)
            wait(60)
            fuzzyCompare(preview, 0.0, 1e-9)
            wheel(slider, -120, Qt.ControlModifier)
            wait(60)
            fuzzyCompare(preview, 0.0, 1e-9, "到底就停住，不会翻负")
        }
        function test_ctrl_wheel_burst_coalesces_one_commit() {
            preview = 0.5
            for (let i = 0; i < 3; ++i)
                wheel(slider, 120, Qt.ControlModifier)
            wait(320)
            fuzzyCompare(preview, 0.53, 1e-6)
            compare(commits, 1, "连转合并成一次提交，别每格都写平台服务")
        }
        function test_disabled_slider_ignores_wheel() {
            slider.enabled = false
            preview = 0.5
            wait(50)
            wheel(slider, 120, Qt.ControlModifier)
            wait(60)
            fuzzyCompare(preview, 0.5, 1e-9)
            compare(commits, 0)
        }
        function test_ctrl_wheel_steps_color_ramp() {
            rampPreview = 0.5
            wheel(ramp, 120, Qt.ControlModifier)
            wait(60)
            fuzzyCompare(rampPreview, 0.51, 1e-6)
            tryCompare(ramp, "_wheelPending", false)
            compare(rampCommits, 1)
        }
        function test_ctrl_wheel_steps_kos_slider() {
            kos.value = 0.5
            wheel(kos, 120, Qt.ControlModifier)
            wait(60)
            fuzzyCompare(kos.value, 0.51, 1e-6)
            compare(kosMoved, 1, "照旧走宿主的 moved() 回写")
        }
    }
}
