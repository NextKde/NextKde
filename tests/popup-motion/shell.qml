import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.bar
import qs.desktop.modules.dock
import qs.desktop.modules.applauncher

ShellRoot {
    id: test
    property int stage: 0
    property real savedProgress: 0
    property int stableGlassChecks: 0

    FloatingWindow {
        id: host
        visible: true
        width: 500
        height: 700
        Item { id: anchorItem; x: 150; y: 20; width: 40; height: 30 }
        Item {
            id: geometryParent
            x: 30; y: 45
            width: 200; height: 200
            Item { id: geometryItem; x: 15; y: 20; width: 100; height: 60 }
            transform: Translate { id: geometryTranslation; x: 0; y: 0 }
        }
        ControlCenterCard {
            id: contentProbe
            x: 300; y: 100
            contentOpacity: 0.25
            contentOffsetY: 6
            cardScale: 0.9
            Item { id: probeChild; width: 10; height: 10 }
        }
    }
    RoundedBlurRegion { id: region; item: geometryItem; radius: 10 }
    ControlCenterPanel { id: center; anchorItem: anchorItem }
    AnimatedPopupWindow {
        id: popup
        anchor.item: anchorItem
        implicitWidth: 100; implicitHeight: 70
        Rectangle { anchors.fill: parent; color: "gray" }
    }
    ContextMenu { id: menu; anchorItem: anchorItem }
    DockInfoPopup { id: info; anchorItem: anchorItem; page: 2 }
    AppLauncherWindow { id: launcher; outputAvailable: false }

    Connections {
        target: center
        function onPageProgressChanged() { Qt.callLater(test.checkPersistentGlass) }
    }

    function checkPersistentGlass() {
        if (!center.isOpen || center.revealProgress !== 1 || center.pageProgress === 1
                || center.displayedSubmenu === "confirm")
            return
        try {
            const cards = center.contentItem.children.filter(child =>
                child.isControlCenterCard && child.visible)
            check(cards.length > 0, "a page transition always retains a glass surface")
            check(center.BackgroundEffect.blurRegion !== null,
                "a page transition never clears the window blur region")
            for (const card of cards) {
                check(card.opacity === 1 && card.scale === 1,
                    "page animation must not fade or shrink the native glass")
                check(card.contentOpacity === center.pageProgress,
                    "only the card content fades during navigation")
            }
            stableGlassChecks++
        } catch (error) {
            console.error("POPUP_MOTION_FAIL " + error)
            Qt.quit()
        }
    }

    function check(condition, message) {
        if (!condition)
            throw new Error(message)
    }

    function checkGeometry() {
        const expected = geometryItem.mapToItem(null,
            Qt.rect(0, 0, geometryItem.width, geometryItem.height))
        check(Math.abs(region.itemRect.x - expected.x) < 0.01
            && Math.abs(region.itemRect.y - expected.y) < 0.01
            && Math.abs(region.itemRect.width - expected.width) < 0.01,
            "blur mask follows the complete transformed scene rectangle")
    }

    Timer {
        id: steps
        running: true
        repeat: true
        interval: 400
        onTriggered: {
            try {
                console.log("POPUP_MOTION_STAGE " + test.stage)
                switch (test.stage++) {
                case 0:
                    checkGeometry()
                    check(probeChild.parent !== contentProbe
                        && probeChild.parent.opacity === 0.25
                        && probeChild.parent.scale === 0.9,
                        "declared card children use the animated content host, not the glass")
                    geometryParent.scale = 0.8
                    geometryParent.x = 60
                    geometryTranslation.y = 13
                    center.toggle(anchorItem)
                    popup.show()
                    info.show()
                    interval = 60
                    break
                case 1:
                    checkGeometry()
                    check(center.visible && center.revealProgress > 0
                        && center.revealProgress < 1, "control center animates its entrance")
                    savedProgress = center.revealProgress
                    center.close()
                    check(!center.isOpen && center.visible && !center.contentItem.enabled,
                        "closing immediately releases input but retains the surface")
                    check(center.revealProgress === savedProgress, "close never snaps progress")
                    center.toggle(anchorItem)
                    check(center.isOpen && center.revealProgress === savedProgress,
                        "reopening reverses from current progress")
                    popup.hide()
                    check(popup.visible && !popup.interactive, "common popup releases input on exit")
                    popup.show()
                    interval = 300
                    break
                case 2:
                    check(info.visible && info.BackgroundEffect.blurRegion !== null,
                        "clock details publish a real window blur region")
                    check(info.BackgroundEffect.blurRegion.item.width === info.width,
                        "clock blur covers the detail panel")
                    info.page = 1
                    check(center.revealProgress === 1 && popup.revealProgress === 1,
                        "old exit callbacks cannot close reopened surfaces")
                    center.openSubmenu("wifi")
                    check(center.activeSubmenu === "wifi" && center.displayedSubmenu === "",
                        "requested and displayed pages are separate")
                    center.closeSubmenu()
                    check(center.activeSubmenu === "", "back clears logical state synchronously")
                    center.openSubmenu("wifi")
                    interval = 60
                    break
                case 3:
                    check(center.displayedSubmenu === "" && center.pageProgress < 1,
                        "outgoing main controls remain rendered during page exit")
                    savedProgress = center.pageProgress
                    center.close()
                    center.toggle(anchorItem)
                    center.openSubmenu("wifi")
                    check(center.pageProgress === savedProgress,
                        "closing and reopening during navigation preserves the current frame")
                    interval = 350
                    break
                case 4:
                    check(info.title === "天气" && info.BackgroundEffect.blurRegion !== null,
                        "weather details retain the same frosted surface")
                    info.page = 3
                    check(center.displayedSubmenu === "wifi" && center.pageProgress === 1,
                        "Wi-Fi page settles")
                    center.closeSubmenu()
                    check(center.activeSubmenu === "" && center.displayedSubmenu === "wifi",
                        "back keeps outgoing Wi-Fi content alive")
                    interval = 60
                    break
                case 5:
                    savedProgress = center.pageProgress
                    center.openSubmenu("wifi")
                    check(center.pageProgress === savedProgress, "page reversal is continuous")
                    interval = 300
                    break
                case 6:
                    check(info.title === "资源占用" && info.BackgroundEffect.blurRegion !== null,
                        "metrics details retain the same frosted surface")
                    center.openSubmenu("bluetooth")
                    center.openSubmenu("sound")
                    center.openSubmenu("brightness")
                    interval = 400
                    break
                case 7:
                    check(center.displayedSubmenu === "brightness" && center.pageProgress === 1,
                        "rapid navigation commits only the latest destination")
                    center.close()
                    check(center.activeSubmenu === "" && !center.submenuOpen
                        && center.displayedSubmenu === "brightness", "close freezes the visible page")
                    interval = 250
                    break
                case 8:
                    check(!center.visible, "control center unmaps only after exit completes")
                    center.toggle(anchorItem)
                    check(center.displayedSubmenu === "", "fresh open never shows a stale submenu")
                    interval = 300
                    break
                case 9:
                    center.openSessionPanel()
                    interval = 400
                    break
                case 10:
                    check(center.displayedSubmenu === "session", "session is an animated page")
                    center.pendingConfirmAction = "poweroff"
                    interval = 350
                    break
                case 11:
                    check(center.displayedSubmenu === "confirm", "confirmation replaces session card")
                    center.pendingConfirmAction = ""
                    interval = 400
                    break
                case 12:
                    check(center.displayedSubmenu === "session" && center.isOpen,
                        "cancel restores session without closing control center")
                    center.close()
                    menu.setItems([{label: "Root", children: [{label: "Child", cmd: "child"}]}])
                    menu.show()
                    interval = 300
                    break
                case 13:
                    menu.enter([{label: "Child", cmd: "child"}])
                    check(menu.displayedPage.items[0].label === "Root", "menu retains outgoing rows")
                    interval = 400
                    break
                case 14:
                    check(menu.displayedPage.items[0].label === "Child", "menu page animation settles")
                    menu.hide()
                    menu.show()
                    launcher.open = true
                    interval = 250
                    break
                case 15:
                    check(menu.visible, "context menu close can reverse")
                    check(launcher.contentRevealProgress === 1, "launcher entrance settles")
                    launcher.open = false
                    check(launcher.contentRevealProgress === 1, "launcher close does not snap to zero")
                    interval = 60
                    break
                case 16:
                    check(launcher.contentRevealProgress > 0 && launcher.contentRevealProgress < 1,
                        "launcher has an exit animation")
                    launcher.open = true
                    popup.hide()
                    menu.hide()
                    info.hide()
                    interval = 300
                    break
                case 17:
                    check(stableGlassChecks > 10, "glass remains stable across animation frames")
                    check(!info.visible && info.BackgroundEffect.blurRegion === null,
                        "the detail popup releases blur after closing")
                    check(!popup.visible && !menu.visible, "popups unmap after closing")
                    check(launcher.contentRevealProgress === 1, "launcher exit can reverse")
                    console.log("POPUP_MOTION_PASS")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("POPUP_MOTION_FAIL stage=" + (test.stage - 1) + " " + error)
                Qt.quit()
            }
        }
    }
}
