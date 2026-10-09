import QtQuick
import QtTest
import "../../shared/qml/foundation" as Foundation
import "../../shared/qml/controls" as Controls

Item {
    width: 320
    height: 240
    property real preview: 0.5

    Flickable {
        id: outer
        width: 300
        height: 200
        contentHeight: 2000
        contentWidth: 300

        Controls.LiquidSlider {
            id: slider
            x: 20
            y: 20
            width: 240
            height: 44
            value: preview
            onPreviewChanged: function(value) { preview = value; }
        }
        Flickable {
            id: inner
            x: 20
            y: 90
            width: 240
            height: 80
            contentHeight: 80
            contentWidth: 1000

            Rectangle { width: 1000; height: 80; color: "gray" }
            Foundation.KosKineticScroll { flickable: inner }
        }
        Foundation.KosKineticScroll { id: catcher; flickable: outer }
    }

    TestCase {
        name: "KineticInputOwnership"
        when: windowShown

        function init() {
            catcher._release();
            catcher.reducedMotion = false;
            outer.contentHeight = 2000;
            outer.contentY = 0;
            inner.contentX = 0;
            preview = 0.5;
            wait(80);
        }
        function test_ctrl_wheel_reaches_slider() {
            mouseWheel(slider, 120, 22, 0, 120, Qt.NoButton, Qt.ControlModifier);
            wait(40);
            fuzzyCompare(preview, 0.51, 0.00001);
        }
        function test_nested_gallery_keeps_wheel() {
            mouseWheel(inner, 120, 40, 0, -120);
            wait(400);
            verify(inner.contentX > 50, "Inner gallery must scroll; outer y=" + outer.contentY);
            compare(outer.contentY, 0);
        }
        function test_reduced_motion_uses_native_scroll() {
            catcher.reducedMotion = true;
            mouseWheel(outer, 150, 180, 0, -120);
            wait(100);
            verify(outer.contentY > 0);
            verify(!catcher._animating);
        }
        function test_input_burst_does_not_integrate_extra_frames() {
            const before = outer.contentY;
            for (let i = 0; i < 30; i++)
                catcher._onWheel(0, -1, 0, 0, false);
            compare(outer.contentY, before);
            tryVerify(function() { return outer.contentY > before; }, 300);
        }
        function test_empty_range_passes_wheel() {
            outer.contentHeight = outer.height;
            compare(catcher._onWheel(0, -120, 0, 0, false), false);
            verify(!catcher._animating);
        }
        function test_pixels_do_not_receive_added_inertia() {
            for (let i = 0; i < 4; i++) {
                compare(catcher._onWheel(0, 0, 0, -10, false), false);
                wait(20);
            }
            catcher._handStopped();
            verify(!catcher._vertical.released, "Pixel input must not release an additional glide");
            verify(!catcher._animating);
        }
    }
}
