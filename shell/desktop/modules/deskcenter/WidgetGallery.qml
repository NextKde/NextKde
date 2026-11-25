import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"
import "../../../shared/qml/controls" as LiquidControls
import "bundled-clock" as Clock

Rectangle {
    id: root
    property var catalog: []
    property string selectedCategory: "all"
    property string query: ""
    property string feedback: ""
    property bool placementEnabled: false
    property bool loading: false
    readonly property bool compact: width < 600
    readonly property color ink: ThemeService.foregroundColor
    // "dock" is a fixed category (the Dock's own built-in music/weather/
    // clock/metrics widgets, folded in from the retired DockComponentEditor)
    // rather than one derived from the addable catalog, so it is always
    // present even when the catalog is empty or still loading.
    readonly property var categories: {
        const result = [{id: "all", name: I18n.tr("All Widgets"), icon: ""}]
        for (const entry of root.publishedEntries) {
            if (entry.category && !result.some(item => item.id === entry.category))
                result.push({id: entry.category, name: entry.categoryName, icon: ""})
        }
        result.push({id: "dock", name: I18n.tr("Dock Widgets"), icon: ""})
        return result
    }
    signal addRequested(var entry, string size)
    signal done()
    objectName: "widget-library"
    radius: 0
    color: "transparent"
    clip: true
    readonly property real cornerRadius: Math.min(
        AppearanceTokens.surface.pick(AppearanceTokens.shape.extraLarge, 28), width / 2, height / 2)
    readonly property var blurRegion: glass.blurRegion || null
    // DIAGNOSTIC (temporary): blurAnchor reverted to the simple, proven
    // `root` pattern used elsewhere, sacrificing the square-bottom-corner
    // overshoot. Isolates whether the base material renders at all before
    // re-introducing the shapeAnchor coordinate trick.
    // Same liquid-glass recipe as the app launcher panel (same blur and
    // background intensity), see AppLauncherWindow.qml's launcherSurface.
    LiquidGlassPanel {
        id: glass
        objectName: "widget-library-glass"
        width: root.width
        height: root.height
        blurAnchor: root
        radius: root.cornerRadius
        cornerExponent: 2.35
        blurSigma: tonal ? -1 : Math.max(6, 18 * AppearanceConfigService.effectiveLauncherBlur)
        // This panel sits on WlrLayer.Bottom (see DeskCenterWindow), so it
        // only samples the wallpaper behind it rather than the full desktop
        // an Overlay-layer popup like the launcher sees. Compensate for the
        // thinner backdrop with a deeper base tint and popup-level depth,
        // rather than chasing the launcher's exact blurSigma/scrimLevel.
        materialDepth: 1
        baseColor: Qt.rgba(0, 0, 0, 0.22)
        scrimEnabled: AppearanceTokens.surface.usesBackdrop
        scrimLevel: "transparent"
        scrimOpacity: 1
    }
    Keys.onEscapePressed: root.done()
    function begin() {
        if (!visible) return
        search.forceActiveFocus()
    }
    function sizeName(size) {
        if (Array.isArray(size)) return size[0] + "×" + size[1]
        return I18n.tr(size === "small" ? "Small" : size === "large" ? "Large" : "Medium")
    }
    // First integrated SDK preview: execute only packages the host actually
    // maps to a view (WidgetRegistry.executablePackages). Index discovery
    // alone must never authorize arbitrary installed QML.
    Clock.Snapshot { id: clockSnapshot }
    // Read every executable package's own declared sizes instead of assuming
    // the example clock's 2x2/3x2 pair. Duck-type the nested arrays on
    // `.length`: arrays that crossed a QML property boundary may be Qt
    // sequence wrappers where Array.isArray() is false (see R9).
    function sizeChoices(entry) {
        if (entry.available !== true || !WidgetRegistry.canExecute(entry.id)) return []
        const choices = []
        const sizes = entry.sizes ?? []
        for (let i = 0; i < sizes.length; i++) {
            const span = sizes[i]
            if (span == null || span.length !== 2) continue
            const columns = Number(span[0])
            const rows = Number(span[1])
            if (!Number.isInteger(columns) || !Number.isInteger(rows)
                    || columns < 1 || columns > 4 || rows < 1 || rows > 4) continue
            const value = columns + "x" + rows
            if (choices.some(choice => choice.value === value)) continue
            choices.push({ value: value, span: [columns, rows], label: root.sizeName([columns, rows]) })
        }
        return choices
    }
    // Resolve sizes from the IPC catalog before entries cross the ListView's
    // model boundary. Delegates use the published choices by package ID.
    readonly property var publishedCatalog: {
        const entries = []
        const choicesById = Object.create(null)
        for (const entry of root.catalog) {
            if (!Array.isArray(entry.defaultSize)) continue
            const choices = root.sizeChoices(entry)
            const defaultValue = entry.defaultSize.join("x")
            if (!choices.some(choice => choice.value === defaultValue)) continue
            entries.push(entry)
            choicesById[entry.id] = choices
        }
        return { entries: entries, choicesById: choicesById }
    }
    readonly property var publishedEntries: publishedCatalog.entries
    readonly property var entries: {
        const needle = query.trim().toLocaleLowerCase()
        return root.publishedEntries.filter(entry =>
            (selectedCategory === "all" || entry.category === selectedCategory)
            && (!needle || (entry.name + " " + (entry.description ?? "") + " " + (entry.categoryName ?? "")).toLocaleLowerCase().includes(needle)))
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
            anchors { top: search.bottom; topMargin: 8; bottom: parent.bottom }
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
        visible: root.selectedCategory !== "dock"
        x: root.compact ? 14 : sidebar.x + sidebar.width + 28
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
                    model: root.publishedCatalog.choicesById[group.modelData.id] ?? []
                    delegate: Item {
                        id: choice
                        required property var modelData
                        readonly property var entry: group.modelData
                        // modelData.span has crossed this Repeater's model:
                        // boundary, which boxes a plain JS array field into a
                        // Qt sequence wrapper -- still indexable, but
                        // Array.isArray() on it is false. Duck-type on
                        // `.length` instead (see WidgetLayout.mjs's toArray).
                        readonly property bool hasSpan: !!modelData.span && modelData.span.length === 2
                        readonly property int cols: hasSpan ? modelData.span[0] : 1
                        readonly property int rows: hasSpan ? modelData.span[1] : 1
                        // A preview scales with the widget's own declared span
                        // instead of a uniform per-row tile size, so a 3x2
                        // choice visibly reads as wider than its 2x2 sibling
                        // (see docs/plugins — size choices must stay visually
                        // distinguishable, not just labeled differently).
                        readonly property real cellUnit: 76
                        readonly property real cellGap: 6
                        readonly property real previewWidth: cols * cellUnit + (cols - 1) * cellGap
                        readonly property real previewHeight: rows * cellUnit + (rows - 1) * cellGap
                        width: previewWidth + 16
                        height: previewHeight + 16 + 44
                        readonly property bool blocked: !root.placementEnabled || !!entry.present
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: pointer.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04) : "transparent"
                            border.width: choice.activeFocus ? 2 : 0
                            border.color: "#007aff"
                        }
                        Item {
                            id: previewBox
                            x: (parent.width - width) / 2
                            y: 8
                            width: choice.previewWidth
                            height: choice.previewHeight
                            readonly property var widgetAppearance: ({
                                isDark: AppearanceTokens.isDarkTheme,
                                foreground: AppearanceTokens.surface.widgetForeground,
                                transparent: AppearanceConfigService.widgetStyle === "glass"
                                    && !AppearanceTokens.surface.paintInQml
                            })
                            Clock.Widget {
                                id: previewWidget
                                anchors.fill: parent
                                data: clockSnapshot.getSnapshot(choice.modelData.span)
                                widgetSize: choice.modelData.span
                                appearance: previewBox.widgetAppearance
                            }
                            Loader {
                                anchors.fill: parent
                                z: -1
                                active: !!previewWidget.backgroundSpec
                                    && !(AppearanceConfigService.widgetStyle === "glass"
                                        && !AppearanceTokens.surface.paintInQml)
                                sourceComponent: Rectangle {
                                    radius: 14
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: previewWidget.backgroundSpec.startColor }
                                        GradientStop { position: 1; color: previewWidget.backgroundSpec.endColor }
                                    }
                                }
                            }
                        }
                        // Primary add affordance. Drag-to-desktop was dropped
                        // (too much surface for cross-window drag tracking to
                        // get right, see WidgetGalleryService) in favor of a
                        // single click target; clicking anywhere else on an
                        // unblocked card does the same thing, matching the
                        // previous whole-card click behavior.
                        Rectangle {
                            id: addBadge
                            visible: !choice.blocked
                            x: 4; y: 4
                            z: 2
                            width: 22; height: 22
                            radius: 11
                            color: addBadgeArea.containsMouse ? "#0062cc" : "#007aff"
                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                color: "white"
                                font { pixelSize: 14; weight: Font.DemiBold }
                            }
                            MouseArea {
                                id: addBadgeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.addRequested(choice.entry, choice.modelData.value)
                            }
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; top: previewBox.bottom; topMargin: 10 }
                            text: choice.modelData.label
                            color: root.ink
                            horizontalAlignment: Text.AlignHCenter
                            font { pixelSize: 11; weight: Font.DemiBold }
                        }
                        Text {
                            anchors { left: parent.left; right: parent.right; top: previewBox.bottom; topMargin: 27; margins: 6 }
                            text: choice.entry.present ? I18n.tr("Already on Desktop") : choice.entry.description
                            textFormat: Text.PlainText
                            color: root.ink
                            opacity: 0.65
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.pixelSize: 10
                        }
                        activeFocusOnTab: !blocked
                        Accessible.role: blocked ? Accessible.StaticText : Accessible.Button
                        Accessible.name: entry.name + ", " + modelData.label
                        Keys.onReturnPressed: if (!blocked) root.addRequested(entry, modelData.value)
                        Keys.onSpacePressed: if (!blocked) root.addRequested(entry, modelData.value)
                        MouseArea {
                            id: pointer
                            anchors.fill: parent
                            enabled: !choice.blocked
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            onClicked: {
                                choice.forceActiveFocus()
                                root.addRequested(choice.entry, choice.modelData.value)
                            }
                        }
                    }
                }
            }
        }
        Text {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 24 }
            visible: previewList.count === 0
            text: root.loading ? I18n.tr("Loading widgets…")
                : root.publishedEntries.length === 0 && !root.feedback ? I18n.tr("No widget previews available yet.")
                : root.publishedEntries.length > 0 ? I18n.tr("No widgets found. Try another search.") : ""
            color: root.ink
            opacity: 0.65
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 13
        }
    }
    // "Dock Widgets" category — folded in from the retired
    // DockComponentEditor.qml. Reuses ConfigService.infoCardOrder/
    // knownInfoCardIds/add|remove|moveInfoCard verbatim (the Dock's own
    // state, unchanged) behind this panel's own styling instead of that
    // popup's Material-token chrome, so it reads as part of this surface
    // rather than a second UI pasted in.
    Item {
        id: dockWidgetsPanel
        objectName: "widget-gallery-dock-widgets"
        visible: root.selectedCategory === "dock"
        x: previewList.x
        y: previewList.y
        width: previewList.width
        height: previewList.height

        readonly property var labels: ({
            music: I18n.tr("Music"), weather: I18n.tr("Weather"),
            clock: I18n.tr("Clock"), metrics: I18n.tr("System")
        })
        readonly property var displayIds: {
            const active = ConfigService.infoCardOrder.slice()
            for (const id of ConfigService.knownInfoCardIds)
                if (active.indexOf(id) < 0) active.push(id)
            return active
        }

        Text {
            id: dockWidgetsTitle
            anchors { left: parent.left; top: parent.top }
            text: I18n.tr("Dock Widgets")
            color: root.ink
            font { pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            anchors { left: parent.left; right: parent.right; top: dockWidgetsTitle.bottom; topMargin: 4 }
            text: I18n.tr("Tap to add or remove, drag to reorder.")
            color: root.ink
            opacity: 0.65
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Flow {
            id: dockCardFlow
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 48 }
            spacing: 12

            Repeater {
                model: dockWidgetsPanel.displayIds
                delegate: Rectangle {
                    id: dockCard
                    required property string modelData
                    required property int index
                    readonly property bool active: ConfigService.infoCardOrder.indexOf(modelData) >= 0
                    readonly property int activeIndex: ConfigService.infoCardOrder.indexOf(modelData)
                    property real dragOffset: 0

                    width: 96; height: 72
                    radius: 14
                    z: dockReorderDrag.active ? 10 : 0
                    scale: dockReorderDrag.active ? 1.06 : 1
                    transform: Translate { x: dockCard.dragOffset }
                    color: active ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
                        : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.035)
                    border.width: active ? 2 : 1
                    border.color: active ? "#007aff" : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
                    opacity: active ? 1 : 0.62

                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        BundledIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "dock.widget." + dockCard.modelData
                            color: root.ink
                            size: 22
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dockWidgetsPanel.labels[dockCard.modelData]
                            color: root.ink
                            font { pixelSize: 11; weight: Font.DemiBold }
                        }
                    }
                    Rectangle {
                        anchors { top: parent.top; right: parent.right; margins: 5 }
                        width: 20; height: 20; radius: 10
                        color: dockCard.active ? "#ff453a" : "#007aff"
                        BundledIcon {
                            anchors.centerIn: parent
                            name: dockCard.active ? "dock.widget.remove" : "dock.widget.add"
                            color: "white"
                            size: 15
                        }
                    }
                    TapHandler {
                        enabled: !dockReorderDrag.active
                        onTapped: {
                            if (dockCard.active) ConfigService.removeInfoCard(dockCard.modelData)
                            else ConfigService.addInfoCard(dockCard.modelData, ConfigService.infoCardOrder.length)
                        }
                    }
                    DragHandler {
                        id: dockReorderDrag
                        target: null
                        enabled: dockCard.active
                        xAxis.enabled: true
                        yAxis.enabled: false
                        onTranslationChanged: if (active) dockCard.dragOffset = translation.x
                        onActiveChanged: {
                            if (active) return
                            if (Math.abs(dockCard.dragOffset) < 8) { dockCard.dragOffset = 0; return }
                            const step = dockCard.width + dockCardFlow.spacing
                            const delta = Math.round(dockCard.dragOffset / step)
                            ConfigService.moveInfoCard(dockCard.modelData,
                                Math.max(0, Math.min(ConfigService.infoCardOrder.length - 1,
                                    dockCard.activeIndex + delta)))
                            dockCard.dragOffset = 0
                        }
                    }
                }
            }
        }

        Row {
            anchors { left: parent.left; right: parent.right; top: dockCardFlow.bottom; topMargin: 24 }
            spacing: 12
            Column {
                width: parent.width - autoRotateSwitch.width - 12
                spacing: 1
                Text {
                    width: parent.width
                    text: I18n.tr("Auto rotate")
                    color: root.ink
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    text: I18n.tr("When off, hover and scroll wheel still switch pages")
                    color: root.ink
                    opacity: 0.58
                    wrapMode: Text.WordWrap
                    font.pixelSize: 10
                }
            }
            LiquidControls.LiquidGlassSwitch {
                id: autoRotateSwitch
                implicitWidth: 58
                implicitHeight: 28
                checked: ConfigService.infoCardAutoRotate
                accentColor: "#007aff"
                trackColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.18)
                onToggled: enabled => ConfigService.updateInfoCardAutoRotate(enabled)
            }
        }
    }
    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 50
        Text {
            anchors { left: parent.left; right: doneButton.left; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 14 }
            text: root.feedback || (root.selectedCategory === "dock"
                ? I18n.tr("Tap a widget to add or remove it, drag to reorder.")
                : root.entries.length > 0
                    ? (root.placementEnabled ? I18n.tr("Click the + on a widget to add it to the desktop.")
                        : I18n.tr("Adding widgets to the desktop is not available yet.")) : "")
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
}
