import QtQuick
import QtTest
Item {
    property var settingsBridge: bridge
    QtObject {
        id: bridge
        property bool sourceTreeEntry: false
        property string sessionShellDir: ""
        property bool developmentBannerDismissed: false
        property string lastError: ""
        property var snapshot: ({baseHeight:60, position:"bottom", contentStyle:"compact", dockStyle:"floating", visibilityMode:"smart", windowGrouping:"grouped", showLauncher:true, showTrash:true})
        property var calls: []
        property var groupingCalls: []
        property var badgeCalls: []
        property var indicatorCalls: []
        property var revealCalls: []
        property bool deferSnapshot: false
        signal dockSnapshotChanged(var state)
        signal dockBuiltinVisibilityChanged(var state)
        signal dockNotificationBadgeVisibilityChanged(var state)
        signal dockRevealIndicatorVisibilityChanged(var state)
        function dockSnapshot() { if (!deferSnapshot) dockSnapshotChanged(snapshot) }
        function updateDockBuiltinVisibility(id, visible) { calls = calls.concat([{id, visible}]) }
        function updateDockNotificationBadgeVisibility(visible) { badgeCalls = badgeCalls.concat([visible]) }
        function updateDockRevealIndicatorVisibility(visible) { indicatorCalls = indicatorCalls.concat([visible]) }
        function updateDockWindowGrouping(mode) { groupingCalls = groupingCalls.concat([mode]) }
        function updateDockRevealTriggerMode(mode) { revealCalls = revealCalls.concat([mode]) }
    }
    TestCase {
        name: "SettingsBuiltins"
        when: windowShown
        function init() {
            bridge.snapshot = {baseHeight:60, position:"bottom", contentStyle:"compact",
                dockStyle:"floating", visibilityMode:"smart", windowGrouping:"grouped",
                showLauncher:true, showTrash:true}
            bridge.calls = []
            bridge.badgeCalls = []
            bridge.groupingCalls = []
            bridge.revealCalls = []
            bridge.deferSnapshot = false
            bridge.lastError = ""
        }

        function test_reveal_choice_roundtrip() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            try {
                const picker = findChild(app.contentItem, "dock-reveal-trigger-picker")
                verify(picker !== null)
                const scroll = findChild(app.contentItem, "settings-page-scroll")
                verify(waitForRendering(picker))
                scroll.contentY = picker.mapToItem(scroll.contentItem, 0, 0).y - 80
                verify(waitForRendering(picker))
                compare(picker.currentIndex, 0, "old snapshots retain whole-edge triggering")
                verify(!picker.disabled)
                mouseClick(picker, picker.width * 0.75, picker.height / 2)
                compare(bridge.revealCalls.length, 1)
                compare(bridge.revealCalls[0], "dockSpan")
                compare(picker.currentIndex, 0, "request does not replace confirmed state")
                bridge.lastError = "save failed"
                bridge.dockSnapshotChanged({})
                compare(picker.currentIndex, 0, "failed update preserves the last confirmed state")
                bridge.lastError = ""
                bridge.snapshot = Object.assign({}, bridge.snapshot, {revealTriggerMode:"dockSpan"})
                bridge.dockSnapshot()
                compare(picker.currentIndex, 1, "snapshot acknowledgement updates the picker")
                mouseClick(picker, picker.width * 0.25, picker.height / 2)
                compare(bridge.revealCalls.length, 2)
                compare(bridge.revealCalls[1], "fullEdge")
                compare(picker.currentIndex, 1)
                bridge.snapshot = Object.assign({}, bridge.snapshot, {revealTriggerMode:"fullEdge"})
                bridge.dockSnapshot()
                compare(picker.currentIndex, 0)
                bridge.snapshot = Object.assign({}, bridge.snapshot, {revealTriggerMode:"dockSpan", visibilityMode:"always"})
                bridge.dockSnapshot()
                compare(picker.currentIndex, 1, "always-visible mode preserves the saved choice")
                verify(picker.disabled)
                mouseClick(picker, picker.width * 0.25, picker.height / 2)
                compare(bridge.revealCalls.length, 2, "disabled and snapshot updates cannot write")
            } finally {
                app.destroy()
            }
        }

        function test_reveal_loading_guard() {
            bridge.deferSnapshot = true
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            try {
                const picker = findChild(app.contentItem, "dock-reveal-trigger-picker")
                verify(picker !== null)
                const scroll = findChild(app.contentItem, "settings-page-scroll")
                verify(waitForRendering(picker))
                scroll.contentY = picker.mapToItem(scroll.contentItem, 0, 0).y - 80
                verify(waitForRendering(picker))
                verify(picker.disabled, "unknown configuration cannot be edited")
                mouseClick(picker, picker.width * 0.75, picker.height / 2)
                compare(bridge.revealCalls.length, 0)
                bridge.dockSnapshotChanged({})
                verify(picker.disabled, "failed initial load must stay disabled")
                bridge.deferSnapshot = false
                bridge.snapshot = Object.assign({}, bridge.snapshot, {revealTriggerMode:"dockSpan"})
                bridge.dockSnapshot()
                verify(!picker.disabled)
                compare(picker.currentIndex, 1)
                compare(bridge.revealCalls.length, 0, "loading the value does not write it back")
            } finally {
                app.destroy()
            }
        }

        function test_grouping_binding() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            const control = findChild(app.contentItem, "window-grouping-switch")
            verify(control !== null)
            const scroll = findChild(app.contentItem, "settings-page-scroll")
            scroll.contentY = control.mapToItem(scroll.contentItem, 0, 0).y - 100
            verify(waitForRendering(control))
            mouseClick(control)
            compare(bridge.groupingCalls.length, 1)
            compare(bridge.groupingCalls[0], "separate")
            verify(control.checked, "only the snapshot confirms the switch")
            bridge.snapshot = Object.assign({}, bridge.snapshot, {windowGrouping:"separate"})
            bridge.dockSnapshot()
            verify(!control.checked, "asynchronous acknowledgement updates the switch")
            bridge.snapshot = Object.assign({}, bridge.snapshot, {windowGrouping:"grouped"})
            bridge.dockSnapshot()
            verify(control.checked, "external changes keep the binding")
            app.destroy()
        }
        function test_notification_badge_binding() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            const control = findChild(app.contentItem, "dock-notification-badges-switch")
            verify(control !== null)
            verify(control.checked, "older snapshots keep notification badges enabled")
            const scroll = findChild(app.contentItem, "settings-page-scroll")
            verify(waitForRendering(app.contentItem))
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                control.mapToItem(scroll.contentItem, 0, 0).y - 100))
            verify(waitForRendering(control))
            mouseClick(control)
            compare(bridge.badgeCalls.length, 1)
            compare(bridge.badgeCalls[0], false)
            verify(control.checked && !control.enabled, "wait for the confirmed snapshot")
            bridge.dockSnapshot()
            verify(!control.enabled, "an unrelated snapshot cannot acknowledge the request")
            bridge.snapshot = Object.assign({}, bridge.snapshot, {showNotificationBadges:false})
            bridge.dockNotificationBadgeVisibilityChanged(bridge.snapshot)
            verify(!control.checked && control.enabled)
            mouseClick(control)
            compare(bridge.badgeCalls.length, 2)
            compare(bridge.badgeCalls[1], true)
            bridge.lastError = "save failed"
            bridge.dockNotificationBadgeVisibilityChanged({})
            verify(!control.checked && control.enabled, "a failed update keeps the confirmed value")
            bridge.lastError = ""
            bridge.snapshot = Object.assign({}, bridge.snapshot, {showNotificationBadges:true})
            bridge.dockSnapshot()
            verify(control.checked, "external snapshots keep the switch binding")
            compare(bridge.badgeCalls.length, 2, "snapshot updates must not write back")
            app.destroy()
        }
        function test_reveal_indicator_binding() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            const control = findChild(app.contentItem, "dock-reveal-indicator-switch")
            verify(control !== null)
            verify(control.checked, "older snapshots keep the indicator enabled")
            const scroll = findChild(app.contentItem, "settings-page-scroll")
            verify(waitForRendering(app.contentItem))
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                control.mapToItem(scroll.contentItem, 0, 0).y - 100))
            verify(waitForRendering(control))
            mouseClick(control)
            compare(bridge.indicatorCalls.length, 1)
            compare(bridge.indicatorCalls[0], false)
            verify(control.checked && !control.enabled, "wait for the confirmed snapshot")
            bridge.dockSnapshot()
            verify(!control.enabled, "an unrelated snapshot cannot acknowledge the request")
            bridge.snapshot = Object.assign({}, bridge.snapshot, {showRevealIndicator:false})
            bridge.dockRevealIndicatorVisibilityChanged(bridge.snapshot)
            verify(!control.checked && control.enabled)
            mouseClick(control)
            compare(bridge.indicatorCalls.length, 2)
            compare(bridge.indicatorCalls[1], true)
            bridge.lastError = "save failed"
            bridge.dockRevealIndicatorVisibilityChanged({})
            verify(!control.checked && control.enabled, "a failed update keeps the confirmed value")
            bridge.lastError = ""
            bridge.snapshot = Object.assign({}, bridge.snapshot, {showRevealIndicator:true})
            bridge.dockSnapshot()
            verify(control.checked, "external snapshots keep the switch binding")
            compare(bridge.indicatorCalls.length, 2, "snapshot updates must not write back")
            app.destroy()
        }
        function test_selection() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            tryVerify(() => findChild(app.contentItem, "dock-launcher-checkbox") !== null)
            const launcher = findChild(app.contentItem, "dock-launcher-checkbox")
            const trash = findChild(app.contentItem, "dock-trash-checkbox")
            verify(launcher !== null); verify(trash !== null)
            verify(launcher.checked && trash.checked)
            verify(waitForRendering(launcher))
            mouseClick(launcher)
            compare(bridge.calls.length, 1)
            compare(bridge.calls[0].id, "launcher")
            compare(bridge.calls[0].visible, false)
            verify(!launcher.enabled && !trash.enabled)
            bridge.dockSnapshotChanged(bridge.snapshot)
            verify(!launcher.enabled && !trash.enabled,
                "an unrelated Dock snapshot must not finish the visibility update")
            bridge.snapshot = Object.assign({},bridge.snapshot,{showLauncher:false})
            bridge.dockBuiltinVisibilityChanged(bridge.snapshot)
            verify(!launcher.checked && trash.checked)
            verify(launcher.enabled && trash.enabled)
            mouseClick(trash)
            compare(bridge.calls.length, 2)
            compare(bridge.calls[1].id, "trash")
            bridge.lastError = "save failed"
            bridge.dockBuiltinVisibilityChanged({})
            verify(trash.checked, "failed update returns to confirmed state")
            verify(trash.enabled)
            // Other clients may change the same setting after an error.
            bridge.lastError = ""
            bridge.snapshot = Object.assign({}, bridge.snapshot, {showLauncher:true, showTrash:false})
            bridge.dockSnapshot()
            verify(launcher.checked && !trash.checked)
            compare(bridge.calls.length, 2, "snapshot changes must not send extra writes")
            app.destroy()
        }
    }
}
