import QtQuick
import QtTest
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.deskcenter

ShellRoot {
    id: test
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
    Timer {
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready || !IconAppearanceService.ready) return
                switch (test.stage++) {
                case 0:
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
                    interval = 1000
                    break
                case 4:
                    check(desktop.editMode, "file-grid background long press enters edit mode")
                    events.mouseMove(test.background, 125, 125, 0, Qt.LeftButton, Qt.NoModifier)
                    check(!test.background.parent.selectionBoxActive, "long press consumes subsequent selection drag")
                    events.mouseRelease(test.background, 125, 125, Qt.LeftButton, Qt.NoModifier, 0)
                    events.keyClick(Qt.Key_Escape, Qt.NoModifier, 0)
                    check(!desktop.editMode && !desktop.widgetLibraryOpen, "Escape leaves widget editing")
                    events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    events.mouseMove(test.background, 160, 160, 0, Qt.LeftButton, Qt.NoModifier)
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
                        check(find(card, "widget-content-layer").layer.enabled === (previous.style === "glass"), "widget effects independent of icon colour")
                    }
                    const next = test.combinations[test.stage - 8]
                    if (next) {
                        AppearanceConfigService.shellStyle = next.form
                        AppearanceConfigService.updateWidgetStyle(next.style)
                        IconAppearanceService.mode = next.icon
                        return
                    }
                    // The runner restarts this same fixture with the saved colour
                    // style and the old grayscale icon setting to prove independence.
                    AppearanceConfigService.updateWidgetStyle("color")
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
