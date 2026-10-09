import QtQuick
import QtTest
import "components"

Item {
    width: 900; height: 700
    ListModel { id: tasks }
    QtObject {
        id: controller
        property var taskModel: tasks
        property string lastAction: ""
        function pause(id) { lastAction = "pause:" + id }
        function resume(id) { lastAction = "resume:" + id }
        function cancel(id) { lastAction = "cancel:" + id }
        function locate(id) { lastAction = "locate:" + id }
        function deleteFile(id) { lastAction = "delete:" + id }
        function pauseAll() { lastAction = "pauseAll" }
        function clearRecords() { tasks.clear() }
    }
    Item {
        id: overlay
        anchors.fill: parent
        property bool opened: false
        visible: opened || panel.x < width
        DownloadPanel {
            id: panel
            width: 450; height: 620; y: 40
            x: overlay.opened ? overlay.width - width : overlay.width
            controller: controller
            onCloseRequested: overlay.opened = false
            Behavior on x { NumberAnimation { duration: 160 } }
        }
    }
    TestCase {
        name: "DownloadPanel"
        when: windowShown
        function list() { return findChild(panel, "downloadTaskList") }
        function fill(count) {
            for (let i = 0; i < count; ++i)
                tasks.append({ taskId: "task-" + i, title: "Download " + i,
                    artist: "Artist", artwork: "", taskState: "downloading",
                    received: 0, total: 104857600, errorMessage: "" })
        }
        function open() {
            overlay.opened = true
            tryCompare(panel, "x", 450)
            tryCompare(list(), "count", tasks.count)
            waitForPolish(list())
            tryVerify(function() { return list().itemAtIndex(0) !== null })
        }
        function init() {
            overlay.opened = false
            tryCompare(overlay, "visible", false)
            tasks.clear(); panel.savedContentY = 0; panel.deletingId = ""
            controller.lastAction = ""
        }
        function cleanup() {
            overlay.opened = false
            tryCompare(overlay, "visible", false)
            tryCompare(list(), "count", 0)
        }
        function test_progressKeepsRowsAndScroll() {
            fill(1200); open()
            const first = list().itemAtIndex(0)
            tasks.setProperty(0, "received", 1048576)
            tryCompare(first, "received", 1048576)
            compare(list().itemAtIndex(0), first)
            verify(findChild(first, "downloadTaskStatus").text.indexOf("1.0 MB") >= 0)
            list().positionViewAtIndex(500, ListView.Beginning)
            waitForPolish(list())
            const y = list().contentY
            tasks.setProperty(0, "received", 2097152)
            wait(20)
            fuzzyCompare(list().contentY, y, 1)
            list().positionViewAtEnd(); waitForPolish(list())
            tryVerify(function() { return list().itemAtIndex(1199) !== null })
            compare(list().itemAtIndex(1199).taskId, "task-1199")
        }
        function test_closeReleasesAndReopenRestores() {
            fill(1200); open()
            list().positionViewAtIndex(500, ListView.Beginning); waitForPolish(list())
            const y = list().contentY - list().originY
            overlay.opened = false
            wait(30)
            verify(overlay.visible); compare(list().count, 1200)
            tryCompare(overlay, "visible", false)
            tryCompare(list(), "count", 0)
            compare(tasks.count, 1200)
            tasks.setProperty(500, "received", 8388608)
            overlay.opened = true
            tryCompare(panel, "x", 450); waitForPolish(list())
            tryVerify(function() { return Math.abs(list().contentY - list().originY - y) < 1 })
            tryVerify(function() { return list().itemAtIndex(500) !== null })
            compare(list().itemAtIndex(500).received, 8388608)
        }
        function test_quickReopenKeepsDelegates() {
            fill(20); open()
            const first = list().itemAtIndex(0)
            overlay.opened = false; wait(30); overlay.opened = true
            tryCompare(panel, "x", 450)
            compare(list().itemAtIndex(0), first)
            for (let i = 0; i < 6; ++i) {
                overlay.opened = false; tryCompare(overlay, "visible", false)
                open(); compare(list().itemAtIndex(0).taskId, "task-0")
            }
        }
        function test_actionsFollowCurrentTask() {
            fill(2); open()
            const row = list().itemAtIndex(0)
            const action = findChild(row, "downloadTaskAction")
            const remove = findChild(row, "downloadTaskRemove")
            mouseClick(action); compare(controller.lastAction, "pause:task-0")
            tasks.setProperty(0, "taskState", "paused")
            mouseClick(action); compare(controller.lastAction, "resume:task-0")
            mouseClick(remove); compare(controller.lastAction, "cancel:task-0")
            tasks.setProperty(0, "taskState", "completed")
            mouseClick(action); compare(controller.lastAction, "locate:task-0")
            mouseClick(remove); compare(panel.deletingId, "task-0")
            compare(controller.lastAction, "locate:task-0")
            panel.deletingId = ""; wait(220)
            tasks.setProperty(0, "taskState", "finalizing")
            verify(!action.enabled); verify(!remove.enabled)
        }
        function test_clearWhileHiddenClampsSavedScroll() {
            fill(100); open()
            list().positionViewAtEnd(); waitForPolish(list())
            overlay.opened = false; tryCompare(overlay, "visible", false)
            tasks.clear(); fill(2); open()
            fuzzyCompare(list().contentY, list().originY, 1)
            tryCompare(list().itemAtIndex(0), "taskId", "task-0")
        }
    }
}
