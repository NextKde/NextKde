import QtQuick
import QtTest
Item {
    property var appStore: closeStore
    QtObject {
        id: closeStore
        property bool anyBusy: false
        property bool hasActiveMutation: false
        signal taskFinished(string name, string code)
    }
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
        property var autoHideCalls: []
        signal dockAutoHideAppChanged(var state)
        function applicationIcon(appId) { return "" }
        function updateDockAutoHideApp(appId, enabled) { autoHideCalls = autoHideCalls.concat([{appId, enabled}]) }
        property bool deferSnapshot: false
        signal dockSnapshotChanged(var state)
        signal dockBuiltinVisibilityChanged(var state)
        signal notificationSnapshotChanged(var state)
        signal dockRevealIndicatorVisibilityChanged(var state)
        function dockSnapshot() { if (!deferSnapshot) dockSnapshotChanged(snapshot) }
        function updateDockBuiltinVisibility(id, visible) { calls = calls.concat([{id, visible}]) }
        function notificationSnapshot() { notificationSnapshotChanged(Object.assign({}, snapshot,
            {ready:true, sources:[], blockedKeys:[], showNotificationBadges:snapshot.showNotificationBadges !== false})) }
        function setNotificationPreference(key, value) { if (key === "showNotificationBadges") badgeCalls = badgeCalls.concat([value]) }
        function setNotificationBlocked(key, value) {}
        function updateDockRevealIndicatorVisibility(visible) { indicatorCalls = indicatorCalls.concat([visible]) }
        function updateDockWindowGrouping(mode) { groupingCalls = groupingCalls.concat([mode]) }
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
            bridge.autoHideCalls = []
            bridge.indicatorCalls = []
            bridge.deferSnapshot = false
            bridge.lastError = ""
        }

        function test_real_window_close_policy() {
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage: 3})
            verify(app !== null)
            try {
                closeStore.anyBusy = true
                closeStore.hasActiveMutation = true
                app.close()
                tryCompare(app, "visible", false)
                compare(closeStore.hasActiveMutation, true)
                compare(app.currentPage, 3)
                app.show()
                tryCompare(app, "visible", true)
                compare(closeStore.hasActiveMutation, true)
                closeStore.hasActiveMutation = false
                app.close()
                tryCompare(app, "visible", false)
            } finally {
                closeStore.anyBusy = false
                closeStore.hasActiveMutation = false
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
            const app = component.createObject(null, {currentPage:12})
            verify(app !== null)
            const control = findChild(app.contentItem, "notification-showNotificationBadges-switch")
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
            bridge.notificationSnapshot()
            verify(!control.checked && control.enabled)
            mouseClick(control)
            compare(bridge.badgeCalls.length, 2)
            compare(bridge.badgeCalls[1], true)
            bridge.lastError = "save failed"
            bridge.notificationSnapshotChanged({})
            verify(!control.checked && control.enabled, "a failed update keeps the confirmed value")
            bridge.lastError = ""
            bridge.snapshot = Object.assign({}, bridge.snapshot, {showNotificationBadges:true})
            bridge.notificationSnapshot()
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
        function test_app_auto_hide_list() {
            bridge.deferSnapshot = true
            const component = Qt.createComponent("../../main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const app = component.createObject(null, {currentPage:3})
            verify(app !== null)
            try {
                const input = findChild(app.contentItem, "dockAutoHideAppInput")
                const add = findChild(app.contentItem, "addManualDockAutoHideApp")
                const picker = findChild(app.contentItem, "dockAutoHideRunningApps")
                const addRunning = findChild(app.contentItem, "addRunningDockAutoHideApp")
                verify(input !== null && add !== null && picker !== null && addRunning !== null)
                input.text = "org.example.Editor"
                verify(!add.enabled, "no writes before initial snapshot")
                bridge.snapshot = Object.assign({}, bridge.snapshot, {autoHideApps: [], runningApps: [
                    {appId:"org.example.Editor.desktop", name:"Editor"},
                    {appId:"org.example.Player.desktop", name:"Player"}]})
                bridge.dockSnapshotChanged(bridge.snapshot)
                verify(add.enabled)
                add.clicked()
                compare(bridge.autoHideCalls.length, 1)
                compare(bridge.autoHideCalls[0].appId, "org.example.Editor")
                compare(bridge.autoHideCalls[0].enabled, true)
                verify(!add.enabled && !addRunning.enabled)
                bridge.dockSnapshotChanged(bridge.snapshot)
                verify(!add.enabled, "unrelated snapshots cannot acknowledge an app edit")
                bridge.lastError = "save failed"
                bridge.dockAutoHideAppChanged({})
                verify(add.enabled)
                compare(input.text, "org.example.Editor", "failed writes preserve manual input")
                bridge.lastError = ""
                add.clicked()
                bridge.snapshot = Object.assign({}, bridge.snapshot, {autoHideApps:["org.example.Editor.desktop"]})
                bridge.dockAutoHideAppChanged(bridge.snapshot)
                compare(input.text, "")
                compare(picker.model.length, 1, "already configured apps leave the picker")
                compare(picker.model[0].appId, "org.example.Player.desktop")
                tryVerify(() => findChild(app.contentItem, "removeDockAutoHideApp_org.example.Editor.desktop") !== null)
                const remove = findChild(app.contentItem, "removeDockAutoHideApp_org.example.Editor.desktop")
                remove.clicked()
                compare(bridge.autoHideCalls[2].enabled, false)
                verify(!remove.enabled)
                bridge.snapshot = Object.assign({}, bridge.snapshot, {autoHideApps:[]})
                bridge.dockAutoHideAppChanged(bridge.snapshot)
                compare(picker.model.length, 2)
                addRunning.clicked()
                compare(bridge.autoHideCalls[3].appId, "org.example.Editor.desktop")
                compare(bridge.autoHideCalls[3].enabled, true)
                bridge.dockAutoHideAppChanged(bridge.snapshot)
                compare(bridge.autoHideCalls.length, 4, "readbacks never send extra writes")
            } finally {
                app.destroy()
            }
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
