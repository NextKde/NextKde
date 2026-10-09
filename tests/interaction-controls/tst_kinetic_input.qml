import QtQuick
import QtTest
import QtQuick.Controls as QtControls
import "../../shared/qml/foundation" as Foundation
import "../../shared/qml/controls" as Controls

Item {
    width: 700
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

    QtControls.ScrollView {
        id: wrapped
        x: 340
        width: 300
        height: 200
        contentWidth: 300
        contentHeight: 1000
        Item {
            width: 300
            height: 1000
            Controls.LiquidSlider {
                id: wrappedSlider
                x: 20; y: 10; width: 240; height: 44
                value: preview
                onPreviewChanged: function(value) { preview = value; }
            }
            Flickable {
                id: wrappedInner
                x: 20; y: 70; width: 240; height: 80
                contentWidth: 1000
                contentHeight: 80
                Rectangle { width: 1000; height: 80; color: "gray" }
                Foundation.KosKineticScroll {}
            }
        }
    }
    Foundation.KosKineticScroll { id: wrappedPolicy; target: wrapped }

    TestCase {
        name: "KineticInputOwnership"
        when: windowShown

        function init() {
            wrappedPolicy._release();
            wrappedPolicy.enabled = true;
            wrappedPolicy.reducedMotion = false;
            wrapped.contentItem.contentY = 0;
            wrappedInner.contentX = 0;
            catcher._release();
            catcher.reducedMotion = false;
            outer.pixelAligned = false;
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
                catcher._onWheel(0, -120, 0, 0, false);
            compare(outer.contentY, before);
            tryVerify(function() { return outer.contentY > before; }, 300);
        }
        function test_empty_range_passes_wheel() {
            outer.contentHeight = outer.height;
            compare(catcher._onWheel(0, -120, 0, 0, false), false);
            verify(!catcher._animating);
        }
        function test_pixels_use_native_frames_without_extra_distance() {
            compare(catcher._onWheel(0, 0, 0, -2, false), true);
            compare(outer.contentY, 2);
            const before = outer.contentY;
            for (let i = 0; i < 10; ++i)
                compare(catcher._onWheel(0, 0, 0, -10, false), true);
            // A synchronous input burst updates the target, not layout ten times.
            compare(outer.contentY, before);
            compare(catcher._vertical.target, 102);
            verify(catcher._pixelAnimating);
            verify(!catcher._animating);
            tryCompare(outer, "contentY", 102, 500, 0.5);
            wait(100);
            compare(outer.contentY, 102);
        }
        function test_continuous_input_prefers_kde_angle_channel() {
            compare(catcher._onWheel(0, -120, 0, -5, false), true);
            compare(catcher._vertical.target, 72);
            tryCompare(outer, "contentY", 72, 500, 0.5);
        }
        function test_zero_delta_markers_do_not_interrupt_native_tail() {
            compare(catcher._onWheel(0, 0, 0, 0, false), true);
            catcher._onWheel(0, 0, 0, -100, false);
            wait(20);
            compare(catcher._onWheel(0, 0, 0, 0, false), true);
            verify(catcher._pixelAnimating);
            tryCompare(outer, "contentY", 100, 500, 0.5);
        }
        function test_fine_angle_only_input_uses_native_smoothing() {
            compare(catcher._onWheel(0, -15, 0, 0, false), true);
            verify(catcher._pixelAnimating);
            verify(!catcher._animating);
            compare(catcher._vertical.target, 9);
            tryCompare(outer, "contentY", 9, 500, 0.5);
        }
        function test_pixel_aligned_views_finish_native_motion() {
            outer.pixelAligned = true;
            catcher._onWheel(0, 0, 0, -30, false);
            wait(20);
            catcher._onWheel(0, 0, 0, -30, false);
            tryCompare(outer, "contentY", 60, 500, 0.5);
            tryVerify(function() { return !catcher._pixelAnimating; }, 300);
            compare(catcher._writtenY, outer.contentY);
        }
        function test_scrollview_pixels_share_native_animation_policy() {
            compare(wrappedPolicy._onWheel(0, 0, 0, -30, false), true);
            verify(wrappedPolicy._pixelAnimating);
            tryCompare(wrapped.contentItem, "contentY", 30, 500, 0.5);
            verify(!wrappedPolicy._animating);
        }
        function test_scrollview_preserves_ctrl_slider_and_nested_gallery() {
            mouseWheel(wrappedSlider, 120, 22, 0, 120, Qt.NoButton, Qt.ControlModifier);
            fuzzyCompare(preview, 0.51, 0.00001);
            compare(wrapped.contentItem.contentY, 0);
            mouseWheel(wrappedInner, 120, 40, 0, -120);
            tryVerify(function() { return wrappedInner.contentX > 50; }, 500);
            compare(wrapped.contentItem.contentY, 0);
        }
        function test_scrollview_restores_native_handling_when_disabled() {
            compare(wrapped.wheelEnabled, false);
            wrappedPolicy.enabled = false;
            compare(wrapped.wheelEnabled, true);
            mouseWheel(wrapped, 150, 175, 0, -120);
            tryVerify(function() { return wrapped.contentItem.contentY > 0; }, 500);
            verify(!wrappedPolicy._animating);
        }
        function test_pixel_reversal_cancels_pending_forward_motion() {
            catcher._onWheel(0, 0, 0, -200, false);
            wait(40);
            const before = outer.contentY;
            catcher._onWheel(0, 0, 0, 20, false);
            verify(catcher._vertical.target < before);
            tryCompare(outer, "contentY", before - 20, 500, 0.5);
        }
        function test_hiding_view_cancels_native_animation() {
            catcher._onWheel(0, 0, 0, -200, false);
            wait(20);
            outer.visible = false;
            verify(!catcher._pixelAnimating);
            const stopped = outer.contentY;
            wait(100);
            compare(outer.contentY, stopped);
            outer.visible = true;
        }
        function test_pixel_to_wheel_switch_has_no_stale_speed() {
            catcher._onWheel(0, 0, 0, -30, false);
            wait(10);
            catcher._onWheel(0, 0, 0, -30, false);
            const start = outer.contentY;
            catcher._onWheel(0, -120, 0, 0, false);
            tryCompare(outer, "contentY", start + 72, 500, 0.5);
        }
        function test_pixels_respect_hidden_and_disabled_views() {
            outer.visible = false;
            compare(catcher._onWheel(0, 0, 0, -30, false), false);
            outer.visible = true;
            outer.enabled = false;
            compare(catcher._onWheel(0, 0, 0, -30, false), false);
            outer.enabled = true;
        }
    }
}
