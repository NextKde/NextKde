import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Focusable full-screen layer with a compact, centered window switcher.
PanelWindow {
    id: root

    // Distinguish this surface from other quickshell panels so the glass
    // plugin can give it its own highlight direction (kwin reads the
    // layer-shell namespace as the window class).
    WlrLayershell.namespace: "quickshell-quicksearch"

    property bool open: false
    property string mode: "window"
    property string viewMode: "list"
    property string query: ""
    property int selectedIndex: 0
    // Keep this deliberately minimal: QuickSearch is a high-frequency
    // shortcut surface, so a brief fade is clearer and faster than a sheet
    // transition or scale animation.
    property real revealProgress: open ? 1.0 : 0.0

    Behavior on revealProgress {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutCubic
        }
    }

    signal closeRequested
    signal modeCycleRequested
    signal viewModeToggleRequested

    readonly property string modeTitle: mode === "app" ? "应用" : (mode === "clipboard" ? "剪贴板" : "窗口")
    readonly property string placeholder: mode === "app" ? "搜索已安装的应用" : (mode === "clipboard" ? "搜索剪贴板历史" : "搜索已打开的窗口")

    readonly property var windowResults: {
        // Explicitly depend on the service revision so title, activation, and
        // window lifecycle changes immediately refresh the search results.
        WindowService.revision;
        const needle = query.trim().toLowerCase();
        const matches = [];
        const records = WindowService.records || [];
        for (let i = 0; i < records.length; i++) {
            const record = records[i];
            const haystack = (record.title + " " + (record.identity?.name ?? "") + " " + (record.identity?.desktopId ?? "")).toLowerCase();
            if (!needle || haystack.includes(needle))
                matches.push({
                    kind: "window",
                    title: record.title,
                    subtitle: record.identity?.name ?? record.identity?.desktopId ?? "",
                    icon: record.iconSource ?? "",
                    windowId: record.windowId
                });
        }
        matches.sort((left, right) => left.title.localeCompare(right.title));
        return matches;
    }
    readonly property var appResults: {
        AppPresentationService.catalogRevision;
        AppPresentationService.revision;
        const needle = query.trim().toLowerCase();
        const matches = [];
        const catalogue = AppPresentationService.catalog();
        for (let i = 0; i < catalogue.length; i++) {
            const presentation = catalogue[i];
            const title = presentation.displayName;
            const haystack = (title + " " + presentation.desktopId).toLowerCase();
            if (!needle || haystack.includes(needle)) {
                matches.push({
                    kind: "app",
                    title: title,
                    subtitle: presentation.desktopId,
                    icon: presentation.iconSource,
                    entry: presentation.entry
                });
            }
        }
        return matches;
    }
    readonly property var clipboardResults: {
        ClipboardService.revision;
        const needle = query.trim().toLowerCase();
        const matches = [];
        const entries = ClipboardService.entries || [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (!needle || entry.preview.toLowerCase().includes(needle)) {
                matches.push({
                    kind: "clipboard",
                    title: entry.isImage ? "图片" : entry.preview,
                    subtitle: entry.isImage ? "图片剪贴板 · " + entry.preview.slice(2, -2) : "文本剪贴板 · 回车复制",
                    icon: Quickshell.iconPath(entry.isImage ? "image-x-generic" : "edit-paste", true) || "",
                    isImage: entry.isImage,
                    selectionRecord: entry.record
                });
            }
        }
        return matches;
    }
    readonly property var results: mode === "app" ? appResults : (mode === "clipboard" ? clipboardResults : windowResults)
    readonly property int resultCount: results.length
    readonly property int visibleResultCount: Math.min(6, resultCount)
    readonly property int gridColumnCount: 5
    readonly property int visibleGridRowCount: Math.min(3, Math.ceil(resultCount / gridColumnCount))

    visible: open
    color: "transparent"
    focusable: true
    // Blur only the compact search card; the rest of the screen remains an
    // untouched, transparent Spotlight-style surface.
    BackgroundEffect.blurRegion: (root.visible && dialog.radius > 0) ? searchBlurRegionHolder : null

    Region {
        id: searchBlurRegionHolder
        RoundedBlurRegion {
            item: dialog
            radius: dialog.radius
        }
    }
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // iOS App-Library style liquid header band, mirroring the launcher's
    // LiquidSearchBar. The whole top strip is one continuous frosted lens over
    // the result view: it captures the region directly beneath the band and
    // blurs whatever entries scroll under it, so the entire top flows with
    // content. The capture rect tracks the view's contentY so the lens always
    // shows the live content below. The search field floats centered on this
    // band as a liquid-glass capsule, so there is no seam between the field
    // and its flanks.
    component LiquidSearchBand: Item {
        id: searchBand
        // The result view (ListView or GridView) whose scrolling content this
        // lens frosts over. Both are Flickables, so a Flickable reference
        // exposes contentY and lets the band follow whichever viewMode is
        // active.
        required property Flickable sourceView
        // The band spans the header's full width; only its height is fixed.
        height: 49

        // Region of the result view directly beneath this band, in the view's
        // own (viewport) coordinates. A Flickable is captured as its rendered
        // viewport - the visible window already reflects contentY - so the
        // source rect must NOT add contentY again.
        //
        // The band floats above the view's top edge, so mapping it into the
        // view gives a negative y: the band sits over the view's empty top
        // margin. That is exactly what we want to frost. Before any scrolling
        // the slice over the view is empty, so the band rests on clean glass;
        // as entries scroll up they slide into the band's slice and become its
        // flowing background. Pixels outside the view's bounds capture as
        // transparent, which simply shows the dialog's blurred backdrop.
        readonly property rect _lensRect: {
            if (!sourceView)
                return Qt.rect(0, 0, 0, 0)
            const topLeft = searchBand.mapToItem(sourceView, 0, 0)
            return Qt.rect(topLeft.x, topLeft.y,
                searchBand.width, searchBand.height)
        }

        ShaderEffectSource {
            id: lensSource
            visible: false
            sourceItem: searchBand.sourceView
            sourceRect: searchBand._lensRect
            live: true
            hideSource: false
            smooth: true
        }
        FastBlur {
            id: lensBlur
            anchors.fill: parent
            source: lensSource
            radius: 16
            transparentBorder: true
            cached: true
        }
        // Clip the blur to the card's own top corners and let the bottom fade
        // out, so the band reads as the card's top edge itself rather than a
        // separate rounded pill floating over it. The mask is a vertical
        // gradient: fully opaque at the top, transparent at the bottom.
        OpacityMask {
            anchors.fill: parent
            source: lensBlur
            maskSource: lensFade
        }
        Item {
            id: lensFade
            anchors.fill: parent
            visible: false
            layer.enabled: true
            // Rounded only at the top corners (matching the card radius) so
            // the band's upper edge merges with the card outline.
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: parent.height
                radius: 20
                // Extend below the band so only the top corners stay rounded;
                // the bottom edge is handled by the fade, not a hard corner.
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: "white" }
                    GradientStop { position: 0.55; color: "white" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
        }
    }

    // QuickSearch result icon with the same appearance settings as Dock.
    // Unlike the shared AppIcon component, this samples IconImage's backing
    // texture directly. It deliberately avoids ShaderEffectSource: QuickSearch
    // repeatedly hides and re-shows its PanelWindow, and a source-item capture
    // can retain the old QQuickWindow across that transition.
    component ResultIcon: Item {
        id: resultIcon
        property string iconSource: ""

        IconImage {
            id: sourceImage
            anchors.fill: parent
            source: resultIcon.iconSource
            smooth: true
            asynchronous: true
            backer.cache: false
            visible: false
        }

        ShaderEffect {
            anchors.fill: parent
            property variant source: sourceImage.backer
            property real opacityMult: ConfigService.iconMode === "color"
                ? 1.0 : ConfigService.iconOpacity
            property real sat: ConfigService.iconMode === "color"
                ? 1.0 : ConfigService.iconSaturation
            property real iconTintEnabled: ConfigService.iconTintEnabled
            property color iconTintColor: ConfigService.iconTintColor
            fragmentShader: Qt.resolvedUrl("../../shaders/icon_effect.frag.qsb")
        }
    }

    property bool clipboardSettingsOpen: false

    function reset() {
        query = "";
        clipboardSettingsOpen = false;
        // Window mode opens with the most recently used window selected (the
        // first MRU result); Alt+Tab proposes the previous window immediately.
        selectedIndex = 0;
        focusTimer.restart();
        if (mode === "clipboard") {
            if (viewMode === "grid")
                gridView.positionViewAtBeginning();
            else
                resultView.positionViewAtBeginning();
        }
    }

    function deleteCurrentSelection() {
        if (root.mode !== "clipboard" || root.selectedIndex < 0 || root.selectedIndex >= root.resultCount)
            return;
        const result = root.results[root.selectedIndex];
        if (result && result.selectionRecord) {
            ClipboardService.deleteEntry(result.selectionRecord);
        }
    }

    function moveSelection(delta) {
        if (resultCount === 0)
            return;
        selectedIndex = (selectedIndex + delta + resultCount) % resultCount;
        if (viewMode === "grid")
            gridView.positionViewAtIndex(selectedIndex, GridView.Contain);
        else
            resultView.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activateSelection() {
        if (selectedIndex < 0 || selectedIndex >= resultCount)
            return;
        const result = results[selectedIndex];
        if (result.kind === "window") {
            // Use the Dock facade so its shared active indicator can begin
            // travelling before this focusable search layer closes.
            DockModelService.activateWindow(result.windowId);
        } else if (result.kind === "clipboard") {
            ClipboardService.copy(result.selectionRecord);
        } else {
            AppActionService.launch(result.entry);
        }
        closeRequested();
    }

    onOpenChanged: {
        if (open) {
            reset();
            if (mode === "clipboard")
                ClipboardService.refresh();
        }
    }
    onModeChanged: {
        if (open)
            reset();
    }
    onResultsChanged: {
        if (selectedIndex >= resultCount)
            selectedIndex = Math.max(0, resultCount - 1);
    }
    Timer {
        id: focusTimer
        interval: 1
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    // A copy can arrive while the palette is already open. Refreshing the
    // light-weight cliphist index here makes it appear without reopening.
    Timer {
        interval: 800
        repeat: true
        running: root.open && root.mode === "clipboard"
        onTriggered: ClipboardService.refresh()
    }

    // There is intentionally no dimmed visual overlay. This transparent input
    // catcher preserves the natural Spotlight behaviour: a click outside the
    // compact search card simply dismisses it.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            if (root.clipboardSettingsOpen) {
                root.clipboardSettingsOpen = false;
                return;
            }
            root.closeRequested();
        }
    }

    Rectangle {
        id: dialog
        width: 580
        height: root.resultCount > 0
            ? (searchHeader.height + 6 + 6 + (root.viewMode === "grid" ? gridView.height : resultView.height) + 10)
            : (searchHeader.height + 6 + 50)
        // Shared readability outline so foreground text stays legible on
        // varying wallpapers. Dark themes use a dark outline for light text;
        // light themes use a light outline for dark text.
        readonly property color textOutlineColor: ThemeService.isDark
            ? Qt.rgba(0.05, 0.08, 0.12, 0.38)
            : Qt.rgba(1, 1, 1, 0.50)
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: Math.round(parent.height * 0.16)
        }
        radius: 28
        color: "transparent"
        opacity: root.revealProgress

        LiquidGlassSurface {
            anchors.fill: parent
            radius: dialog.radius
            baseColor: ThemeService.isDark
                ? Qt.rgba(0.08, 0.09, 0.12, 0.35)
                : Qt.rgba(0.95, 0.95, 0.98, 0.50)
            blurStrength: AppearanceConfigService.effectiveLauncherBlur
            liquidStrength: AppearanceConfigService.effectiveLauncherLiquid
            // QuickSearch stays neutral. Wallpaper-derived tint makes this
            // transient surface look coloured even when only KWin liquid
            // glass is intended to be enabled globally.
            ambientStrength: 0.0
            border.width: 1
            border.color: ThemeService.isDark
                ? Qt.rgba(1, 1, 1, 0.12)
                : Qt.rgba(1, 1, 1, 0.60)
        }

        Item {
            id: searchHeader
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 6
            }
            height: 44
            z: 1

            // The editable search field: a liquid-glass capsule
            LiquidGlassSurface {
                id: fieldPill
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 12
                    rightMargin: 12
                    top: parent.top
                    bottom: parent.bottom
                }
                radius: height / 2
                baseColor: ThemeService.isDark
                    ? Qt.rgba(1, 1, 1, 0.07)
                    : Qt.rgba(0, 0, 0, 0.06)
                surfaceOpacity: 1.0
                materialDepth: 1.0
                bottomShadeVisible: false
                // Keep the input capsule neutral as well; the previous 0.8
                // wallpaper tint was especially visible on colourful walls.
                ambientStrength: 0.0

                // Inner top-edge glow: a thin bright line hugging the capsule's
                // upper rim, the hallmark of iOS liquid components.
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: fieldPill.radius * 0.7
                        rightMargin: fieldPill.radius * 0.7
                    }
                    height: 1
                    radius: 0.5
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
                        GradientStop { position: 0.25; color: Qt.rgba(1, 1, 1, 0.28) }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.4) }
                        GradientStop { position: 0.75; color: Qt.rgba(1, 1, 1, 0.28) }
                        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
                    }
                }

                // Focus ring over the glass body.
                Rectangle {
                    anchors.fill: parent
                    radius: fieldPill.radius
                    color: "transparent"
                    border.width: searchInput.activeFocus ? 1 : 0
                    border.color: ThemeService.isDark
                        ? Qt.rgba(1, 1, 1, 0.40)
                        : Qt.rgba(0, 0, 0, 0.25)
                }
            }

            Text {
                anchors {
                    left: fieldPill.left
                    leftMargin: 14
                    verticalCenter: fieldPill.verticalCenter
                }
                text: "⌕"
                color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.72) : Qt.rgba(0, 0, 0, 0.65)
                font.pixelSize: 20
                style: ThemeService.isDark ? Text.Outline : Text.Normal
                styleColor: dialog.textOutlineColor
            }

            TextInput {
                id: searchInput
                anchors {
                    left: fieldPill.left
                    leftMargin: 44
                    right: fieldPill.right
                    rightMargin: root.mode === "clipboard" ? 180 : 130
                    verticalCenter: fieldPill.verticalCenter
                }
                color: ThemeService.foregroundColor
                font {
                    family: "Noto Sans CJK SC"
                    pixelSize: 15
                }
                clip: true
                selectByMouse: true
                text: root.query
                onTextEdited: {
                    root.query = text;
                    root.selectedIndex = 0;
                }
                Keys.onPressed: function (event) {
                    const control = (event.modifiers & Qt.ControlModifier) !== 0;
                    if (event.key === Qt.Key_Down || (control && event.key === Qt.Key_N)) {
                        root.moveSelection(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up || (control && event.key === Qt.Key_P)) {
                        root.moveSelection(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activateSelection();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        if (root.clipboardSettingsOpen) {
                            root.clipboardSettingsOpen = false;
                            event.accepted = true;
                        } else {
                            root.closeRequested();
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Tab) {
                        root.modeCycleRequested();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Delete) {
                        if (root.mode === "clipboard") {
                            root.deleteCurrentSelection();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.fill: parent
                    visible: !searchInput.text
                    text: root.placeholder
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.54) : Qt.rgba(0, 0, 0, 0.45)
                    font: searchInput.font
                    verticalAlignment: Text.AlignVCenter
                    style: ThemeService.isDark ? Text.Outline : Text.Normal
                    styleColor: dialog.textOutlineColor
                }
            }

            Row {
                anchors {
                    right: fieldPill.right
                    rightMargin: 10
                    verticalCenter: fieldPill.verticalCenter
                }
                spacing: 6

                Text {
                    text: root.modeTitle + (root.mode === "clipboard" ? " · 最新优先" : "") + " · Tab"
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.46) : Qt.rgba(0, 0, 0, 0.48)
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    style: ThemeService.isDark ? Text.Outline : Text.Normal
                    styleColor: dialog.textOutlineColor
                }

                // Clear all clipboard history button
                Item {
                    visible: root.mode === "clipboard" && root.resultCount > 0
                    width: clearText.implicitWidth + 12
                    height: 22
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: clearMouse.containsMouse
                            ? (ThemeService.isDark ? Qt.rgba(1, 0.3, 0.3, 0.22) : Qt.rgba(0.9, 0.1, 0.1, 0.12))
                            : "transparent"
                    }

                    Text {
                        id: clearText
                        anchors.centerIn: parent
                        text: "清空"
                        color: clearMouse.containsMouse
                            ? "#ff453a"
                            : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.50))
                        font.pixelSize: 11
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ClipboardService.clearAll()
                    }
                }

                // Settings button (toggles clipboard settings popover)
                Item {
                    visible: root.mode === "clipboard"
                    width: 22
                    height: 22
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: (settingsMouse.containsMouse || root.clipboardSettingsOpen)
                            ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.10))
                            : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "⚙"
                        color: root.clipboardSettingsOpen
                            ? (ThemeService.isDark ? "#64b5ff" : "#0066cc")
                            : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.70) : Qt.rgba(0, 0, 0, 0.65))
                        font.pixelSize: 13
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }

                    MouseArea {
                        id: settingsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clipboardSettingsOpen = !root.clipboardSettingsOpen
                    }
                }

                Item {
                    width: 22
                    height: 22
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: viewToggle.containsMouse ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        // The button advertises the layout selected by a click.
                        text: root.viewMode === "list" ? "▦" : "☷"
                        color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.76) : Qt.rgba(0, 0, 0, 0.70)
                        font.pixelSize: 16
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }

                    MouseArea {
                        id: viewToggle
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.viewModeToggleRequested()
                    }
                }
            }
        }

        // Settings popover panel
        Rectangle {
            id: settingsPopover
            visible: root.mode === "clipboard" && root.clipboardSettingsOpen
            z: 20
            width: 320
            height: settingsContent.implicitHeight + 24
            radius: 18
            color: "transparent"
            anchors {
                top: searchHeader.bottom
                topMargin: 4
                right: parent.right
                rightMargin: 12
            }

            LiquidGlassSurface {
                anchors.fill: parent
                radius: settingsPopover.radius
                baseColor: ThemeService.isDark
                    ? Qt.rgba(0.12, 0.13, 0.16, 0.95)
                    : Qt.rgba(0.96, 0.96, 0.98, 0.95)
                blurStrength: AppearanceConfigService.effectiveLauncherBlur
                liquidStrength: AppearanceConfigService.effectiveLauncherLiquid
                ambientStrength: 0.0
                border.width: 1
                border.color: ThemeService.isDark
                    ? Qt.rgba(1, 1, 1, 0.18)
                    : Qt.rgba(0, 0, 0, 0.12)
            }

            Column {
                id: settingsContent
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 12
                }
                spacing: 10

                // Header
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - 24
                        text: "剪贴板偏好设置"
                        font { pixelSize: 13; bold: true; family: "Noto Sans CJK SC" }
                        color: ThemeService.foregroundColor
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }
                    Text {
                        width: 24
                        horizontalAlignment: Text.AlignRight
                        text: "×"
                        font.pixelSize: 18
                        color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.50)
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clipboardSettingsOpen = false
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: parent.width
                    height: 1
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                }

                // Watch Images row
                Row {
                    width: parent.width
                    Column {
                        width: parent.width - 46
                        spacing: 2
                        Text {
                            text: "监控图片内容"
                            font { pixelSize: 12; weight: Font.Medium; family: "Noto Sans CJK SC" }
                            color: ThemeService.foregroundColor
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: dialog.textOutlineColor
                        }
                        Text {
                            text: "自动记录截图与复制的图片"
                            font.pixelSize: 10
                            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(0, 0, 0, 0.50)
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: dialog.textOutlineColor
                        }
                    }
                    // iOS switch pill
                    Rectangle {
                        width: 40
                        height: 22
                        radius: 11
                        anchors.verticalCenter: parent.verticalCenter
                        color: ClipboardService.watchImages
                            ? "#34c759"
                            : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.15))
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            width: 18
                            height: 18
                            radius: 9
                            anchors.verticalCenter: parent.verticalCenter
                            x: ClipboardService.watchImages ? parent.width - width - 2 : 2
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ClipboardService.setWatchImages(!ClipboardService.watchImages)
                        }
                    }
                }

                // Max history limit row
                Column {
                    width: parent.width
                    spacing: 6

                    Text {
                        text: "历史保留数量"
                        font { pixelSize: 12; weight: Font.Medium; family: "Noto Sans CJK SC" }
                        color: ThemeService.foregroundColor
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }

                    Row {
                        spacing: 6
                        Repeater {
                            model: [50, 100, 200, 500]
                            Rectangle {
                                width: (settingsContent.width - 18) / 4
                                height: 26
                                radius: 6
                                color: ClipboardService.maxItems === modelData
                                    ? (ThemeService.isDark ? Qt.rgba(0.20, 0.50, 0.95, 0.40) : Qt.rgba(0.0, 0.45, 0.85, 0.20))
                                    : (itemMouse.containsMouse
                                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04)))
                                border.width: 1
                                border.color: ClipboardService.maxItems === modelData
                                    ? (ThemeService.isDark ? Qt.rgba(0.40, 0.70, 1, 0.60) : Qt.rgba(0.0, 0.45, 0.85, 0.50))
                                    : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData + " 条"
                                    font.pixelSize: 11
                                    color: ClipboardService.maxItems === modelData
                                        ? (ThemeService.isDark ? "#64b5ff" : "#0066cc")
                                        : ThemeService.foregroundColor
                                    style: ThemeService.isDark ? Text.Outline : Text.Normal
                                    styleColor: dialog.textOutlineColor
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: ClipboardService.setMaxItems(modelData)
                                }
                            }
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: parent.width
                    height: 1
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
                }

                // Global Shortcuts entry
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: 8
                    color: shortcutMouse.containsMouse
                        ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
                        : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.04))

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        Text {
                            width: parent.width - 20
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌨ 配置系统全局快捷键 (Meta+V)"
                            font { pixelSize: 11; family: "Noto Sans CJK SC" }
                            color: ThemeService.foregroundColor
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: dialog.textOutlineColor
                        }
                        Text {
                            width: 20
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                            text: "›"
                            font.pixelSize: 16
                            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.40) : Qt.rgba(0, 0, 0, 0.40)
                        }
                    }

                    MouseArea {
                        id: shortcutMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            ClipboardService.openShortcutSettings()
                            root.clipboardSettingsOpen = false
                        }
                    }
                }
            }
        }

        ListView {
            id: resultView
            visible: root.viewMode === "list"
            anchors {
                top: searchHeader.bottom
                left: parent.left
                right: parent.right
                topMargin: 4
                leftMargin: 8
                rightMargin: 8
            }
            height: root.visibleResultCount * 52
            clip: true
            model: root.results
            currentIndex: root.selectedIndex

            delegate: Item {
                id: resultItem
                required property var modelData
                required property int index
                width: resultView.width
                height: 52

                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: resultItem.index === root.selectedIndex ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                }

                Rectangle {
                    width: 30
                    height: 30
                    radius: 8
                    anchors {
                        left: parent.left
                        leftMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    visible: resultItem.modelData.isImage ?? false
                    color: Qt.rgba(0.30, 0.56, 0.94, 0.34)
                    border.width: 1
                    border.color: Qt.rgba(0.66, 0.82, 1, 0.42)
                }

                ResultIcon {
                    width: resultItem.modelData.isImage ? 20 : 30
                    height: width
                    anchors {
                        left: parent.left
                        leftMargin: resultItem.modelData.isImage ? 17 : 12
                        verticalCenter: parent.verticalCenter
                    }
                    iconSource: resultItem.modelData.icon ?? ""
                }

                Column {
                    anchors {
                        left: parent.left
                        leftMargin: 54
                        right: parent.right
                        rightMargin: root.mode === "clipboard" ? 72 : 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 1

                    Text {
                        width: parent.width
                        text: resultItem.modelData.title
                        color: ThemeService.foregroundColor
                        elide: Text.ElideRight
                        font {
                            pixelSize: 14
                            weight: Font.DemiBold
                        }
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }

                    Text {
                        width: parent.width
                        text: resultItem.modelData.subtitle
                        color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.68) : Qt.rgba(0, 0, 0, 0.58)
                        elide: Text.ElideRight
                        font.pixelSize: 11
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }
                }

                // Right action badges
                Row {
                    anchors {
                        right: parent.right
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    // Latest badge
                    Rectangle {
                        visible: root.mode === "clipboard" && resultItem.index === 0
                        width: 38
                        height: 18
                        radius: 9
                        anchors.verticalCenter: parent.verticalCenter
                        color: ThemeService.isDark ? Qt.rgba(0.30, 0.56, 0.94, 0.32) : Qt.rgba(0.0, 0.50, 0.90, 0.18)
                        border.width: 1
                        border.color: ThemeService.isDark ? Qt.rgba(0.66, 0.82, 1, 0.40) : Qt.rgba(0.0, 0.50, 0.90, 0.30)

                        Text {
                            anchors.centerIn: parent
                            text: "最新"
                            color: ThemeService.isDark ? Qt.rgba(0.84, 0.93, 1, 0.94) : Qt.rgba(0.0, 0.45, 0.85, 1.0)
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: dialog.textOutlineColor
                        }
                    }

                    // Delete single clipboard item button
                    Item {
                        visible: root.mode === "clipboard"
                        width: 22
                        height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: (resultMouse.containsMouse || resultItem.index === root.selectedIndex) ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 100 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 11
                            color: deleteBtnMouse.containsMouse
                                ? (ThemeService.isDark ? Qt.rgba(1, 0.3, 0.3, 0.30) : Qt.rgba(1, 0.2, 0.2, 0.15))
                                : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: deleteBtnMouse.containsMouse ? "#ff453a" : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.60) : Qt.rgba(0, 0, 0, 0.50))
                            font.pixelSize: 16
                            style: ThemeService.isDark ? Text.Outline : Text.Normal
                            styleColor: dialog.textOutlineColor
                        }

                        MouseArea {
                            id: deleteBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (resultItem.modelData.selectionRecord)
                                    ClipboardService.deleteEntry(resultItem.modelData.selectionRecord);
                            }
                        }
                    }
                }

                MouseArea {
                    id: resultMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selectedIndex = resultItem.index
                    onClicked: {
                        root.selectedIndex = resultItem.index;
                        root.activateSelection();
                    }
                }
            }
        }

        GridView {
            id: gridView
            visible: root.viewMode === "grid"
            anchors {
                top: searchHeader.bottom
                left: parent.left
                right: parent.right
                topMargin: 4
                leftMargin: 8
                rightMargin: 8
            }
            height: root.visibleGridRowCount * 94
            cellWidth: width / root.gridColumnCount
            cellHeight: 94
            clip: true
            model: root.results
            currentIndex: root.selectedIndex

            delegate: Item {
                id: gridResultItem
                required property var modelData
                required property int index
                width: gridView.cellWidth
                height: gridView.cellHeight

                Rectangle {
                    anchors {
                        fill: parent
                        margins: 3
                    }
                    radius: 11
                    color: gridResultItem.index === root.selectedIndex ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                }

                Rectangle {
                    visible: root.mode === "clipboard" && gridResultItem.index === 0
                    width: 34
                    height: 17
                    radius: 8.5
                    anchors {
                        right: parent.right
                        rightMargin: 7
                        top: parent.top
                        topMargin: 7
                    }
                    color: ThemeService.isDark ? Qt.rgba(0.30, 0.56, 0.94, 0.36) : Qt.rgba(0.0, 0.50, 0.90, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: "最新"
                        color: ThemeService.isDark ? Qt.rgba(0.84, 0.93, 1, 0.96) : Qt.rgba(0.0, 0.45, 0.85, 1.0)
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }
                }

                // Delete button on grid item
                Item {
                    visible: root.mode === "clipboard" && (gridMouse.containsMouse || gridResultItem.index === root.selectedIndex)
                    width: 20
                    height: 20
                    anchors {
                        left: parent.left
                        leftMargin: 6
                        top: parent.top
                        topMargin: 6
                    }
                    z: 2

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: gridDeleteMouse.containsMouse
                            ? (ThemeService.isDark ? Qt.rgba(1, 0.3, 0.3, 0.35) : Qt.rgba(1, 0.2, 0.2, 0.20))
                            : (ThemeService.isDark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.60))
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: gridDeleteMouse.containsMouse ? "#ff453a" : (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(0, 0, 0, 0.60))
                        font.pixelSize: 14
                        style: ThemeService.isDark ? Text.Outline : Text.Normal
                        styleColor: dialog.textOutlineColor
                    }

                    MouseArea {
                        id: gridDeleteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (gridResultItem.modelData.selectionRecord)
                                ClipboardService.deleteEntry(gridResultItem.modelData.selectionRecord);
                        }
                    }
                }

                Rectangle {
                    width: 50
                    height: 50
                    radius: 13
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: 5
                    }
                    visible: gridResultItem.modelData.isImage ?? false
                    color: Qt.rgba(0.30, 0.56, 0.94, 0.34)
                    border.width: 1
                    border.color: Qt.rgba(0.66, 0.82, 1, 0.42)
                }

                ResultIcon {
                    width: gridResultItem.modelData.isImage ? 34 : 42
                    height: width
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        top: parent.top
                        topMargin: gridResultItem.modelData.isImage ? 13 : 9
                    }
                    iconSource: gridResultItem.modelData.icon ?? ""
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: 7
                        rightMargin: 7
                        top: parent.top
                        topMargin: 56
                    }
                    text: gridResultItem.modelData.title
                    color: ThemeService.foregroundColor
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font {
                        pixelSize: 11
                        weight: Font.DemiBold
                    }
                    style: ThemeService.isDark ? Text.Outline : Text.Normal
                    styleColor: dialog.textOutlineColor
                }

                Text {
                    visible: gridResultItem.modelData.isImage ?? false
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: 6
                        rightMargin: 6
                        top: parent.top
                        topMargin: 71
                    }
                    text: gridResultItem.modelData.subtitle.replace("图片剪贴板 · ", "")
                    color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.54) : Qt.rgba(0, 0, 0, 0.52)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: 9
                    style: ThemeService.isDark ? Text.Outline : Text.Normal
                    styleColor: dialog.textOutlineColor
                }

                MouseArea {
                    id: gridMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selectedIndex = gridResultItem.index
                    onClicked: {
                        root.selectedIndex = gridResultItem.index;
                        root.activateSelection();
                    }
                }
            }
        }

        Text {
            visible: root.resultCount === 0
            anchors {
                top: searchHeader.bottom
                topMargin: 8
                left: parent.left
                right: parent.right
            }
            height: 40
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.mode === "app" ? "未找到匹配的应用" : (root.mode === "clipboard" ? "剪贴板历史为空" : "未找到匹配的窗口")
            color: ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.52) : Qt.rgba(0, 0, 0, 0.50)
            font.pixelSize: 13
            style: ThemeService.isDark ? Text.Outline : Text.Normal
            styleColor: dialog.textOutlineColor
        }
    }
}
