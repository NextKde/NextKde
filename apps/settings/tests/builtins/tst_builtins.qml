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
        signal dockSnapshotChanged(var state)
        signal dockBuiltinVisibilityChanged(var state)
        function dockSnapshot() { dockSnapshotChanged(snapshot) }
        function updateDockBuiltinVisibility(id, visible) { calls = calls.concat([{id, visible}]) }
        function updateDockWindowGrouping(mode) { groupingCalls = groupingCalls.concat([mode]) }
    }
    TestCase {
        name: "SettingsBuiltins"
        when: windowShown
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
