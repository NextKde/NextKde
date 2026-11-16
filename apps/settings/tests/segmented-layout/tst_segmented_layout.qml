import QtQuick
import QtTest
import "../../components" as Controls

Item {
    id: harness
    width: 760
    height: 160
    Rectangle { anchors.fill: parent; color: "#d2e5c7" }
    readonly property var palette: ({dark: false, primaryText: "#262626"})
    SignalSpy { id: requested; signalName: "selectionChanged" }
    Component {
        id: navigation
        Controls.SettingsNavBar {
            colors: harness.palette
            itemWidthOverride: 76
            currentIndex: 0
            model: [{id: "full", label: "Full-width edge to edge"},
                    {id: "floating", label: "Floating capsule"}]
        }
    }
    Component {
        id: dropdown
        Controls.SettingsSelect {
            colors: harness.palette
            currentIndex: 1
            textRole: "label"
            model: [{id:"a",label:"First"}, {id:"b",label:"Second"},
                    {id:"c",label:"Third"}, {id:"d",label:"Fourth"}]
        }
    }
    TestCase {
        name: "SettingsCanonicalSegments"
        when: windowShown
        function cleanup() { requested.target = null; requested.clear() }
        function test_compactPopupSelection() {
            const picker = createTemporaryObject(dropdown, harness)
            verify(picker !== null)
            requested.target = picker
            mouseClick(picker, picker.width / 2, picker.height / 2)
            tryVerify(() => picker.popupOpened)
            const popup = findChild(picker, "Popup")
            verify(popup !== null, "popup exists")
            const selected = findChild(popup.contentItem, "Option1")
            const other = findChild(popup.contentItem, "Option0")
            verify(selected !== null && other !== null, "popup owns its ordinary option rows")
            const panel = findChild(popup.background, "PopupPanel")
            const shadow = findChild(popup.background, "PopupShadow")
            verify(panel !== null && shadow !== null)
            compare(panel.color, "#f0f0f1")
            compare(panel.border.width, 0)
            verify(shadow.visible && shadow.shadowOpacity > 0)
            compare(shadow.offset.x, 0)
            compare(shadow.offset.y, 0)
            verify(popup.width < 160, "short options must not keep the old 160 px minimum")
            verify(popup.width >= Math.ceil(popup.longestLabelWidth + 46), "reserve checkmark and text insets")
            compare(panel.color.a, 1)
            compare(popup.opacity, 1)
            compare(selected.height, 24)
            const optionText = selected.children.find(child => child.text === "Second")
            verify(optionText !== undefined)
            compare(optionText.font.weight, Font.Normal)
            verify(selected.selected && !selected.blueActive)
            verify(!other.selected && !other.blueActive)
            compare(selected.children[0].color, "#00000000")
            const check = selected.children.find(child => child.name === "check")
            verify(check !== undefined && check.visible)
            compare(check.color, "#1c1c1e")
            picker.closeMenu()
            tryVerify(() => !picker.popupOpened)
            compare(requested.count, 0, "opening and closing must not change the stored setting")
        }
        function test_plainDropdownHasNoBackground() {
            const picker = createTemporaryObject(dropdown, harness, {materialForm: false})
            verify(picker !== null)
            verify(waitForRendering(picker))
            const clear = () => {
                const point = picker.mapToItem(harness, Math.floor(picker.width / 2), picker.height - 2)
                return grabImage(harness).pixel(Math.floor(point.x), Math.floor(point.y))
            }
            const background = Qt.rgba(210 / 255, 229 / 255, 199 / 255, 1)
            compare(clear(), background)
            mouseMove(picker, picker.width / 2, picker.height / 2)
            verify(waitForRendering(picker))
            compare(clear(), background, "hover must not add a button fill")
            picker.forceActiveFocus(Qt.TabFocusReason)
            verify(waitForRendering(picker))
            compare(clear(), background, "focus must not add a button edge or fill")
            picker.materialForm = true
            verify(waitForRendering(picker))
            compare(clear(), background, "plain trigger is independent of popup material")
        }
        function test_dropdownPointerKeyboardAndConfirmation() {
            const picker = createTemporaryObject(dropdown, harness)
            verify(picker !== null)
            requested.target = picker
            compare(picker.height, 24)
            compare(picker.indicatorStyle, "upDown")
            verify(picker.plainTrigger)
            verify(waitForRendering(picker))
            mouseClick(picker, picker.width / 2, picker.height / 2)
            compare(requested.count, 0, "opening the menu does not save")
            tryVerify(() => picker.popupOpened)
            keyClick(Qt.Key_End)
            keyClick(Qt.Key_Return)
            compare(requested.count, 1)
            compare(requested.signalArguments[0][0], 3)
            compare(picker.currentIndex, 1, "the host must confirm the choice")
            tryCompare(picker, "_visualIndex", 1, 1000)
            picker.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Space)
            tryVerify(() => picker.popupOpened)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Return)
            compare(requested.signalArguments[1][0], 2)
            picker.currentIndex = 2
            compare(picker._visualIndex, 2)
            picker.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Space)
            tryVerify(() => picker.popupOpened)
            keyClick(Qt.Key_Escape)
            compare(requested.count, 2, "cancelling a menu must not save")
            picker.disabled = true
            mouseClick(picker, picker.width / 2, picker.height / 2)
            keyClick(Qt.Key_Return)
            compare(requested.count, 2, "disabled choice is inert")
        }
        function test_labelsMeasureAndReflow() {
            const bar = createTemporaryObject(navigation, harness)
            verify(bar !== null)
            verify(bar.implicitWidth > 2 * 76)
            const english = bar.implicitWidth
            bar.model = [{id:"full",label:"全宽贴边"},{id:"floating",label:"悬浮胶囊"}]
            verify(bar.implicitWidth < english)
            compare(bar.height, 24)
        }
        function test_clickKeepsHostOwnedStateAndKeyboard() {
            const bar = createTemporaryObject(navigation, harness, {width: 228})
            requested.target = bar
            mouseClick(bar, bar.width - 15, bar.height / 2)
            compare(requested.count, 1)
            compare(requested.signalArguments[0][0], 1)
            compare(bar.currentIndex, 0, "only the backend adapter confirms selection")
            bar.currentIndex = 1
            bar.width = 390
            wait(350)
            verify(bar._lensPosition >= 0)
            verify(bar._lensPosition + bar.segmentWidth <= bar.width)
            keyClick(Qt.Key_Home)
            compare(requested.signalArguments[1][0], 0)
        }
    }
}
