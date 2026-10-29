pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Kos.Ui
import Kos.Demo as Demo

Item {
    id: root
    required property var pim
    property string filter: "all"
    property string listId: "inbox"
    property string searchQuery: ""
    property string statusMessage: ""
    property string reorderError: ""
    property var collapsedParents: []
    property var collapsedSections: []
    property Item sourceItem: null
    property bool addingSection: false
    property var inlineDrafts: ({})
    property string inlineFocusKey: ""
    property string inlineSavingKey: ""
    property string inlineError: ""
    readonly property bool canOrganize: ["list", "inbox", "group"].includes(filter)
    readonly property bool columnsMode: ["list", "inbox"].includes(filter) && ((pim.lists.find(list => list.id === listId) || {}).viewMode === "columns") && !searchQuery.trim()
    readonly property var displaySections: buildSections()
    signal editRequested(var todo, Item anchor)
    signal removeSectionRequested(var section, Item anchor)
    property date now: new Date()
    readonly property string today: Qt.formatDate(now, "yyyy-MM-dd")
    readonly property string heading: filter === "group" ? ((pim.groups || []).find(group => group.id === listId) || {}).name || qsTr("Group") : ["list", "smart"].includes(filter) ? listName(listId)
        : filter === "tag" ? "#" + listId
        : ({all: qsTr("All reminders"), today: qsTr("Today"), planned: qsTr("Scheduled"),
            flagged: qsTr("Flagged"), completed: qsTr("Completed"), inbox: qsTr("Inbox"), calendar: qsTr("Linked events")})[filter] || qsTr("Reminders")
    readonly property var allTags: {
        const tags = new Map()
        for (const todo of pim.todos)
            for (const tag of todo.tags || [])
                if (!tags.has(tag.toLocaleLowerCase())) tags.set(tag.toLocaleLowerCase(), tag)
        return Array.from(tags.values()).sort((a, b) => a.localeCompare(b))
    }
    readonly property var visibleTodos: filteredTodos()
    signal openRequested(var todo, Item anchor)
    signal subtaskRequested(var todo, Item anchor)
    CalendarStyle { id: design }
    Item { id: contextAnchor; width: 1; height: 1 }
    Timer { interval: 60000; running: root.visible; repeat: true; onTriggered: root.now = new Date() }
    function listName(id) {
        const list = pim.lists.find(item => item.id === id)
        if (!list) return qsTr("Inbox")
        // Only translate the service's untouched built-in names.
        if (list.id === "inbox" && list.name === "Inbox") return qsTr("Inbox")
        if (list.id === "personal" && list.name === "Personal") return qsTr("Personal")
        return list.name
    }
    function includes(todo, requestedFilter, requestedList) {
        const completed = Boolean(todo.completed)
        if (requestedFilter === "completed") return completed
        if (completed) return false
        const due = String(todo.due || "").slice(0, 10)
        if (requestedFilter === "group") {
            const group = (pim.groups || []).find(item => item.id === requestedList)
            return !!group && pim.lists.some(list => list.group === group.name && (list.kind === "smart" ? matchesRules(todo, list.rules || {}) : list.id === todo.listId))
        }
        if (requestedFilter === "tag") return (todo.tags || []).some(tag => tag.toLocaleLowerCase() === requestedList.toLocaleLowerCase())
        if (requestedFilter === "smart") return matchesRules(todo, (pim.lists.find(list => list.id === requestedList) || {}).rules || {})
        if (requestedFilter === "today") return due.length > 0 && due <= today
        if (requestedFilter === "flagged") return Boolean(todo.flagged)
        if (requestedFilter === "planned") return due.length > 0
        if (requestedFilter === "calendar") return Boolean(todo.linkedEventId)
        if (requestedFilter === "inbox") return todo.listId === "inbox"
        if (requestedFilter === "list") return todo.listId === requestedList
        return true
    }
    function matchesRules(todo, rules) {
        const day = String(todo.due || "").slice(0, 10)
        if (rules.listId && todo.listId !== rules.listId) return false
        if (rules.tag && !(todo.tags || []).some(tag => tag.toLocaleLowerCase() === rules.tag.toLocaleLowerCase())) return false
        if (rules.flag === "yes" && !todo.flagged || rules.flag === "no" && todo.flagged) return false
        if (rules.date === "today" && (!day || day > today)) return false
        if (rules.date === "scheduled" && !day || rules.date === "undated" && day) return false
        if (rules.date === "overdue" && (!day || day >= today)) return false
        const p = Number(todo.priority || 0)
        if (rules.priority === "high" && !(p > 0 && p <= 4)) return false
        if (rules.priority === "medium" && p !== 5) return false
        if (rules.priority === "low" && p < 6 || rules.priority === "none" && p !== 0) return false
        return true
    }
    function creationDefaults() {
        if (filter === "group") {
            const group = (pim.groups || []).find(item => item.id === listId)
            const list = group && pim.lists.find(item => item.group === group.name && item.kind !== "smart")
            return {listId: list ? list.id : "inbox"}
        }
        if (filter === "tag") return {tags: [listId]}
        if (filter !== "smart") return {}
        const rules = (pim.lists.find(list => list.id === listId) || {}).rules || {}
        const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
        const day = rules.date === "overdue" ? Qt.formatDate(yesterday, "yyyy-MM-dd") : today
        return {listId: rules.listId || "inbox", tags: rules.tag ? [rules.tag] : [],
            flagged: rules.flag === "yes", priority: ({high: 1, medium: 5, low: 9})[rules.priority] || 0,
            due: ["today", "scheduled", "overdue"].includes(rules.date) ? day + "T00:00:00" : "", allDay: true}
    }
    function taskSection(todo) {
        const seen = new Set()
        while (todo.parentId && !seen.has(todo.id)) {
            seen.add(todo.id)
            const parent = pim.todos.find(item => item.id === todo.parentId)
            if (!parent) break
            todo = parent
        }
        return String(todo.section || "")
    }
    function moveToList(id, targetList) {
        if (!pim.writable || pim.busy || !pim.lists.some(list => list.id === targetList && list.kind !== "smart")) return false
        pim.updateTodo(id, {listId: targetList, parentId: "", section: "", order: Date.now()})
        return true
    }
    function moveRelative(id, target, after) {
        if (!pim.writable || pim.busy || id === target.id || !["list", "inbox"].includes(filter) || searchQuery.trim()) return false
        const siblings = pim.todos.filter(todo => todo.id !== id && todo.listId === target.listId
            && String(todo.parentId || "") === String(target.parentId || "") && taskSection(todo) === taskSection(target))
            .sort((a, b) => Number(a.order || 0) - Number(b.order || 0) || a.id.localeCompare(b.id))
        const index = siblings.findIndex(todo => todo.id === target.id)
        if (index < 0) return false
        const order = Number(target.order || 0)
        const adjacent = siblings[index + (after ? 1 : -1)]
        const nextOrder = adjacent ? (order + Number(adjacent.order || 0)) / 2 : order + (after ? 1024 : -1024)
        if (nextOrder === order) { reorderError = qsTr("These positions are too close. Move the task to another position first."); return false }
        pim.updateTodo(id, {listId: target.listId, parentId: target.parentId || "", section: taskSection(target), order: nextOrder})
        return true
    }
    function count(requestedFilter, requestedList) {
        return pim.todos.filter(todo => includes(todo, requestedFilter, requestedList)).length
    }
    function filteredTodos() {
        const query = searchQuery.trim().toLocaleLowerCase()
        const matching = pim.todos.filter(todo => includes(todo, filter, listId)
            && (!query || (String(todo.title) + "\n" + String(todo.description || "") + "\n" + (todo.tags || []).join(" ")).toLocaleLowerCase().includes(query)))
            .sort((a, b) => {
                if (["list", "inbox"].includes(filter)) {
                    const section = taskSection(a).localeCompare(taskSection(b))
                    if (section) return section
                }
                if (["all", "list", "inbox", "group"].includes(filter))
                    return Number(a.order || 0) - Number(b.order || 0) || a.id.localeCompare(b.id)
                const ad = String(a.due || "9999"), bd = String(b.due || "9999")
                return ad.localeCompare(bd) || (Number(a.order || 0) - Number(b.order || 0))
                    || String(a.id).localeCompare(String(b.id))
            })
        // Date-based and search views retain their own order; only list views nest.
        if (!["all", "list", "inbox", "group"].includes(filter) || query) return matching
        const ids = new Set(matching.map(todo => todo.id))
        const result = [], visited = new Set()
        function append(todo, depth) {
            if (visited.has(todo.id)) return
            visited.add(todo.id)
            result.push(Object.assign({}, todo, {displayDepth: depth}))
            if (!root.collapsedParents.includes(todo.id))
                matching.filter(child => child.parentId === todo.id).forEach(child => append(child, depth + 1))
        }
        matching.filter(todo => !ids.has(todo.parentId)).forEach(todo => append(todo, 0))
        return result
    }
    function childCount(id) { return pim.todos.filter(todo => todo.parentId === id && !todo.completed).length }
    function toggleChildren(id) {
        collapsedParents = collapsedParents.includes(id) ? collapsedParents.filter(key => key !== id) : collapsedParents.concat([id])
    }
    function listColor(id) {
        return (pim.lists.find(item => item.id === id) || {}).color || design.accent
    }
    function sectionTitle(todo) {
        if (!todo) return ""
        if (["list", "inbox"].includes(filter) && pim.todos.some(item => item.listId === todo.listId && item.section))
            return taskSection(todo) || qsTr("Other")
        if (filter !== "planned" && filter !== "today") return ""
        const day = String(todo.due || "").slice(0, 10)
        if (day < today) return qsTr("Overdue")
        if (day === today) return qsTr("Today")
        const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
        if (day === Qt.formatDate(tomorrow, "yyyy-MM-dd")) return qsTr("Tomorrow")
        return new Date(day + "T12:00:00").toLocaleDateString(Qt.locale(), Locale.LongFormat)
    }
    function priorityText(todo) {
        const priority = Number(todo.priority || 0)
        return priority === 0 ? "" : priority <= 4 ? "!!!" : priority <= 5 ? "!!" : "!"
    }
    function select(requestedFilter, requestedList) {
        addingSection = false
        inlineFocusKey = ""
        filter = requestedFilter
        if (requestedList) listId = requestedList
    }
    function submitInline(targetList, section) {
        const key = targetList + "/" + section
        const title = String(inlineDrafts[key] || "").trim()
        if (!title || inlineSavingKey || pim.busy || !pim.writable) return
        inlineSavingKey = key; inlineError = ""
        pim.createTodo(Object.assign({}, creationDefaults(), {title: title, listId: targetList, section: section, allDay: true, reminderMinutes: -1}))
    }
    function reveal(todo) { Qt.callLater(() => root.openRequested(todo, root)) }
    function toggleSection(key) { collapsedSections = collapsedSections.includes(key) ? collapsedSections.filter(item => item !== key) : collapsedSections.concat([key]) }
    function buildSections() {
        if (["list", "inbox", "group"].includes(filter)) {
            const group = (pim.groups || []).find(item => item.id === listId)
            const lists = filter === "group" ? pim.lists.filter(list => group && list.group === group.name)
                : pim.lists.filter(list => list.id === (filter === "inbox" ? "inbox" : listId))
            const result = []
            for (const list of lists) {
                if (list.kind === "smart") {
                    result.push({id: "", listId: list.id, name: "", title: listName(list.id), todos: visibleTodos.filter(todo => matchesRules(todo, list.rules || {})), canAdd: false})
                    continue
                }
                const sections = list.sections || []
                const unsectioned = visibleTodos.filter(todo => todo.listId === list.id && !taskSection(todo))
                if (unsectioned.length || !sections.length) result.push({id: "", listId: list.id, name: "", title: filter === "group" ? listName(list.id) : sections.length ? qsTr("Other") : "", todos: unsectioned, canAdd: !searchQuery.trim()})
                for (let i = 0; i < sections.length; ++i) {
                    const section = sections[i]
                    const todos = visibleTodos.filter(todo => todo.listId === list.id && taskSection(todo) === section.name)
                    if (!searchQuery.trim() || todos.length) result.push({id: section.id, listId: list.id, name: section.name, title: (filter === "group" ? listName(list.id) + " · " : "") + section.name,
                        position: i, sectionCount: sections.length, todos: todos, canAdd: !searchQuery.trim()})
                }
                if (sections.length && !unsectioned.length && !searchQuery.trim()) result.push({id: "", listId: list.id, name: "", title: filter === "group" ? listName(list.id) + " · " + qsTr("Other") : qsTr("Other"), todos: [], canAdd: true})
            }
            return result
        }
        const groups = []
        for (const todo of visibleTodos) {
            const title = sectionTitle(todo)
            let group = groups.find(item => item.title === title)
            if (!group) { group = {id: "", listId: "", name: "", title: title, todos: [], canAdd: false}; groups.push(group) }
            group.todos.push(todo)
        }
        return groups
    }
    function dueText(todo) {
        const due = String(todo.due || "")
        if (!due) return ""
        const date = due.slice(0,10)
        const time = due.match(/T(\d{2}:\d{2})/)
        return (date === today ? qsTr("Today") : date)
            + (!todo.allDay && time ? " · " + time[1] : "")
    }
    Connections {
        target: root.pim
        function onOperationSucceeded(operation, id) {
            if (operation === "createTodo" && root.inlineSavingKey) {
                const drafts = Object.assign({}, root.inlineDrafts)
                delete drafts[root.inlineSavingKey]
                root.inlineDrafts = drafts
                root.inlineSavingKey = ""
            }
        }
        function onOperationFailed(operation, message) {
            if (operation === "createTodo" && root.inlineSavingKey) { root.inlineSavingKey = ""; root.inlineError = message }
        }
        function onSnapshotChanged() {
            if (root.filter === "group" && !(root.pim.groups || []).some(group => group.id === root.listId)) root.select("all")
            if (["list", "smart"].includes(root.filter) && !root.pim.lists.some(list => list.id === root.listId))
                root.select("all")
        }
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Label { text: root.heading; color: ["list", "smart"].includes(root.filter) ? root.listColor(root.listId) : design.labelPrimary; font.pixelSize: 24; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
            Label { text: String(root.searchQuery.trim() ? root.visibleTodos.length : root.count(root.filter, root.listId)); color: design.labelSecondary; font.pixelSize: 22 }
        }
        Label {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.reorderError || root.pim.errorMessage
            color: root.reorderError || root.pim.errorMessage ? design.statusWarning : design.labelSecondary
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Accessible.role: Accessible.Alert
        }
        RowLayout {
            Layout.fillWidth: true
            visible: ["list", "inbox"].includes(root.filter)
            spacing: 6
            Label { text: qsTr("%1 completed").arg(root.pim.todos.filter(todo => todo.listId === root.listId && todo.completed).length); color: design.labelSecondary; font.pixelSize: 11; Layout.fillWidth: true }
            CalendarButton {
                objectName: "reminderViewMode"
                text: root.columnsMode ? qsTr("List view") : qsTr("Column view")
                flat: true
                enabled: !root.pim.busy
                onClicked: root.pim.updateList(root.listId, {viewMode: root.columnsMode ? "list" : "columns"})
            }
            CalendarButton { objectName: "addReminderSection"; text: qsTr("Add section"); flat: true; onClicked: { root.addingSection = true; sectionName.forceActiveFocus() } }
        }
        RowLayout {
            visible: root.addingSection
            Layout.fillWidth: true
            CalendarTextField { id: sectionName; objectName: "newSectionName"; Layout.fillWidth: true; maximumLength: 128; placeholderText: qsTr("Section name"); onAccepted: if (text.trim()) root.pim.saveSection(root.listId, "", {name: text.trim()}); Keys.onEscapePressed: root.addingSection = false }
            CalendarButton { text: qsTr("Add"); enabled: sectionName.text.trim().length > 0 && !root.pim.busy; onClicked: root.pim.saveSection(root.listId, "", {name: sectionName.text.trim()}) }
            Connections { target: root.pim; function onOperationSucceeded(operation, id) { if (operation === "saveSection" && root.addingSection) { root.addingSection = false; sectionName.clear() } } }
        }
        ScrollView {
            id: tasks
            objectName: "remindersList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: root.columnsMode ? Math.max(availableWidth, root.displaySections.length * 220 - 12) : availableWidth
            contentHeight: Math.max(availableHeight, sectionGrid.implicitHeight)
            GridLayout {
                id: sectionGrid
                width: tasks.contentWidth
                columns: root.columnsMode ? Math.max(1, root.displaySections.length) : 1
                columnSpacing: 12
                rowSpacing: 12
                Repeater {
                    id: sectionRepeater
                    model: root.displaySections
                    delegate: CalendarReminderSection {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.columnsMode ? 208 : tasks.availableWidth
                        workspace: root
                        sectionData: modelData
                        card: root.columnsMode
                    }
                }
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                enabled: ["list", "inbox"].includes(root.filter)
                onTapped: (point, button) => {
                    if (button === Qt.RightButton) {
                        const gridPoint = tasks.mapToItem(sectionGrid, point.position.x, point.position.y)
                        let child = sectionGrid.childAt(gridPoint.x, gridPoint.y)
                        while (child) {
                            if (child.objectName.startsWith("reminderRow_")) return
                            const local = sectionGrid.mapToItem(child, gridPoint.x, gridPoint.y)
                            child = child.childAt(local.x, local.y)
                        }
                        const p = tasks.mapToItem(root, point.position.x, point.position.y)
                        contextAnchor.x = p.x; contextAnchor.y = p.y
                        contentMenu.openAtAnchor()
                    } else if (sectionRepeater.count > 0) {
                        const p = tasks.mapToItem(sectionGrid, point.position.x, point.position.y)
                        const index = root.columnsMode ? Math.min(sectionRepeater.count - 1, Math.floor(p.x / (sectionGrid.width / sectionRepeater.count))) : sectionRepeater.count - 1
                        const section = sectionRepeater.itemAt(index)
                        if (section && p.y > section.y + section.height && !root.searchQuery.trim()) section.beginAdd()
                    }
                }
            }
            Demo.LiquidPopover {
                id: contentMenu
                anchorItem: contextAnchor
                sourceItem: root.sourceItem
                Demo.LiquidPopoverItem { objectName: "contextAddSection"; text: qsTr("Add section"); iconName: "plus"; onTriggered: { root.addingSection = true; sectionName.forceActiveFocus() } }
            }
            Label {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 32)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.displaySections.length === 0
                text: !root.pim.ready ? qsTr("Loading reminders…") : root.searchQuery.trim() ? qsTr("No matching reminders") : root.filter === "group" ? qsTr("Move a list into this group to get started.") : qsTr("No reminders")
                color: design.labelSecondary
                font.pixelSize: 13
            }
        }
    }
}
