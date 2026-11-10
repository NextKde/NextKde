import QtQuick
import QtTest
import Kos.Test.NotificationOpen 1.0

TestCase {
    id: test
    name: "NotificationOpen"
    property var controller: null
    property var results: []
    property int defaults: 0

    QtObject {
        id: windows
        property var records: []
        property int revision: 0
        property string activeWindowId: ""
        property var requests: []
        property bool accept: true
        signal commandFinished(string action, string ticket, bool found)
        function windowById(id) { return records.find(record => record.windowId === id) || null }
        function activateWindow(id, options) {
            requests = requests.concat([{ id, options }])
            return accept
        }
        function publish(records) {
            windows.records = records
            ++revision
        }
    }
    QtObject {
        id: launchBackend
        property int requests: 0
        property var callback: null
        property var isCurrent: null
        property bool accept: true
        function launchApp(id, callback, isCurrent) {
            ++requests
            launchBackend.callback = callback
            launchBackend.isCurrent = isCurrent
            return accept
        }
    }
    Component {
        id: factory
        NotificationOpenController {
            windowService: windows
            launcher: launchBackend
            lookupEntry: function(id) { return id === "installed" ? { id: "installed.desktop" } : null }
            activationTimeout: 120
            launchTimeout: 120
            onFinished: function(source, success) { test.results = test.results.concat([{ source, success }]) }
        }
    }
    function record(active, minimized) {
        return { windowId: "one", identity: { desktopId: "installed.desktop", name: "App" },
            toplevel: { activated: active === true, minimized: minimized === true } }
    }
    function notice(withDefault) {
        return { desktopEntry: "installed", appName: "App", resident: false,
            actions: withDefault ? [{ identifier: "default", invoke: function() { ++test.defaults } }] : [] }
    }
    function init() {
        results = []
        defaults = 0
        windows.records = []
        windows.requests = []
        windows.activeWindowId = ""
        windows.accept = true
        launchBackend.requests = 0
        launchBackend.callback = null
        launchBackend.isCurrent = null
        launchBackend.accept = true
        controller = createTemporaryObject(factory, test)
        verify(controller !== null)
        controller.notification = notice(false)
    }
    function cleanup() { controller.cancel() }

    function test_activate_requires_actual_focus() {
        windows.publish([record(false, true)])
        controller.open()
        verify(controller.busy)
        compare(windows.requests.length, 1)
        verify(windows.requests[0].options.forceAnim)
        controller.open()
        compare(windows.requests.length, 1, "repeated clicks must not duplicate requests")
        const ticket = windows.requests[0].options.ticket
        windows.commandFinished("activate", ticket, true)
        windows.activeWindowId = "one"
        compare(results.length, 0, "receipt and optimistic active id are not actual focus")
        windows.publish([record(true, true)])
        compare(results.length, 0, "a minimized window is not a completed handoff")
        windows.publish([record(true, false)])
        compare(results.length, 1)
        verify(results[0].success)
        verify(!controller.busy)
    }
    function test_already_active_does_not_toggle() {
        windows.publish([record(true, false)])
        controller.open()
        compare(windows.requests.length, 0)
        verify(results[0].success)
    }
    function test_activation_rejected_falls_back_once() {
        controller.notification = notice(true)
        windows.publish([record(false, false)])
        controller.open()
        const ticket = windows.requests[0].options.ticket
        windows.commandFinished("activate", "unrelated-ticket", false)
        compare(defaults, 0)
        windows.commandFinished("activate", ticket, false)
        windows.commandFinished("activate", ticket, false)
        compare(defaults, 1)
        verify(results[0].success)
    }
    function test_immediate_activation_failure_retains_notice() {
        windows.publish([record(false, false)])
        windows.accept = false
        controller.open()
        compare(results.length, 1)
        verify(!results[0].success)
    }
    function test_closed_target_retains_notice() {
        windows.publish([record(false, false)])
        controller.open()
        windows.publish([])
        verify(!results[0].success)
        compare(launchBackend.requests, 0)
    }
    function test_timeout_does_not_dispatch_second_action() {
        controller.notification = notice(true)
        windows.publish([record(false, false)])
        controller.open()
        tryCompare(controller, "busy", false, 1000)
        verify(!results[0].success)
        compare(defaults, 0)
        windows.publish([record(true, false)])
        compare(results.length, 1, "late focus must not dismiss the notice")
    }
    function test_launch_acceptance_waits_for_focused_window() {
        controller.open()
        compare(launchBackend.requests, 1)
        launchBackend.callback(true)
        compare(results.length, 0)
        windows.publish([record(false, false)])
        compare(windows.requests.length, 1)
        verify(!windows.requests[0].options.forceAnim)
        windows.publish([record(true, false)])
        verify(results[0].success)
    }
    function test_launch_failure_falls_back() {
        controller.notification = notice(true)
        controller.open()
        launchBackend.callback(false)
        compare(defaults, 1)
        verify(results[0].success)
        launchBackend.callback(false)
        compare(results.length, 1)
    }
    function test_launch_timeout_retains_notice_and_cancels_preparation() {
        controller.notification = notice(true)
        controller.open()
        verify(launchBackend.isCurrent())
        tryCompare(controller, "busy", false, 1000)
        verify(!launchBackend.isCurrent())
        verify(!results[0].success)
        compare(defaults, 0)
        launchBackend.callback(false)
        compare(defaults, 0)
    }
    function test_replacement_invalidates_old_callback() {
        controller.open()
        const callback = launchBackend.callback
        const isCurrent = launchBackend.isCurrent
        controller.notification = notice(true)
        verify(!controller.busy)
        verify(!isCurrent())
        callback(false)
        compare(results.length, 0)
        compare(defaults, 0)
    }
    function test_cancel_invalidates_old_window_receipt() {
        windows.publish([record(false, false)])
        controller.open()
        const ticket = windows.requests[0].options.ticket
        controller.cancel()
        windows.commandFinished("activate", ticket, false)
        windows.publish([record(true, false)])
        compare(results.length, 0)
    }
    function test_destroyed_delegate_invalidates_launch_callback() {
        const removed = createTemporaryObject(factory, test)
        removed.notification = notice(true)
        removed.open()
        const callback = launchBackend.callback
        const isCurrent = launchBackend.isCurrent
        removed.destroy()
        wait(0)
        verify(!isCurrent())
        callback(false)
        compare(results.length, 0)
        compare(defaults, 0)
    }
    function test_uninstalled_desktop_entry_uses_default() {
        const source = notice(true)
        source.desktopEntry = "not-installed"
        controller.notification = source
        controller.open()
        compare(launchBackend.requests, 0)
        compare(defaults, 1)
        verify(results[0].success)
    }
    function test_throwing_default_retains_notice() {
        controller.notification = { actions: [{ identifier: "default", invoke: function() { throw new Error("gone") } }] }
        controller.open()
        verify(!results[0].success)
    }
    function test_default_replacement_keeps_original_source() {
        const replacement = notice(false)
        const source = { actions: [{ identifier: "default", invoke: function() { controller.notification = replacement } }] }
        controller.notification = source
        controller.open()
        compare(results[0].source, source)
        compare(controller.notification, replacement)
    }
    function test_resident_source_is_preserved_for_card_policy() {
        const source = notice(false)
        source.resident = true
        controller.notification = source
        windows.publish([record(true, false)])
        controller.open()
        compare(results[0].source, source)
        verify(results[0].source.resident)
    }
}
