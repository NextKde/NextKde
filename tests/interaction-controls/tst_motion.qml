import QtQuick
import QtQuick.Controls
import QtTest
import "../../shared/qml/foundation" as Foundation
import Kos.Test.LauncherMotion 1.0 as Launcher

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

    Component {
        id: launcherControllerFixture
        Item {
            id: fixture
            width: 200; height: 200
            property alias controller: controller
            Item { id: motionTarget; anchors.fill: parent }
            Launcher.LauncherMotion { id: controller; target: motionTarget }
        }
    }
    Component {
        id: launcherTileFixture
        Item {
            id: fixture
            required property var controller
            property bool animateOnCompleted: true
            property alias visual: visual
            property alias motion: tileMotion
            width: 80; height: 80
            Item {
                id: visual
                width: 80; height: 80
                Rectangle { anchors.fill: parent; color: "blue" }
            }
            Launcher.LauncherIconMotion {
                id: tileMotion
                target: visual
                controller: fixture.controller
                opened: fixture.controller.requestedOpen
                animateOnCompleted: fixture.animateOnCompleted
                offsetX: 32
                offsetY: 24
            }
        }
    }

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

        function launcherTile(controller, properties) {
            return createTemporaryObject(launcherTileFixture, root,
                Object.assign({controller: controller}, properties || {}))
        }

        function tilePose(tile) {
            return [tile.visual.x, tile.visual.y, tile.visual.scale, tile.visual.opacity]
        }

        function test_launcher_entrance_and_reversal() {
            const host = createTemporaryObject(launcherControllerFixture, root)
            const controller = host.controller
            const tile = launcherTile(controller)
            compare(tilePose(tile), [-32, -24, 0.8, 0])
            controller.open()
            // Starting the animation must not expose the fully opaque prewarm
            // pose, even before the first scene-graph frame is synchronized.
            compare(tilePose(tile), [-32, -24, 0.8, 0])
            compare(controller.pendingIcons, 1)
            verify(!controller.interactive)
            wait(60)
            verify(tile.visual.opacity > 0 && tile.visual.opacity < 1)
            verify(tile.visual.scale > 0.8 && tile.visual.scale < 1)
            let pose = tilePose(tile)
            controller.close()
            compare(tilePose(tile), pose, "closing preserves the current pose")
            wait(30)
            pose = tilePose(tile)
            controller.open()
            compare(tilePose(tile), pose, "reopening preserves the current pose")
            let previousOpacity = tile.visual.opacity
            let previousScale = tile.visual.scale
            for (let frame = 0; frame < 8; ++frame) {
                wait(16)
                verify(tile.visual.opacity >= previousOpacity, "fade must not flash backwards")
                verify(tile.visual.scale >= previousScale, "spread must not jump backwards")
                previousOpacity = tile.visual.opacity
                previousScale = tile.visual.scale
            }
            tryCompare(controller, "settledOpen", true)
            compare(tilePose(tile), [0, 0, 1, 1])
            compare(controller.pendingIcons, 0)
            controller.close()
            tryCompare(controller, "mapped", false)
            compare(tilePose(tile), [-32, -24, 0.8, 0])
        }

        function test_launcher_cold_and_late_delegates() {
            const host = createTemporaryObject(launcherControllerFixture, root)
            const controller = host.controller
            controller.open()
            const cold = launcherTile(controller)
            compare(tilePose(cold), [-32, -24, 0.8, 0])
            compare(controller.pendingIcons, 1)
            // GridView assigns cell geometry after delegate construction.
            cold.motion.offsetX = -20
            cold.motion.offsetY = -12
            compare(tilePose(cold), [20, 12, 0.8, 0])
            tryCompare(controller, "settledOpen", true)
            compare(tilePose(cold), [0, 0, 1, 1])
            const late = launcherTile(controller, {animateOnCompleted: false})
            compare(tilePose(late), [0, 0, 1, 1])
            compare(controller.pendingIcons, 0)
        }

        function test_launcher_hidden_page_and_destroyed_delegate() {
            const host = createTemporaryObject(launcherControllerFixture, root)
            const controller = host.controller
            const hidden = launcherTile(controller, {visible: false})
            controller.open()
            compare(controller.pendingIcons, 0)
            compare(tilePose(hidden), [0, 0, 1, 1])
            const tile = launcherTile(controller)
            compare(controller.pendingIcons, 1)
            tile.visible = false
            compare(controller.pendingIcons, 0)
            compare(tilePose(tile), [0, 0, 1, 1])
            tryCompare(controller, "settledOpen", true)
            tile.visible = true
            controller.close()
            compare(controller.pendingIcons, 1)
            tile.destroy()
            wait(0)
            compare(controller.pendingIcons, 0)
            tryCompare(controller, "mapped", false)
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
