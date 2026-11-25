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
    DeskDigitalClockFace {
        id: digitalProbe
        visible: false
        width: 140
        height: 140
        date: new Date(2026, 0, 2, 9, 7, 0)
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
    property string finalClockStyle: "analog"
    property int motionStage: 0
    property int digitalVisualStage: 0
    property var digitalScenarios: [
        { name: "digital-light-small", form: "macos", style: "color", theme: "light", follow: false, span: 1 },
        { name: "digital-dark-large", form: "windows12", style: "color", theme: "dark", follow: false, span: 2 },
        { name: "digital-glass-fixed-light", form: "macos", style: "glass", theme: "light", follow: false, span: 1 },
        { name: "digital-glass-follow-light-large", form: "macos", style: "glass", theme: "light", follow: true, span: 2 },
        { name: "digital-glass-follow-dark", form: "macos", style: "glass", theme: "dark", follow: true, span: 1 }
    ]

    // Show-desktop is a signal, so the fixture counts it directly: leaving
    // widget editing must never also toggle the stage.
    Connections {
        target: StageModeService
        function onDeskRevealToggleRequested() { test.revealRequests++ }
    }

    function checkDigitalText(face) {
        for (const name of ["city", "time", "offset"]) {
            const label = find(face, "desktop-clock-digital-" + name)
            check(label && label.color.a === 1, "digital " + name + " uses opaque ink")
            check(label && !label.scalableRendering
                && label.renderType === (label.transformed ? Text.QtRendering : Text.NativeRendering),
                "digital " + name + " follows settled/scaled ShellText rendering")
        }
    }

    function checkFixedDigitalFace() {
        const cityLabel = find(digitalProbe, "desktop-clock-digital-city")
        check(digitalProbe.city === "" && !cityLabel.visible,
            "an unavailable system zone hides the geographic label")
        digitalProbe.systemTimeZone = "Europe/London"
        check(digitalProbe.city === "LONDON", "a geographic system zone derives its city")
        digitalProbe.systemTimeZone = "Etc/UTC"
        check(digitalProbe.city === "", "a non-geographic zone removes the city label")
        for (const sample of [
            { zone: "Europe/London", city: "LONDON" },
            { zone: "America/Argentina/Buenos_Aires", city: "BUENOS AIRES" },
            { zone: "UTC", city: "" }, { zone: "Etc/GMT+8", city: "" },
            { zone: "Factory", city: "" }, { zone: "", city: "" }
        ])
            check(digitalProbe.cityLabelForZone(sample.zone) === sample.city,
                "geographic label for " + (sample.zone || "empty zone"))
        for (const sample of [
            { value: -480, text: "-8" }, { value: 0, text: "±0" },
            { value: 60, text: "+1" }, { value: 330, text: "+5:30" }
        ]) {
            digitalProbe.utcOffsetMinutes = sample.value
            check(digitalProbe.formattedOffset() === sample.text,
                "exact UTC offset " + sample.value)
        }
        const ring = find(digitalProbe, "desktop-clock-digital-seconds-ring")
        digitalProbe.cornerRadius = 26
        check(ring.cornerRadius === 16, "ring corner follows the widget radius adjusted for its inset")
        for (const second of [0, 1, 59]) {
            digitalProbe.date = new Date(2026, 0, 2, 9, 7, second)
            check(find(digitalProbe, "desktop-clock-digital-time").text === "09:07",
                "fixed digital time is exact 24-hour HH:mm")
            check(ring.second === second, "ring reads the fixed second")
            for (const index of [0, 1, 58, 59])
                check(ring.tickCompleted(index) === (index < second),
                    "elapsed-only tick " + index + " at second " + second)
        }
    }

    function captureDigital(name) {
        const card = test.cards.itemAt(0)
        check(!!card, "digital card exists for capture")
        const face = find(card, "desktop-clock-digital-face")
        check(face && face.visible && face.width > 0 && face.height > 0,
            "actual digital card is ready for capture")
        check(face.cornerRadius === Math.max(0, AppearanceTokens.widget.radius - 14),
            "digital face receives the inset-adjusted widget radius")
        checkDigitalText(face)
        capturePending = true
        check(card.grabToImage(function(result) {
            try {
                check(result.saveToFile(Quickshell.env("WIDGET_CAPTURE_DIR") + "/" + name + ".png"), "save " + name)
                capturePending = false
                digitalVisualStage++
            } catch (error) {
                console.error("WIDGET_EXPERIENCE_FAIL: " + error)
                Qt.quit()
            }
        }), "capture " + name)
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
                    I18nService.setLanguage("zh-CN")
                    check(desktop.widgetLabels.clock === "时钟", "clock label switches to Chinese immediately")
                    I18nService.setLanguage("en")
                    check(desktop.widgetLabels.clock === "Clock", "clock label switches back to English immediately")
                    checkFixedDigitalFace()
                    check(DeskCenterConfigService.clockStyle === Quickshell.env("EXPECTED_CLOCK_STYLE"),
                        "clock style survives restart")
                    check(!DeskCenterConfigService.setClockStyle("invalid"),
                        "invalid clock style is rejected")
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
                case 3: {
                    check(test.cards.count === 1, "clock restored through library button")
                    check(desktop.editMode, "clock style control is available while editing")
                    const previousStyle = DeskCenterConfigService.clockStyle
                    const analogFace = find(desktop.contentItem, "desktop-clock-face")
                    const digitalFace = find(desktop.contentItem, "desktop-clock-digital-face")
                    check(analogFace && analogFace.visible === (previousStyle === "analog"),
                        "analog face matches saved style")
                    check((digitalFace !== null) === (previousStyle === "digital"),
                        "digital face matches saved style")
                    const styleToggle = find(desktop.contentItem, "widget-clock-style")
                    check(styleToggle && styleToggle.visible, "clock style toggle is visible")
                    const styleLabel = find(styleToggle, "widget-clock-style-label")
                    check(styleLabel && styleLabel.font.family === AppearanceTokens.typography.textFamily,
                        "clock style toggle uses the token font")
                    styleToggle.forceActiveFocus()
                    check(styleToggle.activeFocus && styleToggle.border.width === 2,
                        "clock style toggle has a visible keyboard focus indicator")
                    click(styleToggle)
                    const nextStyle = previousStyle === "analog" ? "digital" : "analog"
                    test.finalClockStyle = nextStyle
                    check(DeskCenterConfigService.clockStyle === nextStyle, "clock style toggles")
                    for (const key of [Qt.Key_Space, Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space]) {
                        const expected = DeskCenterConfigService.clockStyle === "analog" ? "digital" : "analog"
                        events.keyClick(key, Qt.NoModifier, 0)
                        check(DeskCenterConfigService.clockStyle === expected,
                            "clock style toggles with keyboard key " + key)
                    }
                    check(DeskCenterConfigService.clockStyle === nextStyle,
                        "keyboard checks finish on the pointer-selected style")
                    check(analogFace.visible === (nextStyle === "analog"), "analog visibility follows selection")
                    const nextDigitalFace = find(desktop.contentItem, "desktop-clock-digital-face")
                    check((nextDigitalFace !== null) === (nextStyle === "digital"),
                        "digital loader follows selection")
                    check(test.cards.itemAt(0).flowerShapedSurface === (nextStyle === "analog"),
                        "only the analog clock uses the flower surface")
                    if (nextDigitalFace) {
                        check(find(nextDigitalFace, "desktop-clock-digital-time").text.length === 5,
                            "digital face renders localized hours and minutes")
                        const city = find(nextDigitalFace, "desktop-clock-digital-city")
                        check(nextDigitalFace.systemTimeZone === "Europe/London"
                            && city && city.visible && city.text === "LONDON",
                            "digital face derives its label from the actual system timezone")
                        check(find(nextDigitalFace, "desktop-clock-digital-offset").text.length > 0,
                            "digital face renders its UTC offset")
                        const secondsRing = find(nextDigitalFace, "desktop-clock-digital-seconds-ring")
                        check(secondsRing && secondsRing.second === nextDigitalFace.date.getSeconds(),
                            "digital seconds ring follows the clock")
                        checkDigitalText(nextDigitalFace)
                    }
                    desktop.leaveWidgetEditMode()
                    events.mousePress(test.background, 100, 100, Qt.LeftButton, Qt.NoModifier, 0)
                    holdStartedAt = Date.now()
                    interval = 1000
                    break
                }
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
                    if (test.motionStage === 0) {
                        AppearanceConfigService.reduceMotion = true
                        test.motionStage++
                        interval = 100
                        return
                    }
                    if (test.motionStage === 1) {
                        const pages = find(desktop.contentItem, "desktop-clock-pages")
                        check(!!pages, "clock pages exist for reduced-motion check")
                        desktop.timerView = true
                        check(pages.pageProgress === 1, "reduced motion opens the countdown without a page animation")
                        desktop.timerView = false
                        check(pages.pageProgress === 0, "reduced motion closes the countdown without a page animation")
                        AppearanceConfigService.reduceMotion = false
                        test.motionStage++
                        return
                    }
                    const visualCount = test.digitalScenarios.length * 2
                    if (test.digitalVisualStage <= visualCount) {
                        if (test.digitalVisualStage === visualCount) {
                            DeskCenterConfigService.setClockStyle(test.finalClockStyle)
                            desktop.resizeWidget("clock", 1, 1)
                            test.digitalVisualStage++
                            interval = 300
                            return
                        }
                        const scenario = test.digitalScenarios[Math.floor(test.digitalVisualStage / 2)]
                        if (test.digitalVisualStage % 2 === 0) {
                            AppearanceConfigService.shellStyle = scenario.form
                            AppearanceConfigService.updateWidgetStyle(scenario.style)
                            AppearanceConfigService.updateThemeMode(scenario.theme)
                            AppearanceConfigService.updateGlassFollowsAppearanceMode(scenario.follow)
                            DeskCenterConfigService.setClockStyle("digital")
                            check(desktop.resizeWidget("clock", scenario.span, scenario.span),
                                "digital capture uses real " + scenario.span + "x" + scenario.span + " spans")
                            test.digitalVisualStage++
                            interval = 500
                            return
                        }
                        if (test.capturePending) return
                        const card = test.cards.itemAt(0)
                        check(!!card, "digital scenario card exists")
                        const face = find(card, "desktop-clock-digital-face")
                        check(!!face, "digital scenario face loaded")
                        const time = find(face, "desktop-clock-digital-time")
                        check(!!time, "digital scenario time loaded")
                        check(card.displayColumns === scenario.span && card.displayRows === scenario.span,
                            "digital capture settled at its requested spans")
                        check(AppearanceTokens.resolvedAppearanceIsDark === (scenario.theme === "dark"),
                            "digital appearance follows explicit light/dark mode")
                        if (scenario.style === "color") {
                            check(card.startColor.toString() === AppearanceTokens.widget.digitalClock.artworkStart.toString()
                                && card.endColor.toString() === AppearanceTokens.widget.digitalClock.artworkEnd.toString(),
                                "digital card uses semantic artwork roles")
                            check(time.color.toString() === AppearanceTokens.widget.digitalClock.ink.toString(),
                                "digital text uses semantic artwork ink")
                        } else {
                            const expectedDark = scenario.follow ? scenario.theme === "dark" : true
                            check(AppearanceTokens.isDarkTheme === expectedDark,
                                "glass-follow setting selects the expected appearance")
                            check(face.monochrome && time.color.toString()
                                === face.ink(AppearanceTokens.content.glassInk()).toString(),
                                "digital glass text retains semantic monochrome glass ink")
                        }
                        captureDigital(scenario.name)
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
    Timer { interval: 90000; running: true; onTriggered: { console.error("WIDGET_EXPERIENCE_FAIL: timeout"); Qt.quit() } }
}
