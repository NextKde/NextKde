import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import qs.desktop.modules.stage

ShellRoot {
    id: test
    // This fixture mounts only the desktop; no shell boot coordinator runs.
    Component.onCompleted: StartupReveal.finish()
    DeskCenterWindow {
        id: desktop
        // Bind key events to this window. A synthetic mouse event does not
        // grant compositor keyboard focus to a layer-shell surface.
        TestEvent { id: events }
    }
    property int stage: 0
    property var background: null
    property var grid: null
    property var cards: null
    property var combinations: []
    property real holdStartedAt: 0
    property int timerStage: 0
    property bool capturePending: false
    property int gestureStage: 0
    property var widgetCard: null
    property var catcher: null
    property int revealRequests: 0
    property int revealRequestsBeforeEditing: 0

    // Show-desktop is a signal, so the fixture counts it directly: leaving
    // widget editing must never also toggle the stage.
    Connections {
        target: StageModeService
        function onDeskRevealToggleRequested() { test.revealRequests++ }
    }

    function captureBell(name) {
        if (capturePending) return
        const bell = find(desktop.contentItem, "timer-end-bell")
        check(bell && bell.visible, "countdown bell is visible")
        capturePending = true
        check(bell.grabToImage(function(result) {
            try {
                check(result.saveToFile(Quickshell.env("WIDGET_CAPTURE_DIR") + "/" + name + ".png"), "save " + name)
                capturePending = false
                timerStage++
            } catch (error) {
                console.error("WIDGET_EXPERIENCE_FAIL: " + error)
                Qt.quit()
            }
        }), "capture " + name)
    }

    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function click(item) {
        check(events.mousePress(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0), "mouse press")
        check(events.mouseRelease(item, item.width / 2, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0), "mouse release")
    }
    function clickButton(item, button) {
        check(events.mousePress(item, item.width / 2, item.height / 2, button, Qt.NoModifier, 0), "mouse press")
        check(events.mouseRelease(item, item.width / 2, item.height / 2, button, Qt.NoModifier, 0), "mouse release")
    }

    // Widget editing must be escapable by gesture, not only by Escape or the
    // Done button: the right click that entered editing has to leave it again,
    // and a plain click on the bare desktop has to end the session. One stage
    // per frame keeps a press and its release in separate dispatches, the same
    // way the desktop file gestures above are driven.
    function runWidgetEditGestureStage(stage) {
        switch (stage) {
        case 0:
            driver.interval = 120
            const contentLayer = find(desktop.contentItem, "widget-content-layer")
            check(!!contentLayer && contentLayer.enabled,
                "widget contents answer input outside editing")
            test.widgetCard = test.cards.itemAt(0)
            check(!!test.widgetCard, "clock card present for the editing gesture checks")
            check(!desktop.editMode, "editing gesture checks start outside editing")
            test.revealRequestsBeforeEditing = test.revealRequests
            clickButton(test.widgetCard, Qt.RightButton)
            break
        case 1:
            check(desktop.editMode, "right click on a card enters widget editing")
            // A live widget during editing is what launched the app behind a
            // card (and a second copy of a running player crashes QQ Music).
            check(!find(desktop.contentItem, "widget-content-layer").enabled,
                "widget contents stay inert while editing")
            clickButton(test.widgetCard, Qt.RightButton)
            break
        case 2:
            check(!desktop.editMode, "right clicking the same card leaves widget editing")
            desktop.enterWidgetEditMode(false)
            events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 3:
            events.mouseRelease(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 4:
            check(!desktop.editMode, "plain click on the bare desktop leaves widget editing")
            check(!desktop.widgetLibraryOpen, "leaving editing closes the widget library")
            check(test.revealRequests === test.revealRequestsBeforeEditing,
                "leaving editing must not toggle show-desktop")
            desktop.enterWidgetEditMode(false)
            events.mousePress(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
            break
        case 5:
            check(!desktop.editMode, "right click on the bare desktop leaves widget editing")
            // Complete the gesture on the now non-editing desktop.
            events.mouseRelease(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
            break
        case 6:
            // The fallback surface (window margins and the widget strip) has
            // its own entry gesture; the release that completes the hold must
            // not be read as a plain click and undo it.
            test.catcher = find(desktop.contentItem, "desktop-background-catcher")
            check(!!test.catcher, "background catcher found")
            test.catcher.pressAndHoldInterval = 60
            events.mousePress(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 7:
            check(desktop.editMode, "long press on the background catcher enters editing")
            events.mouseRelease(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 8:
            check(desktop.editMode, "the release that entered editing must not leave it")
            events.mousePress(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            events.mouseRelease(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 9:
            check(!desktop.editMode, "plain click on the background catcher leaves editing")
            // Positive control for the counter above: outside editing the same
            // plain desktop click still toggles show-desktop.
            events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            events.mouseRelease(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 10:
            check(test.revealRequests === test.revealRequestsBeforeEditing + 1,
                "plain desktop click outside editing still toggles show-desktop")
            break
        }
    }
    Timer {
        id: driver
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready || !IconAppearanceService.ready || !SystemFontService.loaded) return
                switch (test.stage++) {
                case 0:
                    if (Quickshell.env("EXPECTED_WIDGET_STYLE") === "glass") {
                        check(AppearanceTokens.typography.textFamily === "Inter", "legacy font opt-out is ignored")
                        check(AppearanceConfigService.desktopFontFamily === "", "old profile follows system")
                    } else {
                        check(AppearanceConfigService.desktopFontFamily === Qt.fontFamilies()[0], "desktop family survives restart")
                        check(AppearanceTokens.typography.textFamily === Qt.fontFamilies()[0], "restored family reaches desktop")
                    }
                    check(AppearanceConfigService.widgetStyle === Quickshell.env("EXPECTED_WIDGET_STYLE"), "persisted or migrated widget style")
                    ScreenLifecycle.activeScreen = desktop.screen
                    test.background = find(desktop.contentItem, "desktop-background-selection")
                    test.grid = find(desktop.contentItem, "desktop-file-grid")
                    test.cards = find(desktop.contentItem, "desktop-widget-repeater")
                    check(test.background && test.grid && test.cards, "actual desktop components loaded")
                    for (const id of AppearanceConfigService.deskCenterWidgetIds)
                        AppearanceConfigService.setDeskCenterWidgetVisible(id, false)
                    break
                case 1: {
                    check(test.cards.count === 0, "all widgets removed")
                    // Exercise the real file-grid event route and its menu command.
                    events.mousePress(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
                    events.mouseRelease(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
                    const add = test.grid.buildContextItems().find(row => row.cmd === "addWidgets")
                    check(!!add, "empty desktop offers Add Widgets")
                    test.grid.runContextCmd(add.cmd, add)
                    check(find(desktop.contentItem, "widget-library").visible, "menu opens library with zero widgets")
                    break
                }
                case 2:
                    click(find(desktop.contentItem, "widget-library-clock"))
                    break
                case 3:
                    check(test.cards.count === 1, "clock restored through library button")
                    desktop.leaveWidgetEditMode()
                    events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    holdStartedAt = Date.now()
                    interval = 1000
                    break
                case 4:
                    // The platform hold timer and this fixture timer can be
                    // dispatched on adjacent frames under load. Wait for the
                    // actual gesture, with a bounded deadline.
                    if (!desktop.editMode && Date.now() - holdStartedAt
                            < test.background.pressAndHoldInterval + 1000) {
                        test.stage = 4
                        interval = 50
                        return
                    }
                    check(desktop.editMode, "file-grid background long press enters edit mode")
                    events.mouseMove(test.background, 125, 125, 0, Qt.LeftButton, Qt.NoModifier)
                    check(!test.background.parent.selectionBoxActive, "long press consumes subsequent selection drag")
                    events.mouseRelease(test.background, 125, 125, Qt.LeftButton, Qt.NoModifier, 0)
                    events.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
                    check(!desktop.editMode && !desktop.widgetLibraryOpen, "Escape leaves widget editing")
                    events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mouseMove(test.background, 160, 160, 0, Qt.LeftButton, Qt.NoModifier)
                    interval = test.background.pressAndHoldInterval + 250
                    break
                case 5:
                    check(!desktop.editMode, "box selection must not become a long press")
                    events.mouseRelease(test.background, 160, 160, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mousePress(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
                    break
                case 6:
                    check(!desktop.editMode, "right-button hold must not enter edit mode")
                    events.mouseRelease(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
                    desktop.enterWidgetEditMode(false)
                    desktop.leaveWidgetEditMode()
                    interval = 120
                    for (const form of ["macos", "windows12", "material"])
                        for (const style of ["color", "glass"])
                            for (const icon of ["color", "grayscale", "tint"])
                                test.combinations.push({form, style, icon})
                    break
                default: {
                    const previous = test.combinations[test.stage - 9]
                    if (previous) {
                        const card = test.cards.itemAt(0)
                        const backdrop = previous.form === "material" || previous.style === "glass"
                        check(card.usesColorArtwork === (previous.style === "color"), "card artwork independent of icon colour: " + JSON.stringify(previous))
                        check(AppearanceTokens.content.onBackdrop === backdrop, "content ink follows widget surface")
                        check(!!card.blurRegion === backdrop, "correct compositor surface backend")
                        check(!find(card, "widget-content-layer").layer.enabled, "clock text stays outside the saturation texture")
                    }
                    const next = test.combinations[test.stage - 8]
                    if (next) {
                        AppearanceConfigService.shellStyle = next.form
                        AppearanceConfigService.updateWidgetStyle(next.style)
                        IconAppearanceService.mode = next.icon
                        return
                    }
                    // Keep the real countdown alive while changing the widget
                    // surface. Capture its Canvas, not just a colour property:
                    // a stale texture can have the right binding and wrong pixels.
                    switch (test.timerStage) {
                    case 0:
                        interval = 300
                        AppearanceConfigService.shellStyle = "macos"
                        AppearanceConfigService.updateWidgetStyle("color")
                        desktop.addTimerMinutes(15)
                        desktop.toggleTimer()
                        click(find(desktop.contentItem, "clock-timer-button"))
                        test.timerStage++
                        return
                    case 1:
                        check(desktop.timerView && desktop.timerRunning, "countdown remains active")
                        captureBell("timer-color")
                        return
                    case 2:
                        AppearanceConfigService.updateWidgetStyle("glass")
                        test.timerStage++
                        return
                    case 3:
                        check(desktop.timerView && desktop.timerRunning, "countdown survives glass switch")
                        captureBell("timer-glass")
                        return
                    case 4:
                        AppearanceConfigService.updateWidgetStyle("color")
                        test.timerStage++
                        return
                    case 5:
                        check(desktop.timerView && desktop.timerRunning, "countdown survives colour restore")
                        captureBell("timer-restored")
                        return
                    }
                    if (test.gestureStage < 11) {
                        runWidgetEditGestureStage(test.gestureStage++)
                        return
                    }
                    // The runner restarts this same fixture with the saved colour
                    // style and the old grayscale icon setting to prove independence.
                    AppearanceConfigService.updateWidgetStyle("color")
                    AppearanceConfigService.updateDesktopFontFamily(Qt.fontFamilies()[0])
                    console.log("WIDGET_EXPERIENCE_PASS")
                    running = false
                    finish.start()
                }
                }
            } catch (error) {
                console.error("WIDGET_EXPERIENCE_FAIL: " + error)
                Qt.quit()
            }
        }
    }
    Timer { id: finish; interval: 600; onTriggered: Qt.quit() }
    Timer { interval: 15000; running: true; onTriggered: { console.error("WIDGET_EXPERIENCE_FAIL: timeout"); Qt.quit() } }
}
