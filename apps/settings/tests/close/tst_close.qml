import QtQuick
import QtQuick.Controls
import QtTest
import "../../components" as SettingsControls

TestCase {
    name: "SettingsClosePolicy"
    when: windowShown
    QtObject {
        id: backend
        property bool anyBusy: false
        property bool hasActiveMutation: false
        property int cancellations: 0
        property bool immediate: false
        function cancelActiveMutations() {
            cancellations++
            if (immediate) hasActiveMutation = false
        }
    }
    Component {
        id: factory
        ApplicationWindow {
            visible: true
            width: 600; height: 400
            property int currentPage: 3
            SettingsControls.AppOperationCloseDialog {
                parent: Overlay.overlay
                targetWindow: parentWindow
                store: backend
            }
            id: parentWindow
        }
    }
    function init() {
        backend.anyBusy = false
        backend.hasActiveMutation = false
        backend.cancellations = 0
        backend.immediate = false
    }
    function makeWindow() {
        const window = createTemporaryObject(factory, this)
        verify(window)
        tryCompare(window, "visible", true)
        return window
    }
    function test_query_does_not_block_close() {
        backend.anyBusy = true
        const window = makeWindow()
        window.close()
        tryCompare(window, "visible", false)
        compare(backend.cancellations, 0)
    }
    function test_mutation_explains_without_changing_page() {
        backend.hasActiveMutation = true
        const window = makeWindow()
        const dialog = findChild(window, "appOperationCloseDialog")
        window.close()
        tryCompare(dialog, "visible", true)
        compare(window.visible, true)
        compare(window.currentPage, 3)
        tryCompare(dialog, "opened", true)
        mouseClick(findChild(dialog, "keepSettingsOpen"))
        tryCompare(dialog, "visible", false)
        compare(window.visible, true)
        compare(backend.cancellations, 0)
    }
    function test_cancel_waits_for_backend_and_closes_once_safe() {
        backend.hasActiveMutation = true
        const window = makeWindow()
        const dialog = findChild(window, "appOperationCloseDialog")
        window.close()
        tryCompare(dialog, "opened", true)
        mouseClick(findChild(dialog, "cancelTaskAndClose"))
        compare(backend.cancellations, 1)
        compare(window.visible, true)
        compare(dialog.waitingForCancellation, true)
        window.close()
        compare(window.visible, true)
        backend.hasActiveMutation = false
        tryCompare(window, "visible", false)
    }
    function test_task_finishing_does_not_close_without_consent() {
        backend.hasActiveMutation = true
        const window = makeWindow()
        const dialog = findChild(window, "appOperationCloseDialog")
        window.close()
        backend.hasActiveMutation = false
        tryCompare(dialog, "visible", false)
        compare(window.visible, true)
    }
    function test_synchronous_cancellation() {
        backend.hasActiveMutation = true
        backend.immediate = true
        const window = makeWindow()
        window.close()
        findChild(window, "appOperationCloseDialog").cancelAndClose()
        tryCompare(window, "visible", false)
    }
    function test_keep_open_while_cancellation_finishes() {
        backend.hasActiveMutation = true
        const window = makeWindow()
        const dialog = findChild(window, "appOperationCloseDialog")
        window.close()
        dialog.cancelAndClose()
        dialog.keepOpen()
        backend.hasActiveMutation = false
        compare(window.visible, true)
    }
}
