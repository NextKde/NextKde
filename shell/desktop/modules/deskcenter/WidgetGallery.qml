import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.bar
import "../../../shared/qml/i18n"

Rectangle {
    id: root
    property Component builtinPreview
    property real desktopCellSize: 180
    property real desktopGap: 10
    property string selectedCategory: "all"
    property string query: ""
    property string feedback: ""
    property bool dragging: false
    readonly property bool compact: width < 600
    readonly property color ink: ThemeService.foregroundColor
    signal addRequested(var entry, string size)
    signal dragMoved(var entry, string size, real x, real y)
    signal dragReleased(var entry, string size, real x, real y)
    signal dragCancelled()
    signal done()
    signal centerRequested()
    objectName: "widget-library"
    radius: 16
    color: "transparent"
    readonly property var blurRegion: surface.item?.blurRegion || null
    Loader {
        id: surface
        anchors.fill: parent
        active: root.visible && AppearanceTokens.surface.usesKwinBlur
        sourceComponent: Component {
            ControlCenterCard {
                cardWidth: root.width
                cardHeight: root.height
                cardRadius: root.radius
                blurAnchor: root
                cardScrimLevel: AppearanceTokens.bar.popupScrimLevel
                fallbackEnabled: false
            }
        }
    }
    // Own a readable scrim even when the compositor advertises a glass form
    // but cannot provide background blur. Keep it above the native surface's
    // QML fallback and below all gallery content; never alter global glass.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: ThemeService.isDark ? "#f228272b" : "#f2f4f0ed"
        border { width: 1; color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.13) }
    }
    Keys.onEscapePressed: {
        if (dragging) { dragging = false; root.dragCancelled() }
        else root.done()
    }
    function begin() {
        if (!visible) return
        search.forceActiveFocus()
        PluginWidgetService.refresh()
    }
    function sizeName(size) {
        return I18n.tr(size === "small" ? "Small" : size === "large" ? "Large" : "Medium")
    }
    readonly property var categories: {
        const result = [{id: "all", name: I18n.tr("All Widgets"), icon: ""}]
        for (const item of WidgetRegistry.builtins)
            result.push({id: item.id, name: item.name, icon: "desktop.widget." + item.id})
        for (const entry of WidgetRegistry.catalog) {
            if (entry.pluginId && !result.some(item => item.id === entry.category))
                result.push({id: entry.category, name: entry.categoryName, icon: ""})
        }
        return result
    }
    readonly property var entries: {
        const needle = query.trim().toLocaleLowerCase()
        return WidgetRegistry.catalog.filter(entry =>
            (selectedCategory === "all" || entry.category === selectedCategory || (!entry.pluginId && entry.id === selectedCategory))
            && (!needle || (entry.name + " " + entry.description + " " + entry.categoryName).toLocaleLowerCase().includes(needle)))
    }
    onCategoriesChanged: {
        if (!categories.some(item => item.id === selectedCategory)) selectedCategory = "all"
    }

    // Own all panel background clicks, including the spaces between previews.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton }
    Item {
        id: sidebar
        x: 14; y: 14
        width: root.compact ? parent.width - 28 : Math.min(190, parent.width * 0.24)
        height: root.compact ? 88 : parent.height - footer.height - 28
        Controls.TextField {
            id: search
            objectName: "widget-gallery-search"
            width: root.compact ? parent.width - 40 : parent.width
            height: 32
            placeholderText: I18n.tr("Search Widgets")
            selectByMouse: true
            font.pixelSize: 12
            color: root.ink
            onTextChanged: root.query = text
            background: Rectangle {
                radius: 9
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                border.width: search.activeFocus ? 2 : 1
                border.color: search.activeFocus ? "#007aff" : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.13)
            }
            Keys.onDownPressed: {
                if (root.compact) compactCategories.forceActiveFocus()
                else categoriesList.forceActiveFocus()
            }
        }
        Controls.Button {
            visible: root.compact
            anchors { right: parent.right; top: parent.top }
            width: 32; height: 32
            text: "+"
            Accessible.name: I18n.tr("Plugin Center")
            Controls.ToolTip.visible: hovered
            Controls.ToolTip.text: I18n.tr("Plugin Center")
            onClicked: root.centerRequested()
        }
        Controls.ComboBox {
            id: compactCategories
            visible: root.compact
            anchors { top: search.bottom; topMargin: 8 }
            width: parent.width
            height: 32
            model: root.categories
            textRole: "name"
            valueRole: "id"
            onActivated: root.selectedCategory = currentValue
        }
        ListView {
            id: categoriesList
            visible: !root.compact
            anchors { top: search.bottom; topMargin: 8; bottom: center.top; bottomMargin: 8 }
            width: parent.width
            clip: true
            spacing: 2
            model: root.categories
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
            delegate: Controls.ItemDelegate {
                required property var modelData
                required property int index
                width: categoriesList.width
                height: 34
                highlighted: root.selectedCategory === modelData.id
                onClicked: { root.selectedCategory = modelData.id; categoriesList.currentIndex = index }
                contentItem: Row {
                    spacing: 8
                    BundledIcon { visible: !!modelData.icon; name: modelData.icon; size: 20; color: root.ink }
                    Text {
                        width: parent.width - (modelData.icon ? 28 : 0)
                        height: 20
                        verticalAlignment: Text.AlignVCenter
                        text: modelData.name
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        color: root.ink
                        elide: Text.ElideRight
                    }
                }
                background: Rectangle {
                    radius: 7
                    color: parent.highlighted ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
                        : parent.hovered ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05) : "transparent"
                    border.width: parent.activeFocus ? 2 : 0
                    border.color: "#007aff"
                }
            }
        }
        Controls.Button {
            id: center
            visible: !root.compact
            anchors.bottom: parent.bottom
            width: parent.width
            height: 32
            text: I18n.tr("Plugin Center…")
            onClicked: root.centerRequested()
        }
    }
    Rectangle {
        visible: !root.compact
        x: sidebar.x + sidebar.width + 12
        y: 0
        width: 1
        height: parent.height - footer.height
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08)
    }
    ListView {
        id: previewList
        objectName: "widget-gallery-previews"
        x: root.compact ? 14 : sidebar.x + sidebar.width + 28
        interactive: !root.dragging
        y: root.compact ? sidebar.y + sidebar.height + 6 : 16
        width: Math.max(1, parent.width - x - 16)
        height: Math.max(1, parent.height - y - footer.height - 12)
        clip: true
        spacing: 24
        model: root.visible ? root.entries : []
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        delegate: Column {
            id: group
            required property var modelData
            width: previewList.width - 8
            spacing: 10
            Text {
                text: group.modelData.name
                textFormat: Text.PlainText
                color: root.ink
                font { pixelSize: 13; weight: Font.DemiBold }
            }
            Flow {
                width: parent.width
                spacing: 12
                Repeater {
                    model: group.modelData.sizes
                    delegate: Item {
                        id: choice
                        required property string modelData
                        readonly property var entry: group.modelData
                        readonly property var span: WidgetRegistry.sizeSpan(modelData)
                        readonly property int count: Math.max(1, Math.min(3, Math.floor((group.width + 12) / 150)))
                        width: (group.width - (count - 1) * 12) / count
                        height: 230
                        readonly property bool blocked: !!entry.pluginId && entry.present && !entry.multiInstance
                        readonly property string existingId: {
                            for (const item of PluginWidgetService.instances)
                                if (item.pluginId === entry.pluginId && item.widgetId === entry.widgetId) return item.id
                            return ""
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: pointer.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04) : "transparent"
                            border.width: choice.activeFocus ? 2 : 0
                            border.color: "#007aff"
                        }
                        Item {
                            id: previewBox
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            height: 148
                            // The real builtin content is scaled as a single disabled
                            // tree, including the same small/medium/large layouts.
                            Loader {
                                id: builtin
                                property string previewWidgetId: choice.entry.widgetId
                                property int previewColumns: choice.span[0]
                                property int previewRows: choice.span[1]
                                // Lay out the authored desktop content at a full
                                // logical cell size, independent of this output's
                                // compact desktop grid, then shrink the whole tree.
                                readonly property real previewCellSize: Math.max(180, root.desktopCellSize)
                                readonly property real naturalWidth: previewColumns * previewCellSize + (previewColumns - 1) * root.desktopGap
                                readonly property real naturalHeight: previewRows * previewCellSize + (previewRows - 1) * root.desktopGap
                                active: !choice.entry.pluginId
                                sourceComponent: root.builtinPreview
                                width: naturalWidth
                                height: naturalHeight
                                scale: Math.min(previewBox.width / naturalWidth, (choice.modelData === "large" ? 148 : 78) / naturalHeight)
                                x: (previewBox.width - naturalWidth) / 2
                                y: (previewBox.height - naturalHeight) / 2
                                enabled: false
                            }
                            Rectangle {
                                visible: !!choice.entry.pluginId
                                anchors.centerIn: parent
                                width: Math.min(parent.width, choice.span[0] * 78 + (choice.span[0] - 1) * 8)
                                height: choice.modelData === "large" ? 148 : 78
                                radius: 12
                                color: AppearanceTokens.colors.layer1
                                border { width: 1; color: AppearanceTokens.colors.outlineVariant }
                                clip: true
                                Loader {
                                    anchors.fill: parent
                                    active: !!choice.existingId
                                    sourceComponent: Component {
                                        PluginWidgetView { instanceId: choice.existingId; interactive: false }
                                    }
                                }
                                Text {
                                    anchors { fill: parent; margins: 10 }
                                    visible: !choice.existingId
                                    text: choice.entry.name
                                    textFormat: Text.PlainText
                                    color: root.ink
                                    font { pixelSize: 12; weight: Font.DemiBold }
                                    wrapMode: Text.WordWrap
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; top: previewBox.bottom; topMargin: 10 }
                            text: root.sizeName(choice.modelData)
                            color: root.ink
                            horizontalAlignment: Text.AlignHCenter
                            font { pixelSize: 11; weight: Font.DemiBold }
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; top: previewBox.bottom; topMargin: 27; margins: 6 }
                            text: choice.blocked ? I18n.tr("Already on Desktop") : choice.entry.description
                            textFormat: Text.PlainText
                            color: root.ink
                            opacity: 0.65
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: 10
                        }
                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: entry.name + ", " + root.sizeName(modelData)
                        Keys.onReturnPressed: if (!blocked) root.addRequested(entry, modelData)
                        Keys.onSpacePressed: if (!blocked) root.addRequested(entry, modelData)
                        MouseArea {
                            id: pointer
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            preventStealing: true
                            property point origin
                            property bool moving: false
                            onPressed: mouse => {
                                origin = Qt.point(mouse.x, mouse.y)
                                moving = false
                                choice.forceActiveFocus()
                            }
                            onPositionChanged: mouse => {
                                if (!pressed || choice.blocked) return
                                if (!moving && Math.hypot(mouse.x - origin.x, mouse.y - origin.y) < Qt.styleHints.startDragDistance) return
                                moving = true
                                root.dragging = true
                                const point = mapToItem(root, mouse.x, mouse.y)
                                root.dragMoved(choice.entry, choice.modelData, point.x, point.y)
                            }
                            onReleased: mouse => {
                                if (moving && root.dragging) {
                                    const point = mapToItem(root, mouse.x, mouse.y)
                                    root.dragReleased(choice.entry, choice.modelData, point.x, point.y)
                                } else if (!moving && !choice.blocked) root.addRequested(choice.entry, choice.modelData)
                                moving = false
                                root.dragging = false
                            }
                            onCanceled: {
                                moving = false
                                root.dragging = false
                                root.dragCancelled()
                            }
                        }
                    }
                }
            }
        }
        Text {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 24 }
            visible: previewList.count === 0
            text: I18n.tr("No widgets found. Try another search or visit Plugin Center.")
            color: root.ink
            opacity: 0.65
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 13
        }
    }
    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 50
        Text {
            anchors { left: parent.left; right: doneButton.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 14 }
            text: root.feedback || I18n.tr("Click a widget or drag it onto the desktop.")
            textFormat: Text.PlainText
            color: root.ink
            font { pixelSize: 11; weight: root.feedback ? Font.Normal : Font.DemiBold }
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        Controls.Button {
            id: doneButton
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 }
            width: 76; height: 28
            contentItem: Text {
                text: I18n.tr("Done")
                color: "white"
                font { pixelSize: 12; weight: Font.DemiBold }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 14
                color: doneButton.down ? "#0062cc" : "#007aff"
                border.width: doneButton.activeFocus ? 2 : 0
                border.color: "white"
            }
            onClicked: root.done()
        }
    }
    // Compact layouts expose the same install/manage entry through the menu.
    Controls.Menu {
        id: compactMenu
        Controls.MenuItem { text: I18n.tr("Plugin Center…"); onTriggered: root.centerRequested() }
    }
    Keys.onMenuPressed: compactMenu.popup()
}
