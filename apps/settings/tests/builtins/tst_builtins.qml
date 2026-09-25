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
        signal dockSnapshotChanged(var state)
        function dockSnapshot() { dockSnapshotChanged(snapshot) }
        function updateDockBuiltinVisibility(id, visible) { calls = calls.concat([{id, visible}]) }
    }
    TestCase {
        name: "SettingsBuiltins"
        when: windowShown
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
            bridge.snapshot = Object.assign({},bridge.snapshot,{showLauncher:false})
            bridge.dockSnapshot()
            verify(!launcher.checked && trash.checked)
            verify(launcher.enabled && trash.enabled)
            mouseClick(trash)
            compare(bridge.calls.length, 2)
            compare(bridge.calls[1].id, "trash")
            bridge.lastError = "save failed"
            bridge.dockSnapshotChanged({})
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
