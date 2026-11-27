import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter
import qs.desktop.modules.platform
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
    property int gestureStage: 0
    property var catcher: null
    property int revealRequests: 0
    property int revealRequestsBeforeEditing: 0

    // Show-desktop is a signal, so the fixture counts it directly: leaving
    // widget editing must never also toggle the stage.
    Connections {
        target: StageModeService
        function onDeskRevealToggleRequested() { test.revealRequests++ }
    }

    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function check(ok, message) { if (!ok) throw new Error(message) }

    // Widget editing must be escapable by gesture, not only by Escape: a plain
    // click or right-click on the bare desktop must leave editing without
    // toggling show-desktop, and a long press on the fallback surface enters
    // editing without its release undoing it.
    function runWidgetEditGestureStage(stage) {
        switch (stage) {
        case 0: {
            driver.interval = 120
            const card = test.cards.itemAt(0)
            check(!!card && card.contentEnabled,
                "widget contents answer input outside editing")
            check(!desktop.editMode, "editing gesture checks start outside editing")
            test.revealRequestsBeforeEditing = test.revealRequests
            desktop.enterWidgetEditMode()
            break
        }
        case 1:
            check(desktop.editMode && WidgetGalleryService.open,
                "enterWidgetEditMode opens edit mode and gallery")
            check(!test.cards.itemAt(0).contentEnabled,
                "widget contents stay inert while editing")
            events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 2:
            events.mouseRelease(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 3:
            check(!desktop.editMode, "plain click on the bare desktop leaves widget editing")
            check(!WidgetGalleryService.open, "leaving editing closes the widget gallery")
            check(test.revealRequests === test.revealRequestsBeforeEditing,
                "leaving editing must not toggle show-desktop")
            desktop.enterWidgetEditMode()
            events.mousePress(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
            break
        case 4:
            check(!desktop.editMode, "right click on the bare desktop leaves widget editing")
            events.mouseRelease(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
            break
        case 5:
            test.catcher = find(desktop.contentItem, "desktop-background-catcher")
            check(!!test.catcher, "background catcher found")
            test.catcher.pressAndHoldInterval = 60
            events.mousePress(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 6:
            check(desktop.editMode, "long press on the background catcher enters editing")
            events.mouseRelease(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 7:
            check(desktop.editMode, "the release that entered editing must not leave it")
            events.mousePress(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            events.mouseRelease(test.catcher, 5, 5, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 8:
            check(!desktop.editMode, "plain click on the background catcher leaves editing")
            events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            events.mouseRelease(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
            break
        case 9:
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
                if (!AppearanceConfigService.ready || !IconAppearanceService.ready
                        || !SystemFontService.loaded || desktop.widgetCatalog.length === 0)
                    return
                switch (test.stage++) {
                case 0:
                    if (Quickshell.env("EXPECTED_WIDGET_STYLE") === "glass") {
                        check(AppearanceTokens.typography.textFamily === "Inter", "legacy font opt-out is ignored")
                        check(AppearanceConfigService.desktopFontFamily === "", "old profile follows system")
                    } else {
                        check(AppearanceConfigService.desktopFontFamily === Qt.fontFamilies()[0], "desktop family survives restart")
                        check(AppearanceTokens.typography.textFamily === Qt.fontFamilies()[0], "restored family reaches desktop")
                    }
                    check(AppearanceConfigService.widgetStyle === Quickshell.env("EXPECTED_WIDGET_STYLE"),
                        "persisted or migrated widget style")
                    ScreenLifecycle.activeScreen = desktop.screen
                    test.background = find(desktop.contentItem, "desktop-background-selection")
                    test.grid = find(desktop.contentItem, "desktop-file-grid")
                    test.cards = find(desktop.contentItem, "desktop-widget-repeater")
                    check(test.background && test.grid && test.cards, "actual desktop components loaded")
                    AppearanceConfigService.setDeskCenterWidgetVisible("groups", false)
                    while (desktop.widgetInstances.length > 0)
                        desktop.removeWidget(desktop.widgetInstances[0].id)
                    break
                case 1: {
                    check(test.cards.count === 0, "all widgets removed")
                    events.mousePress(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
                    events.mouseRelease(test.background, 100, 100, Qt.RightButton, Qt.NoModifier, 0)
                    const edit = test.grid.buildContextItems().find(row => row.cmd === "editWidgets")
                    check(!!edit, "empty desktop offers Edit Widgets")
                    test.grid.runContextCmd(edit.cmd, edit)
                    check(desktop.editMode && WidgetGalleryService.open,
                        "menu opens widget gallery with zero widgets")
                    break
                }
                case 2: {
                    const clockEntry = desktop.widgetCatalog.find(
                        entry => entry.id === "org.nextkde.widget.clock.macos.analog")
                    check(!!clockEntry, "analog clock SDK package indexed")
                    desktop.addGalleryWidget(clockEntry, "1x1")
                    break
                }
                case 3:
                    check(test.cards.count === 1, "clock package added to desktop")
                    desktop.leaveWidgetEditMode()
                    check(!desktop.editMode && !WidgetGalleryService.open,
                        "leaveWidgetEditMode closes gallery")
                    events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    holdStartedAt = Date.now()
                    interval = 1000
                    break
                case 4:
                    if (!desktop.editMode && Date.now() - holdStartedAt
                            < test.background.pressAndHoldInterval + 1000) {
                        test.stage = 4
                        interval = 50
                        return
                    }
                    check(desktop.editMode, "file-grid background long press enters edit mode")
                    events.mouseMove(test.background, 125, 125, 0, Qt.LeftButton, Qt.NoModifier)
                    check(!test.background.parent.selectionBoxActive,
                        "long press consumes subsequent selection drag")
                    events.mouseRelease(test.background, 125, 125, Qt.LeftButton, Qt.NoModifier, 0)
                    events.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
                    check(!desktop.editMode && !WidgetGalleryService.open,
                        "Escape leaves widget editing")
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
                    desktop.enterWidgetEditMode()
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
                        const backdrop = previous.form === "material" || previous.style === "glass"
                        check(AppearanceTokens.content.onBackdrop === backdrop,
                            "content ink follows widget surface")
                        if (previous.form !== "material") {
                            const card = test.cards.itemAt(0)
                            check(!!card, "macos card present in " + JSON.stringify(previous))
                            check(card.usesColorArtwork === (previous.style === "color"),
                                "card artwork independent of icon colour: " + JSON.stringify(previous))
                            check(!!card.blurRegion === backdrop, "correct compositor surface backend")
                        } else {
                            check(test.cards.count === 0,
                                "macos package parks cleanly while material style is active")
                        }
                    }
                    const next = test.combinations[test.stage - 8]
                    if (next) {
                        AppearanceConfigService.shellStyle = next.form
                        AppearanceConfigService.updateWidgetStyle(next.style)
                        IconAppearanceService.mode = next.icon
                        return
                    }
                    if (AppearanceConfigService.shellStyle !== "macos") {
                        AppearanceConfigService.shellStyle = "macos"
                        AppearanceConfigService.updateWidgetStyle("color")
                        IconAppearanceService.mode = "grayscale"
                        return
                    }
                    check(test.cards.count === 1,
                        "parked macos package restores automatically when switching back from material")
                    if (test.gestureStage < 10) {
                        runWidgetEditGestureStage(test.gestureStage++)
                        return
                    }
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
    Timer { interval: 90000; running: true; onTriggered: { console.error("WIDGET_EXPERIENCE_FAIL: timeout"); Qt.quit() } }
}
