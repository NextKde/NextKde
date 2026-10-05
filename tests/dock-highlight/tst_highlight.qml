import QtQuick
import QtTest
import "../../shell/desktop/modules/dock" as Dock

TestCase {
    id: suite
    name: "DockSelectionHighlight"
    when: windowShown
    visible: true
    width: 240
    height: 200

    Dock.DockIconHighlight {
        id: plate
        x: 30
        y: 30
        width: 52
        height: 52
    }

    function init() {
        plate.enabled = true
        plate.hovered = false
        plate.selected = false
        plate.pressed = false
        plate.dark = true
        tryCompare(plate, "presence", 0)
        tryCompare(plate, "hoverAmount", 0)
        tryCompare(plate, "selectionAmount", 0)
        tryCompare(plate, "pressAmount", 0)
    }
    function test_idleDoesNotPaint() {
        compare(plate.visible, false)
        compare(plate.highlighted, false)
        compare(plate.layer.enabled, false)
    }
    function test_hoverFadesAndKeepsGeometry() {
        plate.hovered = true
        compare(plate.highlighted, true)
        compare(plate.presence, 0) // no instantaneous flash
        tryCompare(plate, "presence", 1)
        tryCompare(plate, "hoverAmount", 1)
        compare(plate.width, 52)
        compare(plate.height, 52)
        compare(plate.scale, 1)
        compare(plate.x, 30)
        compare(plate.y, 30)
        plate.hovered = false
        tryCompare(plate, "presence", 0)
        compare(plate.visible, false)
    }
    function test_selectedHoverAndPressAreDistinct() {
        plate.selected = true
        tryCompare(plate, "selectionAmount", 1)
        tryCompare(plate, "presence", 1)
        const activeTop = plate.topAlpha
        const activeRim = plate.rimAlpha
        plate.hovered = true
        tryCompare(plate, "hoverAmount", 1)
        verify(plate.topAlpha > activeTop)
        verify(plate.rimAlpha > activeRim)
        const hoverTop = plate.topAlpha
        plate.pressed = true
        tryCompare(plate, "pressAmount", 1)
        verify(plate.topAlpha > hoverTop)
        verify(plate.topAlpha < 0.5, "the selected icon must not get an opaque white tile")
        plate.pressed = false
        plate.hovered = false
        tryCompare(plate, "hoverAmount", 0)
        tryCompare(plate, "pressAmount", 0)
        compare(plate.presence, 1) // selected state survives pointer exit
        compare(plate.topAlpha, activeTop)
    }
    function test_rapidExitAndCancel() {
        plate.hovered = true
        plate.pressed = true
        wait(20)
        plate.hovered = false
        plate.pressed = false
        tryCompare(plate, "presence", 0)
        tryCompare(plate, "pressAmount", 0)
        compare(plate.visible, false)
    }
    function test_disabledDoesNotCompeteWithUrgencyOrEditing() {
        plate.selected = true
        plate.hovered = true
        plate.pressed = true
        tryCompare(plate, "presence", 1)
        plate.enabled = false
        compare(plate.visible, false)
        tryCompare(plate, "presence", 0)
        tryCompare(plate, "hoverAmount", 0)
        tryCompare(plate, "selectionAmount", 0)
        tryCompare(plate, "pressAmount", 0)
    }
    function test_lightAndDarkStayTranslucent() {
        plate.selected = true
        plate.hovered = true
        plate.pressed = true
        tryCompare(plate, "selectionAmount", 1)
        tryCompare(plate, "hoverAmount", 1)
        tryCompare(plate, "pressAmount", 1)
        for (const dark of [false, true]) {
            plate.dark = dark
            verify(plate.topAlpha > plate.bottomAlpha)
            verify(plate.topAlpha > 0 && plate.topAlpha < 0.75)
            verify(plate.bottomAlpha > 0 && plate.bottomAlpha < 0.25)
            verify(plate.rimAlpha > 0 && plate.rimAlpha < 1)
        }
    }
}
