// Run with node run.mjs, which stages the module inside an isolated config.
// This isolated fixture loads no desktop services and opens no windows.
import QtQuick
import Quickshell
import Quickshell.Io
import "WindowRecordIndex.mjs" as WindowRecordIndex

QtObject {
    id: root
    property int stage: 0
    property string fixturePath: Qt.resolvedUrl("WindowRecordIndex.mjs").toString().replace(/^file:\/\//, "")
    property QtObject firstTop: QtObject {}
    property QtObject secondTop: QtObject {}
    property FileView reader: FileView {
        preload: true
        watchChanges: false
        printErrors: false
        onLoaded: {
            if (!text().includes("indexWindowRecords")) {
                console.error("STATIC_WORK_FAIL: fixture read")
                Qt.quit()
                return
            }
            if (root.stage === 0 || root.stage === 1) {
                root.stage++
                nextStep.start()
            } else if (root.stage === 3) {
                console.log("STATIC_WORK_PASS: QObject identity, reload, failed read and recovery")
                Qt.quit()
            }
        }
        onLoadFailed: {
            if (root.stage !== 2) {
                console.error("STATIC_WORK_FAIL: unexpected read failure")
                Qt.quit()
                return
            }
            root.stage = 3
            nextStep.start()
        }
    }
    property Timer nextStep: Timer {
        interval: 1
        onTriggered: {
            if (root.stage === 1)
                root.reader.reload()
            else if (root.stage === 2)
                root.reader.path = root.fixturePath + ".nonexistent-test-file"
            else
                root.reader.path = root.fixturePath
        }
    }
    property Timer deadline: Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.error("STATIC_WORK_FAIL: timeout")
            Qt.quit()
        }
    }
    Component.onCompleted: {
        const first = { provider: "foreign", toplevel: firstTop }
        const second = { provider: "foreign", toplevel: secondTop }
        const index = WindowRecordIndex.indexWindowRecords([first, second])
        if (index.foreign.get(firstTop) !== first || index.foreign.get(secondTop) !== second) {
            console.error("STATIC_WORK_FAIL: QObject identity")
            Qt.quit()
            return
        }
        reader.path = fixturePath
    }
}
