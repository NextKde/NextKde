    TestCase {
        function verify(value, message) { if (!value) { console.error("REVIEW_VERIFY_FAILED", message || "", new Error().stack); fail(message || "Verification failed") } }
        function compare(actual, expected, message) { if (actual !== expected) { console.error("REVIEW_COMPARE_FAILED", actual, expected, new Error().stack); fail(message || "Comparison failed") } }
        function tryCompare(object, property, value, timeout) { const end = Date.now() + (timeout || 5000); while (object[property] !== value && Date.now() < end) wait(50); compare(object[property], value, property) }
        function tryVerify(callback, timeout) { const end = Date.now() + (timeout || 5000); while (!callback() && Date.now() < end) wait(50); verify(callback()) }

        id: detailsTest
        name: "ReminderDetails"
        windowShown: true
        when: pim.ready
        function test_details() {
            root.switchWorkspace(true)
            for (const id of ["inbox", "personal"]) {
                const builtin = pim.lists.find(list => list.id === id)
                reminderListEditor.edit(builtin, addButton, builtin.name)
                compare(reminderListEditor.presetColors.length, 18)
                verify(reminderListEditor.presetColors.some(color => color.toLowerCase() === reminderListEditor.selectedColor.toLowerCase()))
                reminderListEditor.close()
            }
            reminderListEditor.edit(null, addButton, "")
            findChild(reminderListEditor.contentItem, "reminderListName").text = "家庭采购"
            const icon = findChild(reminderListEditor.contentItem, "listIcon_home")
            verify(icon !== null)
            mouseClick(icon)
            compare(reminderListEditor.selectedIcon, "home")
            compare(reminderListEditor.presetColors.length, 18)
            wait(300)
            grabImage(root.contentItem).save("/tmp/calendar-list-icons.png")
            reminderListEditor.accept()
            tryVerify(() => pim.lists.some(list => list.name === "家庭采购"))
            tryCompare(reminderListEditor, "visible", false)
            const listId = pim.lists.find(list => list.name === "家庭采购").id
            compare(pim.lists.find(list => list.id === listId).icon, "home")
            remindersView.select("list", listId)
            root.openNewReminder(addButton)
            taskEditor.setQuickTitle("购买厨房用品")
            const timeButton = findChild(taskEditor.contentItem, "reminderTimeToggle")
            const scroller = findChild(taskEditor, "editorScroll")
            verify(timeButton !== null && scroller !== null)
            scroller.contentY = Math.max(0, timeButton.mapToItem(scroller.contentItem, 0, 0).y - 60)
            wait(150)
            mouseClick(timeButton)
            const time = findChild(taskEditor.contentItem, "reminderDueTime")
            tryCompare(time, "visible", true)
            wait(200)
            time.selectedHour = 18
            time.selectedMinute = 30
            time.applyTime()
            verify(taskEditor.payload().due.includes("T18:30:"))
            compare(taskEditor.payload().allDay, false)
            findChild(taskEditor.contentItem, "reminderTags").text = "#家庭 #采购"
            findChild(taskEditor.contentItem, "reminderUrl").text = "https://example.com/list"
            taskEditor.addImages([Qt.resolvedUrl("../sample.png")])
            compare(taskEditor.imageFiles.length, 1)
            scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
            wait(300)
            scroller.contentY = Math.max(0, scroller.contentHeight - scroller.height)
            wait(200)
            grabImage(root.contentItem).save("/tmp/calendar-reminder-media.png")
            taskEditor.accept()
            tryVerify(() => pim.todos.length === 1)
            tryCompare(taskEditor, "visible", false)
            const saved = JSON.parse(JSON.stringify(pim.todos[0]))
            compare(saved.url, "https://example.com/list")
            compare(saved.tags.length, 2)
            compare(saved.images.length, 1)
            verify(saved.images[0] !== String(Qt.resolvedUrl("../sample.png")))
            itemDetails.showItem({kind: "todo", record: saved}, addButton)
            compare(itemDetails.itemImages.length, 1)
            compare(itemDetails.itemUrl, saved.url)
            wait(300)
            grabImage(root.contentItem).save("/tmp/calendar-reminder-media-details.png")
            AppTheme.appearanceMode = "dark"
            Demo.AppTheme.appearanceMode = "dark"
            wait(300)
            grabImage(root.contentItem).save("/tmp/calendar-reminder-media-dark.png")
            itemDetails.close()
            taskEditor.openForTodo(saved)
            compare(taskEditor.imageFiles.length, 1)
            taskEditor.imageFiles = []
            findChild(taskEditor.contentItem, "reminderUrl").text = ""
            taskEditor.accept()
            tryVerify(() => pim.todos[0].images.length === 0 && !pim.todos[0].url)
            console.log("REMINDER_ORGANIZATION_TESTS_PASSED")
        }
    }
    Timer { interval: 1200; running: true; onTriggered: detailsTest.qtest_run() }
