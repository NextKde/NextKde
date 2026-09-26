import QtQuick
import QtTest
import "../../shared/qml/controls" as Controls

Item {
    width: 500; height: 240
    property bool confirmed: false
    property int toggles: 0
    property bool requested: false
    property int triggers: 0
    property bool dragging: false
    property real confirmedValue: 0.4
    property real preview: confirmedValue
    property int commits: 0
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
    TestCase {
        name: "InteractionControls"; when: windowShown
        function init() {
            confirmed = false; toggles = 0; triggers = 0; commits = 0
            sliderHost.visible = true; slider.enabled = true
            preview = confirmedValue; dragging = false
            wait(250)
        }
        function test_async_checked_binding() {
            mouseClick(sw)
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
    }
}
