import QtQuick
import QtTest
import "."

TestCase {
    name: "WindowSwitcher"
    when: windowShown
    width: 900
    height: 260
    SwitcherContent { id: panel; width: 800; height: 196 }

    function cleanup() {
        panel.requestedOpen = false
        tryCompare(panel, "mapped", false)
        panel.windows = []
        SwitcherService.open = false
        SwitcherService.session = ""
        SwitcherService.sequence = -1
    }
    function test_empty_input() {
        panel.requestedOpen = true
        wait(120)
        compare(panel.mapped, false)
        compare(panel.selectedIndex, -1)
        SwitcherService.enabled = true
        SwitcherService.consume({sequence: 1, session: "empty", visible: true, handles: []})
        compare(SwitcherService.open, false)
    }
    function test_stable_selection_and_close() {
        SwitcherService.enabled = true
        const event = {sequence: 1, session: "one", visible: true, handles: ["a", "b", "c"], selected: "b"}
        SwitcherService.consume(event)
        const rows = SwitcherService.windows
        panel.windows = rows
        panel.selectedHandle = "b"
        panel.requestedOpen = true
        tryCompare(panel, "revealProgress", 1)
        event.sequence = 2
        event.handles = ["c", "b", "a"]
        event.selected = "c"
        SwitcherService.consume(event)
        compare(SwitcherService.windows, rows)
        compare(SwitcherService.selectedHandle, "c")
        panel.selectedHandle = "c"
        compare(panel.selectedIndex, 2)
        compare(panel.revealProgress, 1)
        SwitcherService.consume({sequence: 3, visible: false})
        compare(SwitcherService.open, false)
        SwitcherService.consume(event)
        compare(SwitcherService.open, false)
    }
    function test_lost_compositor_lease() {
        SwitcherService.enabled = true
        SwitcherService.consume({sequence: 1, session: "lease", visible: true, handles: ["a"], selected: "a"})
        verify(SwitcherService.open)
        tryCompare(SwitcherService, "open", false, 1200)
    }
}
