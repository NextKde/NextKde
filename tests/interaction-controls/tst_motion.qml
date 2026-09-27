import QtQuick
import QtQuick.Controls
import QtTest
import "../../shared/qml/foundation" as Foundation

Item {
    id: root
    width: 500
    height: 300

    Foundation.KosDialog {
        id: dialog
        parent: root
        width: 200
        height: 100
        modal: true
    }
    Foundation.KosPageCache {
        id: pages
        anchors.fill: parent
        cacheLimit: 1
        asynchronous: false
        pages: [firstPage, secondPage]
    }
    Component { id: firstPage; Rectangle { color: "red" } }
    Component { id: secondPage; Rectangle { color: "blue" } }

    TestCase {
        name: "SharedMotion"
        when: windowShown

        function init() {
            Foundation.AppTheme.reduceMotion = false
            dialog.close()
            pages.currentIndex = 0
            wait(300)
        }

        function test_dialog_reversal() {
            dialog.open()
            wait(70)
            verify(dialog.visible && dialog.revealProgress > 0 && dialog.revealProgress < 1)
            const progress = dialog.revealProgress
            dialog.close()
            compare(dialog.revealProgress, progress)
            verify(!dialog.enabled, "closing dialogs reject repeated actions")
            dialog.open()
            compare(dialog.revealProgress, progress)
            tryCompare(dialog, "revealProgress", 1)
            dialog.close()
            wait(40)
            verify(dialog.visible && dialog.revealProgress > 0 && dialog.revealProgress < 1)
            tryCompare(dialog, "visible", false)
        }

        function test_page_exit_retains_loader() {
            verify(pages.pageAt(0) !== null)
            pages.currentIndex = 1
            verify(pages.pageAt(0) !== null, "eviction waits for outgoing page animation")
            wait(60)
            verify(pages.pageAt(0) !== null)
            pages.currentIndex = 0
            wait(300)
            verify(pages.pageAt(0) !== null)
            compare(pages.pageAt(1), null)
            pages.currentIndex = 1
            wait(300)
            compare(pages.pageAt(0), null)
            verify(pages.pageAt(1) !== null)
        }

        function test_reduce_motion() {
            Foundation.AppTheme.reduceMotion = true
            dialog.open()
            tryCompare(dialog, "revealProgress", 1, 100)
            compare(dialog.scale, 1)
            dialog.close()
            tryCompare(dialog, "visible", false, 100)
        }

        function test_settings_navigation() {
            const component = Qt.createComponent("../../apps/settings/main.qml")
            compare(component.status, Component.Ready, component.errorString())
            const settings = component.createObject(null, {currentPage: 3})
            verify(settings !== null)
            compare(settings.displayedPage, 3)
            settings.currentPage = 4
            compare(settings.displayedPage, 3)
            wait(60)
            compare(settings.displayedPage, 3)
            settings.currentPage = 5
            tryCompare(settings, "displayedPage", 5)
            wait(250)
            settings.currentPage = 3
            compare(settings.displayedPage, 5)
            tryCompare(settings, "displayedPage", 3)
            settings.destroy()
        }
    }
}
