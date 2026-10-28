import QtQuick
import QtTest
import "../../components" as Controls

Item {
    id: harness
    width: 760
    height: 160
    readonly property var palette: ({dark: false, primaryText: "#262626"})
    SignalSpy { id: requested; signalName: "selectionChanged" }
    Component {
        id: navigation
        Controls.SettingsNavBar {
            colors: harness.palette
            itemWidthOverride: 76
            currentIndex: 1
            model: [{id: "full", label: "Full-width edge to edge"},
                    {id: "floating", label: "Floating capsule"},
                    {id: "transparent", label: "Fully transparent"}]
        }
    }
    TestCase {
        name: "SettingsCanonicalSegments"
        when: windowShown
        function cleanup() { requested.target = null; requested.clear() }
        function test_labelsMeasureAndReflow() {
            const bar = createTemporaryObject(navigation, harness)
            verify(bar !== null)
            verify(bar.implicitWidth > 3 * 76)
            const english = bar.implicitWidth
            bar.model = [{id:"full",label:"全宽贴边"},{id:"floating",label:"悬浮胶囊"},{id:"transparent",label:"全透明"}]
            verify(bar.implicitWidth < english)
            compare(bar.height, 26)
        }
        function test_clickKeepsHostOwnedStateAndKeyboard() {
            const bar = createTemporaryObject(navigation, harness, {width: 228})
            requested.target = bar
            mouseClick(bar, bar.width - 15, bar.height / 2)
            compare(requested.count, 1)
            compare(requested.signalArguments[0][0], 2)
            compare(bar.currentIndex, 1, "only the backend adapter confirms selection")
            bar.currentIndex = 2
            bar.width = 390
            wait(350)
            verify(bar._lensPosition >= 0)
            verify(bar._lensPosition + bar.segmentWidth <= bar.width)
            keyClick(Qt.Key_Home)
            compare(requested.signalArguments[1][0], 0)
        }
    }
}
