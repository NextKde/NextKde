import QtQuick
import QtQuick.Controls
import "../../../shared/qml/i18n"
import qs.desktop.modules.common
import "DesktopGroups.mjs" as DesktopGroups

// Content of the grouped desktop widget. The widget delegate owns the card,
// placement, edit mode and resize handles; this component draws the header,
// type tabs, search bubble and member grid only.
Item {
    id: root
    anchors.fill: parent

    property var entries: []
    property string initialCategory: "shortcuts"
    property bool editing: false
    // Display parity with the normal desktop icon field.
    property bool showExtensions: true
    property var folderCustomizations: ({})
    // Member artwork follows the desktop's Small/Medium/Large icon size.
    // The grid metrics scale with it so a 72 px icon keeps its two-line label
    // without overflowing, while a 40 px icon fits more columns.
    property int iconSize: 56
    readonly property int iconTopMargin: Math.max(4, Math.round(iconSize * 0.1))
    readonly property int cellHeight: Math.max(64, iconSize + 46)
    readonly property int columnWidth: Math.max(48, iconSize + 36)
    readonly property int labelFontSize: iconSize >= 72 ? 14
        : iconSize >= 56 ? 11 : 9
    readonly property int labelFontWeight: iconSize >= 72 ? Font.Bold
        : iconSize >= 56 ? Font.DemiBold : Font.Medium

    property string selectedCategory: ""
    property bool searchOpen: false
    property string searchQuery: ""
    // The normal icon field is hidden while this card is shown, so the card
    // owns its own inline rename editor and commits through the same callback.
    property string renamingPath: ""
    property var renameCallback: null
    // Single selection gives the click the same feedback as the normal icon
    // field and makes the double-click target obvious.
    property string selectedPath: ""

    readonly property var groups: DesktopGroups.buildGroups(entries)
    readonly property int totalCount: groups.reduce(function(sum, group) {
        return sum + group.entries.length
    }, 0)
    readonly property var selectedGroup: groupFor(selectedCategory)
    readonly property var selectedEntries: selectedGroup
        ? selectedGroup.entries : []
    // Diagnostics/test hook: the reconciled content model drives the grid.
    readonly property int contentCount: contentModel.count

    signal openEntryRequested(var entry)
    signal categorySelected(string category)
    // Position is in window/scene coordinates, so the host can anchor the
    // shared desktop context menu beside the member.
    signal contextMenuRequested(var entry, real x, real y)

    function groupFor(category) {
        for (let index = 0; index < groups.length; ++index) {
            if (groups[index].category === category)
                return groups[index]
        }
        return null
    }

    function countFor(category) {
        const group = groupFor(category)
        return group ? group.entries.length : 0
    }

    function customFor(entry) {
        const path = entry?.path
        return path && root.folderCustomizations
            ? root.folderCustomizations[path] ?? null : null
    }

    function displayName(entry) {
        const name = entry?.title || entry?.name || ""
        if (root.showExtensions || entry?.kind === "folder")
            return name
        const extensionIndex = name.lastIndexOf(".")
        return extensionIndex > 0 ? name.slice(0, extensionIndex) : name
    }

    function isSelected(path) {
        return path !== "" && path === root.selectedPath
    }

    function selectOnly(path) {
        root.selectedPath = path ?? ""
    }

    function beginRename(path) {
        if (path)
            root.renamingPath = path
    }

    function renameSelectionEnd(entry) {
        const name = entry?.name ?? ""
        if (entry?.kind === "folder")
            return name.length
        const extensionIndex = name.lastIndexOf(".")
        return extensionIndex > 0 ? extensionIndex : name.length
    }

    function commitRename(entry, name) {
        const trimmed = (name ?? "").trim()
        if (!root.renameCallback || trimmed.length === 0)
            return false
        if (!root.renameCallback(entry, trimmed))
            return false
        root.renamingPath = ""
        return true
    }

    function ensureSelection() {
        const current = groupFor(selectedCategory)
        if (current && current.entries.length > 0)
            return
        const first = groups.find(function(group) {
            return group.entries.length > 0
        })
        const next = first ? first.category : ""
        if (selectedCategory !== next)
            selectedCategory = next
    }

    function selectCategory(category) {
        if (DesktopGroups.CATEGORY_ORDER.indexOf(category) < 0)
            return false
        if (countFor(category) === 0)
            return false
        if (selectedCategory !== category)
            selectedCategory = category
        categorySelected(category)
        return true
    }

    function entryMatches(entry) {
        const query = searchQuery.trim().toLowerCase()
        if (query.length === 0)
            return true
        const text = String(entry?.title || entry?.name || "").toLowerCase()
        if (text.indexOf(query) >= 0)
            return true
        // Extension hiding changes the visible name; searching either form
        // must keep finding the same file.
        return root.displayName(entry).toLowerCase().indexOf(query) >= 0
    }

    function openSearch() {
        root.searchOpen = true
        Qt.callLater(function() {
            if (searchField) {
                searchField.forceActiveFocus()
                searchField.selectAll()
            }
        })
    }

    function closeSearch() {
        // Closing the bubble keeps the filter active so the grid does not
        // change under the pointer; clear the input to restore the type.
        root.searchOpen = false
    }

    function toggleSearch() {
        if (root.searchOpen)
            closeSearch()
        else
            openSearch()
    }

    ListModel { id: contentModel }

    function syncContent() {
        const group = groupFor(selectedCategory)
        const next = (group ? group.entries : []).filter(function(entry) {
            return !!entry?.path && root.entryMatches(entry)
        })
        const nextPaths = ({})
        for (let index = 0; index < next.length; ++index)
            nextPaths[next[index].path] = true
        // A rename that succeeded has a new path; a filtered-out or removed
        // entry must not leave a stale editor behind.
        if (root.renamingPath && !nextPaths[root.renamingPath])
            root.renamingPath = ""
        // The same applies to the selection: switching tabs must not leave a
        // highlight on an item that is no longer visible.
        if (root.selectedPath && !nextPaths[root.selectedPath])
            root.selectedPath = ""
        for (let index = contentModel.count - 1; index >= 0; --index) {
            if (!nextPaths[contentModel.get(index).path])
                contentModel.remove(index)
        }
        for (let target = 0; target < next.length; ++target) {
            const entry = next[target]
            let current = -1
            for (let index = target; index < contentModel.count; ++index) {
                if (contentModel.get(index).path === entry.path) {
                    current = index
                    break
                }
            }
            if (current < 0) {
                contentModel.insert(target, { path: entry.path, entry: entry })
                continue
            }
            if (current !== target)
                contentModel.move(current, target, 1)
            contentModel.set(target, { path: entry.path, entry: entry })
        }
    }

    onInitialCategoryChanged: {
        if (initialCategory && countFor(initialCategory) > 0
                && initialCategory !== selectedCategory)
            selectedCategory = initialCategory
    }
    onGroupsChanged: {
        if (groups.length === 0)
            closeSearch()
        ensureSelection()
        syncContent()
    }
    onSelectedCategoryChanged: syncContent()
    onSearchQueryChanged: syncContent()
    onEditingChanged: {
        if (editing)
            closeSearch()
    }
    Component.onCompleted: {
        if (initialCategory)
            selectedCategory = initialCategory
        ensureSelection()
        syncContent()
    }

    // Consume bare left clicks so they do not reach Show Desktop. Right-click
    // is deliberately left alone: the widget delegate uses it for edit mode.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        z: 0
    }

    // ── Header: title, total and search ────────────────────────────
    Item {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 44

        Text {
            id: headerTitle
            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: I18n.tr("Grouped View")
            color: AppearanceTokens.surface.widgetForeground
            font {
                family: AppearanceTokens.typography.textFamily
                pixelSize: 14
                weight: Font.DemiBold
            }
        }

        Text {
            anchors {
                left: headerTitle.right
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: root.totalCount
            color: AppearanceTokens.surface.widgetForeground
            opacity: 0.6
            font {
                family: AppearanceTokens.typography.textFamily
                pixelSize: 11
            }
        }

        Item {
            id: searchButton
            width: 28
            height: 28
            anchors {
                right: parent.right
                rightMargin: 16
                verticalCenter: parent.verticalCenter
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.searchOpen || root.searchQuery.length > 0
                    || searchHover.hovered
                    ? AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.layer2,
                        Qt.rgba(1, 1, 1, 0.10))
                    : "transparent"
                Behavior on color {
                    ColorAnimation {
                        duration: AppearanceTokens.motion.fast.duration
                    }
                }
            }

            BundledIcon {
                anchors.centerIn: parent
                name: "search.query"
                size: 16
                color: AppearanceTokens.surface.widgetForeground
            }

            HoverHandler {
                id: searchHover
                cursorShape: Qt.PointingHandCursor
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: root.toggleSearch()
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 12
                rightMargin: 12
            }
            height: 1
            color: AppearanceTokens.surface.pick(
                AppearanceTokens.colors.outlineVariant,
                Qt.rgba(1, 1, 1, 0.12))
        }

    }

    // ── Left type tabs ─────────────────────────────────────────────
    Item {
        id: tabs
        width: 108
        anchors {
            left: parent.left
            top: header.bottom
            bottom: parent.bottom
            leftMargin: 10
            topMargin: 2
            bottomMargin: 10
        }

        Column {
            anchors.fill: parent
            spacing: 2

            Repeater {
                model: DesktopGroups.CATEGORY_ORDER
                delegate: Item {
                    id: tab
                    required property string modelData
                    readonly property int count: root.countFor(modelData)
                    readonly property bool selected:
                        root.selectedCategory === modelData
                    width: parent.width
                    height: 40
                    opacity: count > 0 ? 1 : 0.38
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.tr(DesktopGroups.labelKey(modelData))
                        + " · " + count

                    HoverHandler { id: tabHover }

                    Rectangle {
                        id: tabSurface
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 8
                        color: tab.selected
                            ? AppearanceTokens.surface.pick(
                                AppearanceTokens.colors.primaryContainer,
                                Qt.rgba(1, 1, 1, 0.16))
                            : (tabHover.hovered && tab.count > 0
                                ? AppearanceTokens.surface.pick(
                                    AppearanceTokens.colors.layer2,
                                    Qt.rgba(1, 1, 1, 0.08))
                                : "transparent")
                        Behavior on color {
                            ColorAnimation {
                                duration: AppearanceTokens.motion.fast.duration
                            }
                        }

                        BundledIcon {
                            id: tabIcon
                            anchors {
                                left: parent.left
                                leftMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            name: DesktopGroups.iconName(tab.modelData)
                            size: 16
                            color: tab.selected
                                ? AppearanceTokens.surface.pick(
                                    AppearanceTokens.colors.primaryContainerForeground,
                                    "white")
                                : AppearanceTokens.surface.widgetForeground
                        }

                        Text {
                            id: tabLabel
                            anchors {
                                left: tabIcon.right
                                leftMargin: 6
                                right: tabCount.left
                                rightMargin: 4
                                verticalCenter: parent.verticalCenter
                            }
                            text: I18n.tr(DesktopGroups.labelKey(tab.modelData))
                            color: tab.selected
                                ? AppearanceTokens.surface.pick(
                                    AppearanceTokens.colors.primaryContainerForeground,
                                    "white")
                                : AppearanceTokens.surface.widgetForeground
                            elide: Text.ElideRight
                            font {
                                family: AppearanceTokens.typography.textFamily
                                pixelSize: 11
                                weight: tab.selected ? Font.DemiBold : Font.Medium
                            }
                        }

                        Text {
                            id: tabCount
                            anchors {
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            text: tab.count
                            color: tab.selected
                                ? AppearanceTokens.surface.pick(
                                    AppearanceTokens.colors.primaryContainerForeground,
                                    "white")
                                : AppearanceTokens.surface.widgetForeground
                            opacity: 0.65
                            font {
                                family: AppearanceTokens.typography.textFamily
                                pixelSize: 10
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        enabled: tab.count > 0
                        cursorShape: enabled ? Qt.PointingHandCursor
                            : Qt.ArrowCursor
                        onClicked: root.selectCategory(tab.modelData)
                    }
                }
            }
        }
    }

    Rectangle {
        anchors {
            left: tabs.right
            top: header.bottom
            bottom: parent.bottom
            topMargin: 8
            bottomMargin: 12
        }
        width: 1
        color: AppearanceTokens.surface.pick(
            AppearanceTokens.colors.outlineVariant,
            Qt.rgba(1, 1, 1, 0.12))
    }

    // ── Selected category contents ────────────────────────────────
    Item {
        id: content
        anchors {
            left: tabs.right
            leftMargin: 12
            right: parent.right
            rightMargin: 12
            top: header.bottom
            topMargin: 4
            bottom: parent.bottom
            bottomMargin: 12
        }

        GridView {
            id: grid
            objectName: "desktop-groups-grid"
            anchors.fill: parent
            clip: true
            readonly property int columns: Math.max(1,
                Math.floor(width / root.columnWidth))
            cellWidth: width / columns
            cellHeight: root.cellHeight
            model: contentModel
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 3
            }

            delegate: Item {
                id: tile
                required property string path
                required property var entry
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property var custom: root.customFor(tile.entry)
                readonly property bool selected: root.isSelected(tile.path)
                Accessible.role: Accessible.Button
                Accessible.name: root.displayName(tile.entry)

                // Same filled selection as the normal icon field, so a click
                // visibly pins the item before the double-click opens it.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 12
                    color: tile.selected
                        ? Qt.rgba(0.18, 0.42, 0.78, 0.42)
                        : Qt.rgba(1, 1, 1, 0.08)
                    border.width: tile.selected ? 1 : 0
                    border.color: Qt.rgba(0.45, 0.70, 1, 0.75)
                    opacity: tile.selected || tileHover.hovered ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: AppearanceTokens.motion.fast.duration
                            easing.type: AppearanceTokens.motion.enterCurve
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: AppearanceTokens.motion.fast.duration
                        }
                    }
                }

                DesktopGroupMemberIcon {
                    id: glyph
                    anchors {
                        top: parent.top
                        horizontalCenter: parent.horizontalCenter
                        topMargin: root.iconTopMargin
                    }
                    width: root.iconSize
                    height: root.iconSize
                    entry: tile.entry
                    folderCustom: tile.custom
                    size: root.iconSize
                }

                Text {
                    anchors {
                        top: glyph.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 2
                    }
                    visible: root.renamingPath !== tile.path
                    // Same emblem-before-label treatment as the normal icon
                    // field, so the shared customization menu is not dead
                    // outside folders.
                    text: (tile.custom && tile.custom.emoji
                        ? tile.custom.emoji + " " : "")
                        + root.displayName(tile.entry)
                    color: tile.custom && tile.custom.color
                        ? tile.custom.color
                        : AppearanceTokens.surface.widgetForeground
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    font {
                        family: AppearanceTokens.typography.textFamily
                        pixelSize: root.labelFontSize
                        weight: root.labelFontWeight
                    }
                }

                // Inline rename: the normal icon field is hidden behind this
                // card, so the editor lives here and commits through the same
                // desktop rename callback (validation, folder-custom migration).
                Rectangle {
                    id: renameFrame
                    anchors {
                        top: glyph.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 2
                    }
                    height: root.labelFontSize + 12
                    radius: 5
                    visible: root.renamingPath === tile.path
                    color: AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.layer3,
                        Qt.rgba(0.14, 0.15, 0.20, 0.90))
                    border.width: 1
                    border.color: AppearanceTokens.surface.pick(
                        AppearanceTokens.colors.primary,
                        Qt.rgba(1, 1, 1, 0.42))

                    function commit() {
                        if (root.renamingPath !== tile.path)
                            return
                        root.commitRename(tile.entry, renameInput.text)
                    }

                    onVisibleChanged: {
                        if (!visible)
                            return
                        renameInput.text = tile.entry?.name ?? ""
                        renameInput.forceActiveFocus()
                        renameInput.select(0,
                            root.renameSelectionEnd(tile.entry))
                    }

                    TextInput {
                        id: renameInput
                        anchors {
                            fill: parent
                            leftMargin: 5
                            rightMargin: 5
                        }
                        color: AppearanceTokens.surface.widgetForeground
                        selectionColor: AppearanceTokens.surface.pick(
                            AppearanceTokens.colors.primaryContainer,
                            Qt.rgba(1, 1, 1, 0.22))
                        selectedTextColor: AppearanceTokens.surface.pick(
                            AppearanceTokens.colors.primaryContainerForeground,
                            "white")
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        selectByMouse: true
                        font {
                            family: AppearanceTokens.typography.textFamily
                            pixelSize: root.labelFontSize
                            weight: root.labelFontWeight
                        }
                        onActiveFocusChanged: {
                            if (!activeFocus && renameFrame.visible)
                                renameFrame.commit()
                        }
                        Keys.onReturnPressed: function(event) {
                            renameFrame.commit()
                            event.accepted = true
                        }
                        Keys.onEscapePressed: function(event) {
                            root.renamingPath = ""
                            event.accepted = true
                        }
                    }
                }

                HoverHandler {
                    id: tileHover
                    cursorShape: Qt.PointingHandCursor
                }

                // Double-click opens, like the normal desktop. Right-click
                // opens the shared file menu; the inner handler takes the
                // button before the card's right-click-to-edit gesture.
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    enabled: root.renamingPath !== tile.path
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: function(point, button) {
                        root.selectOnly(tile.path)
                        if (button !== Qt.RightButton)
                            return
                        const scenePoint = tile.mapToItem(null,
                            point.position.x, point.position.y)
                        root.contextMenuRequested(tile.entry,
                            scenePoint.x, scenePoint.y)
                    }
                    onDoubleTapped: function(point, button) {
                        if (button !== Qt.LeftButton)
                            return
                        // A synthesized double tap may not emit the first
                        // single tap; select here too so the opened item is
                        // always the highlighted one.
                        root.selectOnly(tile.path)
                        root.openEntryRequested(tile.entry)
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: contentModel.count === 0 && root.searchQuery.length > 0
            text: I18n.tr("No results")
            color: AppearanceTokens.surface.widgetForeground
            opacity: 0.6
            font {
                family: AppearanceTokens.typography.textFamily
                pixelSize: 12
            }
        }
    }

    // ── Search bubble ─────────────────────────────────────────────
    // Only the input: the query filters the type already selected on the left.
    MouseArea {
        id: searchScrim
        anchors.fill: parent
        z: 70
        visible: root.searchOpen
        acceptedButtons: Qt.LeftButton
        onClicked: root.closeSearch()
    }

    Item {
        id: searchPopover
        visible: root.searchOpen
        z: 80
        width: Math.min(300, root.width - 24)
        height: 58
        anchors {
            right: parent.right
            top: header.bottom
            rightMargin: 12
            topMargin: 6
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: AppearanceTokens.surface.pick(
                AppearanceTokens.colors.layer3,
                Qt.rgba(0.14, 0.15, 0.20, 0.66))
            border.width: 1
            border.color: AppearanceTokens.surface.pick(
                AppearanceTokens.colors.outlineVariant,
                Qt.rgba(1, 1, 1, 0.16))
        }

        Rectangle {
            id: searchFieldFrame
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            height: 34
            radius: 10
            color: AppearanceTokens.surface.pick(
                AppearanceTokens.colors.layer2,
                Qt.rgba(1, 1, 1, 0.08))
            border.width: 1
            border.color: searchField.activeFocus
                ? AppearanceTokens.surface.pick(
                    AppearanceTokens.colors.primary,
                    Qt.rgba(1, 1, 1, 0.28))
                : AppearanceTokens.surface.pick(
                    AppearanceTokens.colors.outlineVariant,
                    Qt.rgba(1, 1, 1, 0.12))
            Behavior on border.color {
                ColorAnimation {
                    duration: AppearanceTokens.motion.fast.duration
                }
            }

            TextInput {
                id: searchField
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: AppearanceTokens.surface.widgetForeground
                selectionColor: AppearanceTokens.surface.pick(
                    AppearanceTokens.colors.primaryContainer,
                    Qt.rgba(1, 1, 1, 0.22))
                selectedTextColor: AppearanceTokens.surface.pick(
                    AppearanceTokens.colors.primaryContainerForeground, "white")
                font {
                    family: AppearanceTokens.typography.textFamily
                    pixelSize: 12
                }
                selectByMouse: true
                onTextChanged: root.searchQuery = text
                Keys.onEscapePressed: root.closeSearch()
            }

            Text {
                anchors {
                    left: searchField.left
                    right: searchField.right
                    verticalCenter: searchField.verticalCenter
                }
                visible: searchField.text.length === 0
                text: I18n.tr("Search this type")
                color: AppearanceTokens.surface.widgetForeground
                opacity: 0.45
                elide: Text.ElideRight
                font: searchField.font
            }
        }
    }

}
