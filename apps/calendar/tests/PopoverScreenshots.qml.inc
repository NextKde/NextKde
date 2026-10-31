    TestCase {
        name: "PopoverScreenshots"
        windowShown: true
        when: pim.ready
        function shot(name) {
            wait(500)
            grabImage(root.contentItem).save("/tmp/calendar-arrow-" + name + ".png")
        }
        function test_capture() {
            root.width = 960; root.height = 660
            AppTheme.appearanceMode = "light"; Demo.AppTheme.appearanceMode = "light"
            root.switchWorkspace(false)
            root.selectedDate = new Date(2026, 9, 29)
            root.beginEvent(root.selectedDate, 9, addButton)
            wait(300); verify(eventEditor.visible); verify(!eventEditor.arrowVisible)
            shot("event-light")
            eventEditor.close()
            root.switchWorkspace(true)
            root.openNewReminder(addButton)
            wait(300); verify(taskEditor.visible); verify(!taskEditor.arrowVisible)
            shot("reminder-light")
            AppTheme.appearanceMode = "dark"; Demo.AppTheme.appearanceMode = "dark"
            shot("reminder-dark")
            taskEditor.close()
            AppTheme.appearanceMode = "light"; Demo.AppTheme.appearanceMode = "light"
            const trigger = findChild(root.contentItem, "addReminderListOrGroup")
            mouseClick(trigger)
            shot("sidebar-menu")
            keyClick(Qt.Key_Escape)
            root.switchWorkspace(false)
            actionsMenu.openAtAnchor()
            wait(300)
            shot("edge-menu")
            actionsMenu.close()
            console.log("REMINDER_ORGANIZATION_TESTS_PASSED")
        }
    }
