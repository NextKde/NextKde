import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.desktop.modules.common
import qs.desktop.modules.bar
import qs.desktop.modules.dock
import qs.desktop.modules.applauncher
import qs.desktop.modules.notifications

ShellRoot {
    id: test
    property int stage: 0
    property real savedProgress: 0
    property int stableGlassChecks: 0
    property int launcherVariant: 0
    property var launcherFrame: null
    property var launcherLayout: null
    property real stableLayoutWidth: 0
    property real stableLayoutHeight: 0
    readonly property var launcherVariants: [
        {mode: "bottom", edge: "bottom"},
        {mode: "bottomWide", edge: "bottom"},
        {mode: "bottom", edge: "left"},
        {mode: "bottom", edge: "right"},
        {mode: "center", edge: "bottom"},
        {mode: "fullscreen", edge: "bottom"}
    ]

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
        LiquidGlassPanel { id: scrimProbe; visible: false; scrimLevel: "balanced" }
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

    QtObject {
        id: notificationGroups
        property ListModel groupsModel: ListModel {}
        property int sidecarRevision: 0
        property var dismissed: []
        property var notice: ({
            summary: "Notification motion", body: "The glass stays with the card.",
            appName: "Motion test", image: "", appIcon: "", urgency: 2,
            expireTimeout: 0, actions: [], hasInlineReply: false
        })
        function latestForKey(key) {
            return dismissed.indexOf(key) < 0 ? notice : null
        }
        function dismissGroupByKey(key) {
            dismissed = dismissed.concat([key])
            sidecarRevision++
            for (let index = 0; index < groupsModel.count; ++index) {
                if (groupsModel.get(index).groupKey === key) {
                    groupsModel.remove(index)
                    return
                }
            }
        }
        function expireGroupByKey(key) { dismissGroupByKey(key) }
    }
    NotificationWindow { id: notifications; groupService: notificationGroups; visible: true; exitDuration: 600 }

    function checkNotificationGlass(expectedCount) {
        const cards = notifications.visibleCards
        check(cards.length === expectedCount, "notification delegates survive until their slide finishes: "
            + cards.length + " vs " + expectedCount)
        const blur = notifications.BackgroundEffect.blurRegion
        check(blur !== null && blur.regions.length === expectedCount,
            "blur includes every live card, including removed model rows")
        for (const card of cards) {
            const region = card.notificationBlurRegion
            const expected = card.mapToItem(null, Qt.rect(0, 0, card.width, card.height))
            check(region.item === card && Math.abs(region.itemRect.x - expected.x) < 0.01
                && Math.abs(region.itemRect.y - expected.y) < 0.01
                && Math.abs(region.itemRect.height - expected.height) < 0.01,
                "notification blur follows each card's slide and displacement")
            if (card.removing) {
                check(!card.enabled && card.displaySummary === "Notification motion",
                    "departing card retains its content without accepting input")
            }
        }
    }

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

    function findItem(item, name) {
        if (item.objectName === name)
            return item
        for (const child of item.children || []) {
            const found = findItem(child, name)
            if (found)
                return found
        }
        return null
    }

    function checkLauncherFrame() {
        check(launcherFrame.width > 0 && launcherFrame.height > 0
            && launcherFrame.width < stableLayoutWidth
            && launcherFrame.height < stableLayoutHeight,
            "the actual glass panel expands/contracts, not just its foreground")
        check(launcherLayout.width === stableLayoutWidth
            && launcherLayout.height === stableLayoutHeight,
            "grid layout remains fixed throughout the panel animation")
        const surface = findItem(launcherFrame, "launcher-glass-surface")
        const content = findItem(launcherFrame, "launcher-motion-content")
        const progress = launcher.contentRevealProgress
        check(launcherFrame.opacity === 1 && content.opacity === progress,
            "launcher content fades once without leaving an empty dark panel")
        check(Math.abs(surface.blurRegion.scrimCap - surface._effectiveScrimCap * progress) < 0.0001
            && Math.abs(surface.blurRegion.scrimDecay - surface._effectiveScrimDecay * progress) < 0.0001,
            "native glass tint fades with the same progress as the launcher content")
        const blur = launcher.BackgroundEffect.blurRegion
        check(blur !== null && blur.item === launcherFrame,
            "native blur follows the animated frame instead of the full-sized layout")
        const expected = launcherFrame.mapToItem(null,
            Qt.rect(0, 0, launcherFrame.width, launcherFrame.height))
        check(Math.abs(blur.itemRect.x - expected.x) < 0.01
            && Math.abs(blur.itemRect.y - expected.y) < 0.01
            && Math.abs(blur.itemRect.width - expected.width) < 0.01
            && Math.abs(blur.itemRect.height - expected.height) < 0.01,
            "blur geometry matches the current visible frame")
        check(Math.abs(launcherFrame.x + launcherFrame.width * launcher.panelOriginX
            - stableLayoutWidth * launcher.panelOriginX) < 0.01
            && Math.abs(launcherFrame.y + launcherFrame.height * launcher.panelOriginY
            - stableLayoutHeight * launcher.panelOriginY) < 0.01,
            "the panel keeps its Dock edge or central origin fixed")
    }

    function checkScrimOpacity() {
        check(scrimProbe.blurRegion.scrimCap === 0.47 && scrimProbe.blurRegion.scrimDecay === 0.75,
            "panels without a reveal retain their existing glass tint")
        for (const opacity of [-1, 0, 0.4, 1, 2]) {
            scrimProbe.scrimOpacity = opacity
            const bounded = Math.max(0, Math.min(1, opacity))
            check(Math.abs(scrimProbe.blurRegion.scrimCap - 0.47 * bounded) < 0.0001
                && Math.abs(scrimProbe.blurRegion.scrimDecay - 0.75 * bounded) < 0.0001,
                "adaptive tint scales both its cap and decay and clamps reveal opacity")
            scrimProbe.scrimFixed = true
            check(scrimProbe.blurRegion.scrimDecay === 2, "fixed tint preserves its protocol mode")
            scrimProbe.scrimGraphite = true
            check(scrimProbe.blurRegion.scrimDecay === 3, "graphite tint preserves its protocol mode")
            scrimProbe.scrimPearl = true
            check(scrimProbe.blurRegion.scrimDecay === 4, "pearl tint preserves its protocol mode")
            scrimProbe.scrimPearl = false
            scrimProbe.scrimGraphite = false
            scrimProbe.scrimFixed = false
        }
        scrimProbe.scrimOpacity = 1
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
                    checkScrimOpacity()
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
                    interval = 380
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
                    launcher.open = false
                    launcher.outputAvailable = true
                    interval = 300
                    break
                case 18:
                    AppLauncherConfigService.displayMode = launcherVariants[launcherVariant].mode
                    AppLauncherService.dockPosition = launcherVariants[launcherVariant].edge
                    AppLauncherService.dockWidth = 800
                    AppLauncherService.dockHeight = 60
                    launcherFrame = findItem(launcher.contentItem, "launcher-motion-frame")
                    launcherLayout = findItem(launcher.contentItem, "launcher-stable-layout")
                    check(launcherFrame !== null && launcherLayout !== null, "launcher frame loads")
                    launcher.open = true
                    interval = 65
                    break
                case 19:
                    stableLayoutWidth = launcherLayout.width
                    stableLayoutHeight = launcherLayout.height
                    checkLauncherFrame()
                    interval = 350
                    break
                case 20:
                    check(launcherFrame.width === stableLayoutWidth
                        && launcherFrame.height === stableLayoutHeight, "panel settles to full size")
                    launcher.open = false
                    check(!launcherFrame.enabled, "exit immediately disables card input")
                    check(launcherFrame.width === stableLayoutWidth, "close starts without a geometry jump")
                    interval = 70
                    break
                case 21:
                    checkLauncherFrame()
                    savedProgress = launcher.contentRevealProgress
                    launcher.open = true
                    check(launcher.contentRevealProgress === savedProgress, "panel geometry reverses continuously")
                    interval = 330
                    break
                case 22:
                    check(launcherFrame.width === stableLayoutWidth
                        && launcherFrame.height === stableLayoutHeight, "reopening restores full panel size")
                    launcher.open = false
                    interval = 300
                    break
                case 23:
                    check(!launcherFrame.visible && launcher.BackgroundEffect.blurRegion === null,
                        "panel collapses completely before its blur is removed")
                    launcherVariant++
                    if (launcherVariant < launcherVariants.length) {
                        test.stage = 18
                        interval = 40
                    } else {
                        interval = 40
                    }
                    break
                case 24:
                    notificationGroups.groupsModel.append({groupKey: "first", count: 1, collapsed: true})
                    notificationGroups.groupsModel.append({groupKey: "second", count: 1, collapsed: true})
                    interval = 280
                    break
                case 25:
                    checkNotificationGlass(2)
                    notifications.visibleCards.find(card => card.groupKey === "first").close(false)
                    interval = 80
                    break
                case 26:
                    checkNotificationGlass(2)
                    check(notificationGroups.groupsModel.count === 1, "dismiss removes the model row immediately")
                    check(notifications.visibleCards.some(card => card.removing && card.x > 0),
                        "removed notification and its blur continue sliding together")
                    check(notifications.mask.regions.length === 1, "departing card releases its input region")
                    interval = 600
                    break
                case 27:
                    checkNotificationGlass(1)
                    notifications.visibleCards[0].close(true)
                    interval = 80
                    break
                case 28:
                    checkNotificationGlass(1)
                    check(notificationGroups.groupsModel.count === 0 && notifications.mask.regions.length === 0,
                        "last notification keeps its exiting blur without blocking input")
                    notificationGroups.groupsModel.append({groupKey: "replacement", count: 1, collapsed: true})
                    interval = 50
                    break
                case 29:
                    checkNotificationGlass(2)
                    interval = 600
                    break
                case 30:
                    checkNotificationGlass(1)
                    notifications.visibleCards[0].close(false)
                    interval = 650
                    break
                case 31:
                    check(notifications.visibleCards.length === 0 && notifications.BackgroundEffect.blurRegion === null,
                        "notification blur is released only after the last delegate exits")
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
