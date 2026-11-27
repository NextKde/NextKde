import QtQuick
import QtQuick.Controls as Controls
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/i18n"
import "../../../shared/qml/controls" as LiquidControls
import "WidgetCategories.mjs" as WidgetCategories
import "WidgetGalleryDiagnostics.mjs" as WidgetDiagnostics
import "WidgetLocalization.mjs" as WidgetLocalization

Rectangle {
    id: root
    property var catalog: []
    property var invalidPackages: []
    property var trippedPackages: []
    property var missingInstances: []
    property string selectedCategory: "all"
    property string query: ""
    property string feedback: ""
    property bool placementEnabled: false
    property bool loading: false
    readonly property bool compact: width < 600
    readonly property color ink: ThemeService.foregroundColor
    readonly property var _trippedList: WidgetDiagnostics.toList(root.trippedPackages)
    readonly property var _invalidList: WidgetDiagnostics.toList(root.invalidPackages)
    readonly property var _missingList: WidgetDiagnostics.toList(root.missingInstances)
    readonly property int unavailableCount: _trippedList.length + _invalidList.length + _missingList.length
    readonly property string previewThemeKey: WidgetPreviewCache.themeKeyFor(
        WidgetHostService.widgetAppearance,
        AppearanceTokens.surface.paintInQml,
        String(AppearanceTokens.colors.layer1),
        Screen.devicePixelRatio || 1
    )
    function _syncPreviewCache() {
        WidgetPreviewCache.syncCatalog(root.catalog, root._trippedList)
    }
    onCatalogChanged: root._syncPreviewCache()
    onTrippedPackagesChanged: root._syncPreviewCache()
    onVisibleChanged: if (!visible) WidgetPreviewCache.clearPendingRenders()
    Component.onCompleted: root._syncPreviewCache()
    // "dock" is a fixed category (the Dock's own built-in music/weather/
    // clock/metrics widgets, folded in from the retired DockComponentEditor)
    // rather than one derived from the addable catalog, so it is always
    // present even when the catalog is empty or still loading.
    readonly property var categories: {
        const _lang = I18n.language
        const result = [{id: "all", name: I18n.tr("All Widgets"), icon: ""}]
        const stdCats = WidgetCategories.buildSidebarCategories(root.publishedEntries, key => I18n.tr(key))
        for (let i = 0; i < stdCats.length; i++)
            result.push(stdCats[i])
        result.push({id: "dock", name: I18n.tr("Dock Widgets"), icon: ""})
        if (root.unavailableCount > 0)
            result.push({id: "unavailable", name: I18n.tr("Unavailable") + " (" + root.unavailableCount + ")", icon: ""})
        return result
    }
    function localized(entry, field) {
        return WidgetLocalization.localizedField(entry, field, I18n.language)
    }
    function supportsContainer(entry, containerName) {
        if (!entry || typeof entry !== "object") return false
        const raw = entry.containers
        if (raw == null || typeof raw === "string" || typeof raw.length !== "number" || raw.length === 0)
            return containerName === "desktop"
        for (let i = 0; i < raw.length; i++) {
            if (String(raw[i]) === containerName) return true
        }
        return false
    }
    signal addRequested(var entry, string size)
    signal reEnableRequested(string packageId)
    signal removeRetiredInstanceRequested(string instanceId)
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
        if (size != null && typeof size !== "string" && size.length === 2)
            return Number(size[0]) + "×" + Number(size[1])
        return I18n.tr(size === "small" ? "Small" : size === "large" ? "Large" : "Medium")
    }
    // Read every executable package's own declared sizes instead of assuming
    // fixed presets. Duck-type the nested arrays on `.length`: arrays that
    // crossed a QML property boundary may be Qt sequence wrappers where
    // Array.isArray() is false (see R9).
    function sizeChoices(entry) {
        if (!WidgetRegistry.canExecute(entry)
                || !WidgetRegistry.matchesActiveStyle(entry)) return []
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
        // Bind explicitly to activePackageStyle so switching shellStyle
        // immediately re-filters the gallery to matching packages.
        const styleFilter = WidgetRegistry.activePackageStyle
        const entries = []
        const choicesById = Object.create(null)
        for (const entry of root.catalog) {
            if (String(entry.style ?? "") !== styleFilter) continue
            if (!root.supportsContainer(entry, "desktop")) continue
            const defaultSize = entry.defaultSize
            if (defaultSize == null || typeof defaultSize === "string" || defaultSize.length !== 2) continue
            const choices = root.sizeChoices(entry)
            const defaultValue = Number(defaultSize[0]) + "x" + Number(defaultSize[1])
            if (!choices.some(choice => choice.value === defaultValue)) continue
            entries.push(entry)
            choicesById[entry.id] = choices
        }
        return { entries: entries, choicesById: choicesById }
    }
    readonly property var publishedEntries: publishedCatalog.entries
    readonly property var entries: {
        const _lang = I18n.language
        const needle = query.trim().toLocaleLowerCase()
        return root.publishedEntries.filter(entry => {
            const catId = WidgetCategories.normalizeCategory(entry.category)
            if (selectedCategory !== "all" && catId !== selectedCategory) return false
            if (!needle) return true
            const catLabel = I18n.tr(WidgetCategories.categoryLabelKey(catId))
            return (
                root.localized(entry, "name") + " " + (entry.name ?? "") + " "
                + root.localized(entry, "packageName") + " " + (entry.packageName ?? "") + " "
                + root.localized(entry, "description") + " " + (entry.description ?? "") + " "
                + catLabel + " " + catId
            ).toLocaleLowerCase().includes(needle)
        })
    }
    readonly property var groupedEntries: {
        const _lang = I18n.language
        return WidgetCategories.groupEntriesByPackage(
            root.entries,
            root.publishedCatalog.choicesById,
            (entry, field) => root.localized(entry, field),
            key => I18n.tr(key)
        )
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
        visible: root.selectedCategory !== "dock" && root.selectedCategory !== "unavailable"
        x: root.compact ? 14 : sidebar.x + sidebar.width + 28
        y: root.compact ? sidebar.y + sidebar.height + 6 : 16
        width: Math.max(1, parent.width - x - 16)
        height: Math.max(1, parent.height - y - footer.height - 12)
        clip: true
        spacing: 24
        cacheBuffer: 240
        model: root.visible ? root.groupedEntries : []
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        delegate: Column {
            id: group
            required property var modelData
            width: previewList.width - 8
            spacing: 10
            Text {
                text: String(group.modelData.title ?? "")
                textFormat: Text.PlainText
                color: root.ink
                font { pixelSize: 13; weight: Font.DemiBold }
            }
            Flow {
                width: parent.width
                spacing: 12
                Repeater {
                    model: group.modelData.items ?? []
                    delegate: Item {
                        id: choice
                        required property var modelData
                        readonly property var entry: choice.modelData.entry
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
                        readonly property real previewScale: 0.5
                        readonly property real previewWidth: cols * cellUnit + (cols - 1) * cellGap
                        readonly property real previewHeight: rows * cellUnit + (rows - 1) * cellGap
                        width: Math.max(previewWidth + 16, choice.modelData.showSubName ? 128 : 112)
                        height: previewHeight + 16 + Math.max(44, 28 + descriptionText.implicitHeight + 6)
                        readonly property bool blocked: !root.placementEnabled || !!entry.present
                        readonly property string sizeValue: String(modelData.value ?? "")
                        readonly property bool isDefaultSize: {
                            const ds = choice.entry.defaultSize
                            if (ds != null && typeof ds !== "string" && ds.length === 2)
                                return (Number(ds[0]) + "x" + Number(ds[1])) === choice.sizeValue
                            return false
                        }
                        readonly property string slotKey: WidgetPreviewCache.slotKeyFor(String(choice.entry.id ?? ""), choice.sizeValue)
                        readonly property string desiredFileName: WidgetPreviewCache.fileNameFor(
                            String(choice.entry.id ?? ""),
                            String(choice.entry.revision ?? ""),
                            choice.sizeValue,
                            root.previewThemeKey
                        )
                        readonly property var cacheResolution: WidgetPreviewCache.resolve(choice.slotKey, choice.desiredFileName)
                        readonly property bool hasExactCache: cacheResolution.status === "hit" && cacheResolution.exactUrl.length > 0
                        readonly property bool hasFallbackCache: cacheResolution.status === "stale" && cacheResolution.fallbackUrl.length > 0
                        property bool _renderFailed: false
                        readonly property bool needsRender: root.visible && previewList.visible
                            && !choice.hasExactCache && !choice._renderFailed && choice.desiredFileName.length > 0
                        readonly property bool renderGranted: WidgetPreviewCache.isRenderGranted(choice.slotKey, choice.desiredFileName)
                        function _syncRenderQueue() {
                            if (choice.needsRender)
                                WidgetPreviewCache.requestRender(choice.slotKey, choice.desiredFileName, choice.isDefaultSize)
                            else
                                WidgetPreviewCache.releaseRender(choice.slotKey)
                        }
                        onDesiredFileNameChanged: {
                            choice._renderFailed = false
                            choice._syncRenderQueue()
                        }
                        onNeedsRenderChanged: choice._syncRenderQueue()
                        Component.onCompleted: choice._syncRenderQueue()
                        Component.onDestruction: WidgetPreviewCache.releaseRender(choice.slotKey)

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
                            clip: true
                            Image {
                                id: cachedPreviewImage
                                anchors.fill: parent
                                z: 1
                                source: choice.hasExactCache
                                    ? choice.cacheResolution.exactUrl
                                    : (choice.hasFallbackCache ? choice.cacheResolution.fallbackUrl : "")
                                visible: source.toString().length > 0 && status === Image.Ready && !choice._renderFailed
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                asynchronous: true
                                cache: false
                                onStatusChanged: {
                                    if (status === Image.Ready && choice.hasExactCache) {
                                        WidgetPreviewCache.touch(choice.slotKey)
                                    } else if (status === Image.Error && source.toString().length > 0) {
                                        const badFile = choice.hasExactCache
                                            ? choice.cacheResolution.exactFileName
                                            : choice.cacheResolution.fallbackFileName
                                        if (badFile) WidgetPreviewCache.invalidateFile(choice.slotKey, badFile)
                                    }
                                }
                            }
                            Loader {
                                id: livePreviewLoader
                                active: choice.renderGranted || choice._renderFailed
                                x: 0
                                y: (cachedPreviewImage.visible && !choice._renderFailed) ? (previewBox.height + 32) : 0
                                width: previewBox.width
                                height: previewBox.height
                                sourceComponent: Item {
                                    id: captureSurface
                                    width: previewBox.width
                                    height: previewBox.height
                                    property int _captureToken: 0
                                    readonly property string targetFile: choice.desiredFileName
                                    readonly property var previewHost: previewCard.loadedContent ?? null
                                    readonly property bool previewReady: Boolean(previewHost && previewHost.ready)
                                    readonly property bool previewFailed: Boolean(previewHost && previewHost.failed)
                                    readonly property bool shouldCapture: previewReady
                                        && WidgetPreviewCache.dirReady
                                        && !choice.hasExactCache
                                        && !choice._renderFailed
                                    onTargetFileChanged: {
                                        _captureToken++
                                        if (shouldCapture) captureTimer.restart()
                                    }
                                    onShouldCaptureChanged: {
                                        if (shouldCapture) captureTimer.restart()
                                        else captureTimer.stop()
                                    }
                                    DeskWidgetCard {
                                        id: previewCard
                                        x: 0
                                        y: 0
                                        width: choice.previewWidth / choice.previewScale
                                        height: choice.previewHeight / choice.previewScale
                                        transformOrigin: Item.TopLeft
                                        scale: choice.previewScale
                                        preview: true
                                        readonly property var _bgSpec: previewCard.loadedContent ? (previewCard.loadedContent.backgroundSpec ?? null) : null
                                        startColor: _bgSpec?.startColor ?? "#536783"
                                        hasMidColor: _bgSpec?.midColor !== undefined
                                            && _bgSpec?.midColor !== null
                                            && String(_bgSpec.midColor).length > 0
                                        midColor: hasMidColor ? _bgSpec.midColor : "transparent"
                                        midPosition: _bgSpec?.midPosition !== undefined
                                            ? Number(_bgSpec.midPosition) : 0.5
                                        endColor: _bgSpec?.endColor ?? "#35465f"
                                        gradientOrientation: _bgSpec?.orientation === "horizontal"
                                            ? Gradient.Horizontal : Gradient.Vertical
                                        showSurface: Boolean(_bgSpec)
                                        materialSurfaceColor: AppearanceTokens.colors.layer1
                                        materialSurfaceShape: choice.entry.style === "material" && previewCard.loadedContent
                                            ? String(previewCard.loadedContent.surfaceShape || "roundedRect")
                                            : "roundedRect"
                                        contentComponent: Component {
                                            WidgetPreviewHost {
                                                packageId: String(choice.entry.id ?? "")
                                                widgetEntry: String(choice.entry.widgetEntry ?? "")
                                                snapshotEntry: String(choice.entry.snapshotEntry ?? "")
                                                packageRevision: String(choice.entry.revision ?? "")
                                                widgetSize: choice.modelData.span
                                                appearance: WidgetHostService.widgetAppearance
                                                onFailedChanged: {
                                                    if (failed) {
                                                        captureTimer.stop()
                                                        choice._renderFailed = true
                                                        WidgetPreviewCache.releaseRender(choice.slotKey)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Timer {
                                        id: captureTimer
                                        interval: 80
                                        repeat: false
                                        running: captureSurface.shouldCapture && !captureSurface.previewFailed
                                        onTriggered: {
                                            if (!captureSurface.shouldCapture || captureSurface.previewFailed) return
                                            const token = ++captureSurface._captureToken
                                            const fileName = captureSurface.targetFile
                                            const outPath = WidgetPreviewCache.filePathFor(fileName)
                                            if (!outPath) {
                                                WidgetPreviewCache.releaseRender(choice.slotKey)
                                                return
                                            }
                                            const dpr = Math.max(1, Number(Screen.devicePixelRatio || 1))
                                            const targetSize = Qt.size(
                                                Math.max(1, Math.round(captureSurface.width * dpr)),
                                                Math.max(1, Math.round(captureSurface.height * dpr))
                                            )
                                            const widgetId = String(choice.entry.id ?? "")
                                            const packageId = String(choice.entry.packageId ?? choice.entry.id ?? "")
                                            const sizeValue = choice.sizeValue
                                            const isDefault = choice.isDefaultSize
                                            const rev = String(choice.entry.revision ?? "")
                                            const themeKey = root.previewThemeKey
                                            const slotKey = choice.slotKey
                                            const ok = captureSurface.grabToImage(function(result) {
                                                if (token !== captureSurface._captureToken || fileName !== choice.desiredFileName)
                                                    return
                                                if (result && result.saveToFile(outPath)) {
                                                    WidgetPreviewCache.commit({
                                                        widgetId: widgetId,
                                                        packageId: packageId,
                                                        sizeValue: sizeValue,
                                                        isDefaultSize: isDefault,
                                                        fileName: fileName,
                                                        revision: rev,
                                                        themeKey: themeKey
                                                    })
                                                } else {
                                                    WidgetPreviewCache.releaseRender(slotKey)
                                                }
                                            }, targetSize)
                                            if (!ok) WidgetPreviewCache.releaseRender(slotKey)
                                        }
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
                            x: Math.max(4, previewBox.x - 4); y: 4
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
                            anchors { left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4; top: previewBox.bottom; topMargin: 10 }
                            text: choice.modelData.label
                            color: root.ink
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font { pixelSize: 11; weight: Font.DemiBold }
                        }
                        Text {
                            id: descriptionText
                            anchors { left: parent.left; right: parent.right; top: previewBox.bottom; topMargin: 27; margins: 6 }
                            text: choice.entry.present ? I18n.tr("Already on Desktop") : root.localized(choice.entry, "description")
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
                        Accessible.name: root.localized(entry, "name") + ", " + modelData.label
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
    // "Dock Widgets" category — every Dock card is an installed package that
    // declares containers: ["dock"], keyed by dockCardId. Reuses
    // ConfigService.infoCardOrder/add|remove|moveInfoCard (the Dock's own
    // state, unchanged) behind this panel's own styling instead of that
    // popup's Material-token chrome, so it reads as part of this surface
    // rather than a second UI pasted in.
    Flickable {
        id: dockWidgetsPanel
        objectName: "widget-gallery-dock-widgets"
        visible: root.selectedCategory === "dock"
        x: previewList.x
        y: previewList.y
        width: previewList.width
        height: previewList.height
        clip: true
        contentWidth: width
        contentHeight: dockContentCol.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        readonly property var dockPackageMap: {
            const map = Object.create(null)
            for (const entry of (root.catalog ?? [])) {
                if (!WidgetRegistry.canExecute(entry) || !WidgetRegistry.matchesActiveStyle(entry))
                    continue
                if (!root.supportsContainer(entry, "dock"))
                    continue
                const cardId = String(entry.dockCardId || entry.id)
                if (!map[cardId]) map[cardId] = entry
            }
            return map
        }
        readonly property var displayIds: {
            const active = []
            for (const id of ConfigService.infoCardOrder) {
                if (!!dockPackageMap[id])
                    active.push(id)
            }
            for (const id of Object.keys(dockPackageMap))
                if (active.indexOf(id) < 0) active.push(id)
            return active
        }

        Column {
            id: dockContentCol
            width: dockWidgetsPanel.width - 10
            spacing: 12

            Column {
                width: parent.width
                spacing: 4
                Text {
                    id: dockWidgetsTitle
                    text: I18n.tr("Dock Widgets")
                    color: root.ink
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    text: I18n.tr("Tap to add or remove, drag to reorder.")
                    color: root.ink
                    opacity: 0.65
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            Flow {
                id: dockCardFlow
                width: parent.width
                spacing: 12

                Repeater {
                    model: dockWidgetsPanel.displayIds
                    delegate: Rectangle {
                        id: dockCard
                        required property string modelData
                        required property int index
                        readonly property var pkgEntry: dockWidgetsPanel.dockPackageMap[modelData] ?? null
                        readonly property int units: pkgEntry
                            ? Math.max(2, Math.min(4, Number(pkgEntry.dockUnits) || 4)) : 3
                        readonly property bool active: ConfigService.infoCardOrder.indexOf(modelData) >= 0
                        readonly property int activeIndex: ConfigService.infoCardOrder.indexOf(modelData)
                        readonly property bool hasPopup: Boolean(pkgEntry
                            && pkgEntry.hasPopup && String(pkgEntry.popupEntry || "").length > 0)
                        property real dragOffset: 0

                        width: Math.max(156, units * 46 + 24)
                        height: 110
                        radius: 16
                        z: dockReorderDrag.active ? 10 : 0
                        scale: dockReorderDrag.active ? 1.04 : 1
                        transform: Translate { x: dockCard.dragOffset }
                        color: active ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.10)
                            : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.04)
                        border.width: active ? 2 : 1
                        border.color: active ? "#007aff" : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
                        opacity: active ? 1 : 0.72

                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        // Live Dock strip preview slot
                        Rectangle {
                            id: dockSlotPreview
                            anchors {
                                left: parent.left; right: parent.right
                                top: parent.top; margins: 8
                            }
                            height: 56
                            radius: 14
                            clip: true
                            readonly property var spec: dockPreviewLoader.item
                                ? dockPreviewLoader.item.backgroundSpec : null
                            readonly property bool paintGradient: !AppearanceTokens.isMaterial
                                && !!spec && !WidgetHostService.widgetAppearance.transparent
                            color: paintGradient ? "transparent"
                                : (AppearanceTokens.isMaterial
                                    ? Qt.rgba(AppearanceTokens.colors.layer2.r,
                                        AppearanceTokens.colors.layer2.g,
                                        AppearanceTokens.colors.layer2.b, 0.82)
                                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08))
                            gradient: paintGradient ? dockSlotGradient : null
                            Gradient {
                                id: dockSlotGradient
                                orientation: dockSlotPreview.spec?.orientation === "horizontal"
                                    ? Gradient.Horizontal : Gradient.Vertical
                                GradientStop { position: 0; color: dockSlotPreview.spec?.startColor ?? "transparent" }
                                GradientStop {
                                    position: Math.max(0.01, Math.min(0.99,
                                        dockSlotPreview.spec?.midPosition !== undefined
                                            ? Number(dockSlotPreview.spec.midPosition) : 0.5))
                                    color: {
                                        const s = dockSlotPreview.spec
                                        if (!s) return "transparent"
                                        const m = s.midColor
                                        if (m !== undefined && m !== null && String(m).length > 0) return m
                                        const sc = Qt.color(String(s.startColor ?? "transparent"))
                                        const ec = Qt.color(String(s.endColor ?? "transparent"))
                                        return Qt.rgba((sc.r + ec.r) * 0.5, (sc.g + ec.g) * 0.5,
                                            (sc.b + ec.b) * 0.5, (sc.a + ec.a) * 0.5)
                                    }
                                }
                                GradientStop { position: 1; color: dockSlotPreview.spec?.endColor ?? "transparent" }
                            }

                            Loader {
                                id: dockPreviewLoader
                                anchors.fill: parent
                                anchors.margins: 4
                                active: root.visible && root.selectedCategory === "dock"
                                    && Boolean(dockCard.pkgEntry)
                                sourceComponent: Component {
                                    WidgetPreviewHost {
                                        packageId: String(dockCard.pkgEntry?.id ?? "")
                                        widgetEntry: String(dockCard.pkgEntry?.widgetEntry ?? "")
                                        snapshotEntry: String(dockCard.pkgEntry?.snapshotEntry ?? "")
                                        packageRevision: String(dockCard.pkgEntry?.revision ?? "")
                                        containerType: "dock"
                                        containerOrientation: "horizontal"
                                        widgetSize: [dockCard.units, 1]
                                        appearance: WidgetHostService.widgetAppearance
                                    }
                                }
                            }
                        }

                        // Title + optional Popup preview pill on bottom row
                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                bottom: parent.bottom; margins: 8; bottomMargin: 7
                            }
                            height: 26
                            spacing: 6

                            Text {
                                width: Math.max(1, parent.width
                                    - (popupPreviewBtn.visible ? popupPreviewBtn.width + 6 : 0))
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: dockCard.pkgEntry
                                    ? (root.localized(dockCard.pkgEntry, "name") || dockCard.modelData)
                                    : dockCard.modelData
                                color: root.ink
                                font { pixelSize: 11; weight: Font.DemiBold }
                            }

                            Rectangle {
                                id: popupPreviewBtn
                                visible: dockCard.hasPopup
                                anchors.verticalCenter: parent.verticalCenter
                                width: popupBtnLabel.implicitWidth + 14
                                height: 22
                                radius: 11
                                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
                                Text {
                                    id: popupBtnLabel
                                    anchors.centerIn: parent
                                    text: I18n.tr("Popup")
                                    color: root.ink
                                    font { pixelSize: 10; weight: Font.DemiBold }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        mouse.accepted = true
                                        dockPopupPreview.pkgEntry = dockCard.pkgEntry
                                        dockPopupPreview.units = dockCard.units
                                        dockPopupPreview.open()
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 4 }
                            width: 20; height: 20; radius: 10
                            color: dockCard.active ? "#ff453a" : "#007aff"
                            BundledIcon {
                                anchors.centerIn: parent
                                name: dockCard.active ? "dock.widget.remove" : "dock.widget.add"
                                color: "white"
                                size: 14
                            }
                        }

                        TapHandler {
                            enabled: !dockReorderDrag.active
                            onTapped: function(eventPoint) {
                                if (popupPreviewBtn.visible) {
                                    const pt = popupPreviewBtn.mapFromItem(dockCard,
                                        eventPoint.position.x, eventPoint.position.y)
                                    if (popupPreviewBtn.contains(pt))
                                        return
                                }
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
                width: parent.width
                topPadding: 10
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

        Controls.Popup {
            id: dockPopupPreview
            property var pkgEntry: null
            property int units: 4
            readonly property real rawDesiredHeight: galleryPopupHost.preferredContentHeight > 0
                ? galleryPopupHost.preferredContentHeight : 160
            readonly property int clampedHeight: Math.round(
                Math.max(72, Math.min(480, rawDesiredHeight)))
            parent: Controls.Overlay.overlay
            anchors.centerIn: parent
            width: 300
            height: clampedHeight
            padding: 0
            modal: true
            focus: true
            closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside
            background: Rectangle {
                radius: 18
                color: AppearanceTokens.isMaterial
                    ? AppearanceTokens.colors.layer1
                    : (ThemeService.isDark ? Qt.rgba(0.14, 0.16, 0.20, 0.94) : Qt.rgba(0.96, 0.97, 0.99, 0.96))
                border.width: 1
                border.color: AppearanceTokens.isMaterial
                    ? AppearanceTokens.colors.outlineVariant
                    : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
            }
            contentItem: Flickable {
                id: galleryPopupFlick
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: Math.max(height, Math.round(dockPopupPreview.rawDesiredHeight))
                interactive: contentHeight > height + 1
                WidgetPreviewHost {
                    id: galleryPopupHost
                    x: 0
                    y: 0
                    width: galleryPopupFlick.width
                    height: galleryPopupFlick.contentHeight
                    useImplicitHeight: true
                    packageId: dockPopupPreview.opened && dockPopupPreview.pkgEntry
                        ? String(dockPopupPreview.pkgEntry.id ?? "") : ""
                    widgetEntry: dockPopupPreview.opened && dockPopupPreview.pkgEntry?.hasPopup
                        ? String(dockPopupPreview.pkgEntry.popupEntry ?? "") : ""
                    snapshotEntry: dockPopupPreview.opened && dockPopupPreview.pkgEntry
                        ? String(dockPopupPreview.pkgEntry.snapshotEntry ?? "") : ""
                    packageRevision: String(dockPopupPreview.pkgEntry?.revision ?? "")
                    containerType: "dock"
                    containerOrientation: "horizontal"
                    widgetSize: [dockPopupPreview.units, 1]
                    appearance: {
                        const base = WidgetHostService.widgetAppearance
                        return Object.assign({}, base, {
                            foreground: ThemeService.foregroundColor,
                            palette: AppearanceTokens.isMaterial ? (base.palette ?? ({})) : ({})
                        })
                    }
                }
            }
        }
    }
    Flickable {
        id: unavailablePanel
        objectName: "widget-gallery-unavailable"
        visible: root.selectedCategory === "unavailable"
        x: previewList.x
        y: previewList.y
        width: previewList.width
        height: previewList.height
        clip: true
        contentWidth: width
        contentHeight: unavailableColumn.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

        Column {
            id: unavailableColumn
            width: unavailablePanel.width - 10
            spacing: 16

            Column {
                width: parent.width
                spacing: 8
                visible: root._trippedList.length > 0
                Text {
                    text: I18n.tr("Paused After Crash")
                    color: root.ink
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
                Repeater {
                    model: root._trippedList
                    delegate: Rectangle {
                        required property var modelData
                        width: unavailableColumn.width
                        height: Math.max(54, trippedInfo.implicitHeight + 20)
                        radius: 10
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)

                        Column {
                            id: trippedInfo
                            anchors { left: parent.left; right: reEnableBtn.left; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 2
                            Text {
                                width: parent.width
                                text: String(modelData.id ?? "")
                                textFormat: Text.PlainText
                                color: root.ink
                                font { pixelSize: 12; weight: Font.DemiBold }
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: I18n.tr("上次加载时导致桌面崩溃，已自动暂停")
                                textFormat: Text.PlainText
                                color: root.ink
                                opacity: 0.7
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                        Controls.Button {
                            id: reEnableBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                            width: 84; height: 28
                            contentItem: Text {
                                text: I18n.tr("Re-enable")
                                color: "white"
                                font { pixelSize: 11; weight: Font.DemiBold }
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 14
                                color: reEnableBtn.down ? "#0062cc" : "#007aff"
                            }
                            onClicked: root.reEnableRequested(String(modelData.id ?? ""))
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 8
                visible: root._invalidList.length > 0
                Text {
                    text: I18n.tr("Incompatible or Invalid Packages")
                    color: root.ink
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
                Repeater {
                    model: root._invalidList
                    delegate: Rectangle {
                        required property var modelData
                        width: unavailableColumn.width
                        height: invalidInfo.implicitHeight + 20
                        radius: 10
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)

                        Column {
                            id: invalidInfo
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 3
                            Text {
                                width: parent.width
                                text: String(modelData.id ?? "") + (modelData.code ? ("  [" + modelData.code + "]") : "")
                                textFormat: Text.PlainText
                                color: root.ink
                                font { pixelSize: 12; weight: Font.DemiBold }
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: WidgetDiagnostics.friendlyReason(modelData.code, modelData.reason)
                                textFormat: Text.PlainText
                                color: root.ink
                                opacity: 0.85
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                width: parent.width
                                visible: String(modelData.reason ?? "").length > 0 || String(modelData.path ?? "").length > 0
                                text: String(modelData.reason ?? "") + (modelData.path ? ("\n" + modelData.path) : "")
                                textFormat: Text.PlainText
                                color: root.ink
                                opacity: 0.55
                                font.pixelSize: 10
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 8
                visible: root._missingList.length > 0
                Text {
                    text: I18n.tr("Unavailable Desktop Widgets")
                    color: root.ink
                    font { pixelSize: 13; weight: Font.DemiBold }
                }
                Repeater {
                    model: root._missingList
                    delegate: Rectangle {
                        required property var modelData
                        width: unavailableColumn.width
                        height: Math.max(54, missingInfo.implicitHeight + 20)
                        radius: 10
                        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)

                        Column {
                            id: missingInfo
                            anchors { left: parent.left; right: removeMissingBtn.left; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 2
                            Text {
                                width: parent.width
                                text: String(modelData.packageId ?? modelData.id ?? "") + "  (" + String(modelData.id ?? "") + ")"
                                textFormat: Text.PlainText
                                color: root.ink
                                font { pixelSize: 12; weight: Font.DemiBold }
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: String(modelData.summary ?? "")
                                textFormat: Text.PlainText
                                color: root.ink
                                opacity: 0.7
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }
                        Controls.Button {
                            id: removeMissingBtn
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                            width: 92; height: 28
                            contentItem: Text {
                                text: I18n.tr("Remove")
                                color: "white"
                                font { pixelSize: 11; weight: Font.DemiBold }
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                radius: 14
                                color: removeMissingBtn.down ? "#d6352c" : "#ff453a"
                            }
                            onClicked: root.removeRetiredInstanceRequested(String(modelData.id ?? ""))
                        }
                    }
                }
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
                : root.selectedCategory === "unavailable"
                    ? I18n.tr("Review paused or incompatible widgets, re-enable or clean up unused records.")
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
