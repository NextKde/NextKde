import QtQuick
import QtTest
import "."

TestCase {
    id: suite
    name: "ControlCenterSelection"
    when: windowShown
    visible: true
    width: 320
    height: 240
    property int clicks: 0

    Rectangle {
        id: button
        x: 30; y: 30; width: 137; height: 59; radius: 29.5
        color: "#007aff"
        MouseArea {
            id: inputArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: suite.clicks++
        }
        ControlCenterSelection {
            id: highlight
            pointer: inputArea
            cornerRadius: button.radius
        }
    }
    function init() {
        inputArea.enabled = true
        inputArea.focus = false
        suite.forceActiveFocus()
        AppearanceTokens.surface.selectionHighlightStyle = "glass"
        highlight.selected = false
        mouseMove(suite, 250, 200)
        tryCompare(highlight, "presence", 0)
        clicks = 0
    }
    function test_overlayDoesNotInterceptClicks() {
        mouseMove(button, 50, 25)
        tryCompare(highlight, "hovered", true)
        mousePress(button, 50, 25)
        compare(highlight.pressed, true)
        mouseRelease(button, 50, 25)
        compare(highlight.pressed, false)
        compare(clicks, 1)
        compare(button.color, "#007aff")
        compare(button.width, 137)
        compare(button.height, 59)
        compare(highlight.fillStrength, 0.35)
    }
    function test_selectedPersistsWithoutPointer() {
        highlight.selected = true
        tryCompare(highlight, "presence", 1)
        compare(highlight.hovered, false)
        highlight.selected = false
        tryCompare(highlight, "presence", 0)
    }
    function test_disabledAndFlatStyles() {
        highlight.selected = true
        inputArea.enabled = false
        compare(highlight.enabled, false)
        compare(highlight.visible, false)
        inputArea.enabled = true
        AppearanceTokens.surface.selectionHighlightStyle = "flat"
        compare(highlight.enabled, false)
        compare(highlight.visible, false)
    }
    function test_keyboardFocus() {
        inputArea.forceActiveFocus()
        tryCompare(highlight, "hovered", true)
        suite.forceActiveFocus()
        tryCompare(highlight, "hovered", false)
    }
}
