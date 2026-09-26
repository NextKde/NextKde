import QtQuick
import Quickshell
import "./AdaptiveMath.mjs" as AdaptiveMath
import qs.desktop
import qs.desktop.modules.applauncher
import qs.desktop.modules.common
import qs.desktop.modules.weather
import "../../../Kos/Ui"

// ────────────────────────────────────────────────────────────────
// DockContainer — Adaptive layout engine.
//
// Calls AdaptiveMath.computeLayout(...) reactively whenever
// model counts or screen dimensions change.  Derives iconSize,
// dockHeight, dockWidth, and all spacing values.  Hosts the
// horizontal Row of three sections: pinned | windows | music.
//
// Animation Behaviors on computed dimensions ensure smooth
// transitions when the dock resizes.
// ────────────────────────────────────────────────────────────────

Item {
    id: container

    // DockWindow chooses the target output. Never infer it from
    // Quickshell.screens[0]: on a multi-monitor setup the Dock may be on a
    // different output with a different width.
    property var targetScreen: null
    property real surfaceOriginX: 0
    property real surfaceOriginY: 0
    property Component leadingAccessory: null
    property Component trailingAccessory: null
    property bool clockInInfoCarousel: false

    // ═══════════════════════════════════════════════════════════
    // Inputs (from services / parent)
    // ═══════════════════════════════════════════════════════════
    // The app launcher is a permanent visual slot before persisted pinned apps.
    // Include it in adaptive width fitting, but never in the model used for
    // drag-reordering or persistence.
    readonly property int pinnedCount: DockModelService.pinnedCount + 2
    readonly property int windowCount: DockModelService.windowCount
    function infoCardSelected(id) {
        return ConfigService.infoCardOrder.indexOf(id) >= 0
    }
    readonly property bool hasPlayingMusic: infoCardSelected("music")
        && DockMprisService.hasPlayer
    readonly property bool hasWeather: infoCardSelected("weather")
        && WeatherService.available
    // Side Dock Stack information keeps its clock page. The separate
    // top-of-Dock clock is intentionally not injected by DesktopEnvironment.
    readonly property bool hasClock: infoCardSelected("clock")
        && (clockInInfoCarousel || vertical)
    // Temperature is a permanent horizontal Dock page. MetricsService may
    // still be loading its first snapshot; the card remains and shows "--".
    readonly property bool hasTemperature: infoCardSelected("metrics")
    readonly property bool hasAvailableInfo: hasPlayingMusic || hasWeather || hasClock
        || hasTemperature
    readonly property int screenWidth: targetScreen?.width
        ?? Quickshell.screens[0]?.width ?? 1920
    readonly property int screenHeight: targetScreen?.height
        ?? Quickshell.screens[0]?.height ?? 1080
    readonly property bool barIntegratedWithDock:
        AppearanceConfigService.barIntegratedWithDock
    readonly property real reservedBarHeight: barIntegratedWithDock
        ? 0 : ConfigService.barHeight
    // A fused side Dock gets the full output height because the standalone
    // top Bar and its exclusive strip are disabled too.
    // Surface style and content distribution are independent. A taskbar
    // always fills its edge; relaxed content also asks a floating surface for
    // the available length, but keeps proportional insets and rounded glass.
    readonly property bool stretched: ConfigService.dockStyle === "taskbar"
    readonly property bool relaxed: ConfigService.contentStyle === "relaxed"
    readonly property bool fillsAvailableLength: stretched || relaxed
    readonly property real floatingSpreadInset: !stretched && relaxed
        ? Math.max(4, Math.round(baseHeight * 0.12)) : 0
    readonly property int availableLength: (vertical
        ? screenHeight - reservedBarHeight
        : screenWidth) - Math.round(floatingSpreadInset * 2)
    readonly property real baseHeight: ConfigService.baseHeight
    // Shape proportions come from the selected shell style. The macOS token
    // values equal the previous Dock defaults, preserving the upgrade baseline.
    // User-owned height/position/visibility remain in DockConfigService.
    readonly property var proportions: ({
        vpad: AppearanceTokens.dock.verticalPaddingRatio,
        hpad: AppearanceTokens.dock.horizontalPaddingRatio,
        spacing: AppearanceTokens.dock.itemSpacingRatio,
        divmargin: AppearanceTokens.dock.dividerMarginRatio,
    })
    // Side docks (left/right) stack icons vertically instead of horizontally.
    readonly property bool vertical: ConfigService.position === "left"
        || ConfigService.position === "right"
    readonly property int accessoryCount:
        (leadingAccessoryLoader.active ? 1 : 0)
        + (trailingAccessoryLoader.active ? 1 : 0)
    readonly property real accessoryContentWidth:
        leadingAccessoryLoader.width + trailingAccessoryLoader.width
    // Some accessories fold their content vertically when enough Dock height
    // is available. Feed their stable maximum width into the height solver so
    // that changing row count cannot create a width/height binding loop; the
    // final Dock width below still uses the accessory's actual folded width.
    readonly property real leadingAccessoryReserveWidth:
        leadingAccessoryLoader.active && leadingAccessoryLoader.item
        ? (leadingAccessoryLoader.item.layoutMaximumWidth !== undefined
            ? leadingAccessoryLoader.item.layoutMaximumWidth
            : leadingAccessoryLoader.width) : 0
    readonly property real trailingAccessoryReserveWidth:
        trailingAccessoryLoader.active && trailingAccessoryLoader.item
        ? (trailingAccessoryLoader.item.layoutMaximumWidth !== undefined
            ? trailingAccessoryLoader.item.layoutMaximumWidth
            : trailingAccessoryLoader.width) : 0
    // Reserve accessory width before solving iconSize. The extra estimate
    // covers one separator and two Row gaps per accessory; the exact value is
    // added back after AdaptiveMath returns its scale-dependent margins.
    readonly property real estimatedAccessoryWidth:
        leadingAccessoryReserveWidth + trailingAccessoryReserveWidth
        + accessoryCount * baseHeight * 0.60
    // Probe the crowded layout with the carousel included before deciding
    // whether it is safe to show. This avoids a feedback loop where hiding the
    // carousel makes icons larger and immediately makes it reappear.
    readonly property var _infoProbeLayout: AdaptiveMath.computeLayout(
        baseHeight, pinnedCount, windowCount,
        hasAvailableInfo && !vertical,
        Math.max(baseHeight, availableLength - estimatedAccessoryWidth),
        proportions,
        vertical ? AdaptiveMath.MAX_HEIGHT_RATIO : AdaptiveMath.MAX_WIDTH_RATIO,
        infoSlotUnits
    )
    // At the 18px absolute icon floor, the cards cannot keep even compact
    // glyphs legible. Remove the carousel and its divider as one unit, which
    // also returns its four icon-widths to application tasks.
    readonly property bool hideInfoCarousel: !vertical && hasAvailableInfo
        && _infoProbeLayout.iconSize <= AdaptiveMath.MIN_ICON_SIZE
    readonly property bool hasInfo: hasAvailableInfo && !hideInfoCarousel
    // A side Dock rotates its content row. Its dedicated compact carousel
    // needs only two icon lengths, while the bottom carousel keeps four.
    readonly property bool infoExpanded: ConfigService.infoCardMode === "expanded"
    readonly property int expandedInfoUnits: {
        let total = 0
        for (const id of ConfigService.infoCardOrder) {
            const available = id === "music" ? hasPlayingMusic
                : id === "weather" ? hasWeather
                : id === "clock" ? hasClock
                : id === "metrics" ? hasTemperature : false
            if (available)
                total += vertical ? 2 : (id === "clock" ? 3 : 4)
        }
        return total
    }
    readonly property int infoSlotUnits: infoExpanded
        ? expandedInfoUnits : (vertical ? 2 : 4)
    // ═══════════════════════════════════════════════════════════
    // Computed layout (re-evaluates on any input change)
    // ═══════════════════════════════════════════════════════════
    // All adaptive inputs are passed into one pure calculation. New content
    // must affect the calculation through counts/units instead of changing
    // height or spacing locally, otherwise width fitting can be bypassed.
    readonly property var _layout: AdaptiveMath.computeLayout(
        baseHeight, pinnedCount, windowCount,
        hasInfo,
        Math.max(baseHeight, availableLength - estimatedAccessoryWidth),
        proportions,
        vertical ? AdaptiveMath.MAX_HEIGHT_RATIO : AdaptiveMath.MAX_WIDTH_RATIO,
        infoSlotUnits
    )

    readonly property int computedDockHeight: _layout.dockHeight
    readonly property int iconSize: _layout.iconSize
    // naturalDockWidth is the width the content asks for. A taskbar or relaxed
    // layout grows to the available edge length. distributionSlack is spent
    // only by relaxed content, between apps/windows and trailing components.
    readonly property int naturalDockWidth: Math.round(_layout.dockWidth
        + accessoryContentWidth
        + accessoryCount * (2 + dividerMargin * 2 + itemSpacing * 2))
    readonly property int computedDockWidth: fillsAvailableLength
        ? Math.max(naturalDockWidth, availableLength)
        : naturalDockWidth
    readonly property real distributionSlack: Math.max(0, computedDockWidth
        - naturalDockWidth)
    readonly property int itemSpacing: _layout.itemSpacing
    readonly property int hPadding: _layout.hPadding
    readonly property int vPadding: _layout.vPadding
    readonly property int dividerMargin: _layout.dividerMargin
    readonly property int pillRadius: Math.round(computedDockHeight
        * AppearanceTokens.dock.radiusRatio)
    // DockIcon reserves this invisible outer slot even when inactive. This
    // keeps the Row width stable while the active background appears/disappears.
    readonly property real activeBackgroundGap: _layout.activeBackgroundGap
    readonly property int iconUnits: _layout.iconUnits
    readonly property real infoUnits: _layout.infoUnits
    // Long press or starting a real drag enters the iPadOS-like edit state.
    // It ends on drop, a plain Dock-icon tap, or shortly after the pointer
    // leaves, while another direct drag can enter the state again.
    property bool editMode: false
    // This tracks only the in-progress source for reorder geometry; it must
    // not decide whether the user remains in persistent edit mode after drop.
    property var draggedPinnedLoader: null
    readonly property bool isEditing: editMode || draggedPinnedLoader !== null
    readonly property real draggedPointerX: draggedPinnedLoader
        ? draggedPinnedLoader.dragPointerX : -1

    // ── Auto-hide inhibitor state (consumed by DockAutoHideController) ──
    // A passive pointer probe so the controller can keep the dock shown while
    // the cursor is over the glass. passive because DockIcon, music controls,
    // drag gestures and MouseAreas still win their own events.
    readonly property bool pointerInside: _dockPointerHover.hovered
    // Keep the pointer in DockContainer coordinates. Mapping each icon back to
    // this same Item is safe for both bottom and rotated side Docks.
    readonly property point magnificationPointer: _dockPointerHover.hovered
        ? _dockPointerHover.point.position
        : Qt.point(-10000, -10000)
    HoverHandler {
        id: _dockPointerHover
        enabled: true
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        // Editing is spatial: once the pointer leaves the dock the user is
        // done placing icons. A grace period keeps a fast diagonal crossing
        // of a dock corner from ending an in-progress session, and any
        // started drag cancels the pending exit.
        onHoveredChanged: {
            if (hovered)
                editExitTimer.stop()
            else if (container.editMode && !container.draggedPinnedLoader)
                editExitTimer.restart()
        }
    }

    Timer {
        id: editExitTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (container.editMode && !container.draggedPinnedLoader
                    && !_dockPointerHover.hovered)
                container.editMode = false
        }
    }

    function publishLauncherPresentation() {
        AppLauncherService.setDockPresentation(
            computedDockWidth,
            computedDockHeight,
            ConfigService.position,
            ThemeService.backgroundColor,
            WallpaperColorSource.primary,
            WallpaperColorSource.secondary,
            ThemeService.foregroundColor,
            reservedBarHeight)
    }

    // Several layout and palette bindings can change in the same event-loop
    // turn. Publish the final presentation once instead of briefly sending
    // AppLauncher intermediate width/colour combinations.
    Timer {
        id: launcherPresentationTimer
        interval: 0
        repeat: false
        onTriggered: container.publishLauncherPresentation()
    }

    function scheduleLauncherPresentation() {
        launcherPresentationTimer.restart()
    }

    Component.onCompleted: scheduleLauncherPresentation()
    onComputedDockWidthChanged: scheduleLauncherPresentation()
    onComputedDockHeightChanged: scheduleLauncherPresentation()
    // Side flips change both dimensions anyway, but keep the anchor side
    // explicit so the launcher never lags behind a dock edge change.
    onVerticalChanged: scheduleLauncherPresentation()

    Connections {
        target: ThemeService
        function onBackgroundColorChanged() { container.scheduleLauncherPresentation() }
        function onForegroundColorChanged() { container.scheduleLauncherPresentation() }
    }
    Connections {
        target: WallpaperColorSource
        function onPrimaryChanged() { container.scheduleLauncherPresentation() }
        function onSecondaryChanged() { container.scheduleLauncherPresentation() }
    }
    // Pin actions may come from Dock, AppLauncher, QuickSearch, or future
    // shell surfaces. Dock remains the sole owner of Dock persistence.
    Connections {
        target: AppActionService
        function onPinRequested(appId) { DockModelService.pinApp(appId) }
        function onUnpinRequested(appId) { DockModelService.unpinApp(appId) }
    }

    // Nearest top-level slot for the in-progress reorder preview.
    readonly property int dragInsertIndex: {
        if (!draggedPinnedLoader)
            return -1
        let nearestIndex = draggedPinnedLoader.pinnedIndex
        let nearestDistance = Number.POSITIVE_INFINITY
        for (let i = 0; i < pinnedRepeater.count; i++) {
            const candidate = pinnedRepeater.itemAt(i)
            if (!candidate)
                continue
            const distance = Math.abs(draggedPointerX
                                      - (candidate.x + candidate.width / 2))
            if (distance < nearestDistance) {
                nearestDistance = distance
                nearestIndex = i
            }
        }
        return nearestIndex
    }

    // ═══════════════════════════════════════════════════════════
    // Size
    // ═══════════════════════════════════════════════════════════
    implicitWidth: vertical ? computedDockHeight : computedDockWidth
    implicitHeight: vertical ? computedDockWidth : computedDockHeight
    width: implicitWidth
    height: implicitHeight

    // Keep PR #2's size interpolation when app groups, accessories, or the
    // information carousel change the adaptive layout.
    Behavior on height {
        NumberAnimation {
            duration: DockAnimation.dockResizeDuration
            easing.type: DockAnimation.dockResizeEasing
        }
    }
    Behavior on width {
        NumberAnimation {
            duration: DockAnimation.dockResizeDuration
            easing.type: DockAnimation.dockResizeEasing
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Content row
    // ═══════════════════════════════════════════════════════════

    opacity: iconUnits > 0 ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation {
            duration: DockAnimation.dockFadeDuration
            easing.type: DockAnimation.dockFadeEasing
        }
    }

    // This sits behind the delegates, so it only receives clicks in the Dock
    // gaps. It provides a natural way to leave the persistent edit state.
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: (container.editMode && !container.draggedPinnedLoader)
            || AppLauncherService.open
        onClicked: {
            if (AppLauncherService.open)
                AppLauncherService.hide()
            if (container.editMode && !container.draggedPinnedLoader)
                container.editMode = false
        }
    }

    // The trash is a shell control too, so its menu uses the same self-drawn
    // liquid-glass ContextMenu as Dock apps and the launcher. A native
    // Platform.Menu rendered with the system Qt/KDE style and broke away
    // from the rest of the shell.
    ContextMenu {
        id: trashContextMenu
        anchorItem: trashIcon
        position: ConfigService.position
        baseColor: ThemeService.backgroundColor
        foregroundColor: ThemeService.foregroundColor
        property bool hasBeenVisible: false

        Component.onCompleted: setItems([
            { icon: "folder-open", label: "打开回收站", cmd: "open" },
            { icon: "user-trash", label: "清空回收站", cmd: "empty" }
        ])

        onAboutToShow: hasBeenVisible = true
        onAboutToHide: {
            if (hasBeenVisible) {
                hasBeenVisible = false
                if (DockModelService.activeDockPopup === trashContextMenu)
                    DockModelService.releaseDockPopup(trashContextMenu)
            }
        }

        onAction: function(cmd) {
            if (cmd === "open")
                DockTrashService.open()
            else if (cmd === "empty")
                DockModelService.openDockPopup(trashConfirmPopup)
        }
    }

    // The launcher is a shell control, so its mode picker must use the same
    // self-drawn liquid-glass menu as Dock apps and desktop icons. Keeping it
    // as a native Qt/KDE menu made this one right-click entry visually break
    // away from the rest of the shell.
    ContextMenu {
        id: appLauncherContextMenu
        anchorItem: appLauncherIcon
        position: ConfigService.position
        baseColor: ThemeService.backgroundColor
        foregroundColor: ThemeService.foregroundColor
        property bool hasBeenVisible: false

        function rebuildItems() {
            setItems([
                {
                    icon: "align-bottom",
                    label: "底部吸附",
                    cmd: "bottom",
                    checkable: true,
                    checked: AppLauncherConfigService.displayMode === "bottom"
                },
                {
                    icon: "align-center",
                    label: "底部紧凑",
                    cmd: "bottomWide",
                    checkable: true,
                    checked: AppLauncherConfigService.displayMode === "bottomWide"
                },
                {
                    icon: "align-center",
                    label: "屏幕居中",
                    cmd: "center",
                    checkable: true,
                    checked: AppLauncherConfigService.displayMode === "center"
                },
                {
                    icon: "align-fullscreen",
                    label: "全屏覆盖",
                    cmd: "fullscreen",
                    checkable: true,
                    checked: AppLauncherConfigService.displayMode === "fullscreen"
                },
                { separator: true },
                { icon: "preferences-system", label: "启动台设置…", cmd: "settings" }
            ])
        }

        function setDockPopupVisible(shouldOpen) {
            if (shouldOpen) {
                rebuildItems()
                show()
            } else {
                hide()
            }
        }

        onAboutToShow: hasBeenVisible = true
        onAboutToHide: {
            if (hasBeenVisible) {
                hasBeenVisible = false
                if (DockModelService.activeDockPopup === appLauncherContextMenu)
                    DockModelService.releaseDockPopup(appLauncherContextMenu)
            }
        }

        onAction: function(cmd) {
            if (cmd === "settings") {
                DesktopAppLauncher.openSettings()
            } else if (cmd === "bottom" || cmd === "bottomWide"
                    || cmd === "center" || cmd === "fullscreen") {
                AppLauncherConfigService.updateDisplayMode(cmd)
            }
        }
    }

    DockTrashConfirmPopup {
        id: trashConfirmPopup
        anchorItem: trashIcon
    }

    // A Dock panel cannot receive pointer events from the rest of the
    // desktop. WindowService does observe focus changes, which lets an edit
    // session end naturally when the user clicks any other application.
    Connections {
        target: WindowService
        function onActiveWindowIdChanged() {
            if (container.editMode)
                container.editMode = false
        }
    }

    Row {
        id: contentRow
        // Side docks rotate the whole row 90 degrees: the horizontal layout
        // becomes a vertical stack without duplicating the content tree.
        // DockIcon counter-rotates its image so the icons stay upright.
        rotation: container.vertical ? 90 : 0
        transformOrigin: Item.Center
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: container.itemSpacing
        leftPadding: container.hPadding
        rightPadding: container.hPadding
        height: container.computedDockHeight

        Loader {
            id: leadingAccessoryLoader
            active: container.leadingAccessory !== null
            sourceComponent: container.leadingAccessory
            width: active && item ? item.implicitWidth : 0
            height: container.computedDockHeight
            visible: active
        }

        DockDivider {
            dockHeight: container.computedDockHeight
            dividerWidth: 2
            sideMargin: container.dividerMargin
            visible: leadingAccessoryLoader.active
        }

        // ── Pinned apps ──
        // Fixed launcher slot. This project-owned image avoids icon-theme
        // lookup differences. Keeping it outside the Repeater makes it
        // immutable with respect to pinned-app ordering.
        DockIcon {
            id: appLauncherIcon
            magnificationRoot: container
            magnificationPointer: container.magnificationPointer
            targetScreen: container.targetScreen
            surfaceOriginX: container.surfaceOriginX
            surfaceOriginY: container.surfaceOriginY
            vertical: container.vertical
            iconSize: container.iconSize
            activeBackgroundGap: container.activeBackgroundGap
            // 启动器 logo 是仓库里的位图原作（1024²），走文件而不是内联
            // 降采样副本 —— 后者在 Dock 尺寸下明显发糊。
            iconSource: Qt.resolvedUrl("../../assets/applauncher.svg")
            displayName: "应用程序"
            showContextMenu: false
            customContextMenu: true
            allowEdit: false
            dismissAppLauncherOnInteraction: false
            isPinnedItem: false
            onActivate: {
                if (container.isEditing) {
                    container.editMode = false
                    return
                }
                container.editMode = false
                if (DockModelService.activeDockPopup)
                    DockModelService.setDockPopupVisible(
                        DockModelService.activeDockPopup, false)
                AppLauncherService.toggle()
            }
            onContextRequested: DockModelService.openDockPopup(appLauncherContextMenu)
        }

        // Permanent shell control, kept on the left with the app launcher and
        // intentionally outside the pinned-app model and its drag ordering.
        DockIcon {
            id: trashIcon
            magnificationRoot: container
            magnificationPointer: container.magnificationPointer
            targetScreen: container.targetScreen
            surfaceOriginX: container.surfaceOriginX
            surfaceOriginY: container.surfaceOriginY
            vertical: container.vertical
            iconSize: container.iconSize
            activeBackgroundGap: container.activeBackgroundGap
            // 回收站是这条统一链路的例外：图案跟随系统图标主题。
            iconSource: SystemIconResolver.source("trash",
                DockTrashService.hasItems ? "full" : "empty")
            displayName: "回收站"
            showContextMenu: false
            customContextMenu: true
            allowEdit: false
            isPinnedItem: false
            onActivate: {
                if (container.isEditing) {
                    container.editMode = false
                    return
                }
                DockTrashService.open()
            }
            onContextRequested: DockModelService.openDockPopup(trashContextMenu)
        }

        Connections {
            target: DockTrashService
            function onDepositReceived() {
                trashIcon.acknowledgeAttention()
            }
        }

        Repeater {
            id: pinnedRepeater
            model: DockModelService.pinnedItems
            delegate: Item {
                id: pinnedItemLoader
                required property var modelData
                required property int index
                property real lastDragX: 0
                property var itemData: modelData
                property int pinnedIndex: index
                property bool dragged: false
                property real lastDragOffsetX: 0
                // The DragHandler clears translation as soon as the pointer is
                // released. Keep a visual anchor for one layout frame so the
                // source never flashes back to its old slot before the reordered
                // Repeater geometry is ready.
                property bool settling: false
                property real releaseCenterX: 0
                readonly property real dragPointerX: reorderDrag.active
                    ? pinnedItemLoader.x + pinnedItemLoader.width / 2
                      + reorderDrag.translation.x : -1
                // Keep the Row in charge of geometry while the visual item
                // follows the pointer above it. This leaves a clear gap at
                // the original position and avoids fighting Row's layout.
                property real dragOffsetX: {
                    if (reorderDrag.active)
                        return reorderDrag.translation.x
                    if (settling)
                        return releaseCenterX - (pinnedItemLoader.x
                            + pinnedItemLoader.width / 2)
                    return 0
                }
                readonly property real reorderOffsetX: {
                    const source = container.draggedPinnedLoader
                    const destination = container.dragInsertIndex
                    if (!source || source === pinnedItemLoader || destination < 0)
                        return 0
                    const slotStep = pinnedItemLoader.width + container.itemSpacing
                    if (destination < source.pinnedIndex
                            && pinnedItemLoader.pinnedIndex >= destination
                            && pinnedItemLoader.pinnedIndex < source.pinnedIndex)
                        return slotStep
                    if (destination > source.pinnedIndex
                            && pinnedItemLoader.pinnedIndex <= destination
                            && pinnedItemLoader.pinnedIndex > source.pinnedIndex)
                        return -slotStep
                    return 0
                }
                property real visualOffsetX: dragOffsetX + reorderOffsetX
                readonly property real iconSlotWidth: container.iconSize
                    + container.activeBackgroundGap * 2
                readonly property int extraWindowCount: itemData.type === "app"
                    ? (itemData.extraWindows?.length ?? 0) : 0
                width: iconSlotWidth * (1 + extraWindowCount)
                    + container.itemSpacing * extraWindowCount
                // Row places delegates at y=0; keep the delegate dock-height
                // tall so the nested square icon can remain vertically centred.
                height: container.computedDockHeight
                z: reorderDrag.active || settling ? 10 : 0
                scale: reorderDrag.active || settling ? 1.10 : 1.0
                opacity: reorderDrag.active || settling ? 0.88 : 1.0
                transformOrigin: Item.Center
                layer.enabled: reorderDrag.active || settling
                transform: Translate { x: pinnedItemLoader.visualOffsetX }
                Behavior on visualOffsetX {
                    // The dragged source follows immediately. Neighbours ease
                    // out of the way as the candidate insertion slot changes;
                    // after release, the source uses the same easing to land
                    // from its anchored pointer position into the new slot.
                    enabled: pinnedItemLoader !== container.draggedPinnedLoader
                        || pinnedItemLoader.settling
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                }
                // Releasing a drag commits the reordered top-level app.
                DragHandler {
                    id: reorderDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    xAxis.enabled: true
                    yAxis.enabled: false
                    onActiveChanged: {
                        if (active) {
                            // A deliberate drag is an alternate entry point
                            // into edit mode. It ends automatically when the
                            // drop settles; a new drag re-enters it, so no
                            // explicit session is kept between drags.
                            editExitTimer.stop()
                            container.editMode = true
                            pinnedItemLoader.dragged = true
                            pinnedItemLoader.settling = false
                            pinnedItemLoader.lastDragOffsetX = 0
                            container.draggedPinnedLoader = pinnedItemLoader
                            return
                        }
                        if (!pinnedItemLoader.dragged)
                            return

                        // `translation` is measured from this Loader's start
                        // position, so it gives the actual visual centre in
                        // contentRow coordinates without centroid-space
                        // ambiguity.
                        const center = pinnedItemLoader.x
                                + pinnedItemLoader.width / 2
                                + pinnedItemLoader.lastDragOffsetX
                        let nearestIndex = pinnedItemLoader.pinnedIndex
                        let nearestDistance = Number.POSITIVE_INFINITY
                        for (let i = 0; i < pinnedRepeater.count; i++) {
                            const candidate = pinnedRepeater.itemAt(i)
                            if (!candidate)
                                continue
                            const candidateCenter = candidate.x + candidate.width / 2
                            const distance = Math.abs(center - candidateCenter)
                            if (distance < nearestDistance) {
                                nearestDistance = distance
                                nearestIndex = i
                            }
                        }
                        // Preserve the pointer-release position until Row has
                        // received the new model order. `settleTimer` then lets
                        // the visual source glide into its new, real slot.
                        pinnedItemLoader.releaseCenterX = center
                        pinnedItemLoader.settling = true
                        DockModelService.movePinnedItem(
                                    pinnedItemLoader.itemData.type,
                                    pinnedItemLoader.itemData.appId,
                                    nearestIndex)
                        settleTimer.restart()
                    }
                    // DragHandler clears translation during deactivation,
                    // before onActiveChanged(false) runs. Keep the final
                    // non-zero value for the release transaction above.
                    onTranslationChanged: {
                        if (active)
                            pinnedItemLoader.lastDragOffsetX = translation.x
                    }
                }

                Timer {
                    id: settleTimer
                    // A frame lets the Repeater/Row commit its new geometry;
                    // clearing the anchor sooner is the old-slot flash seen on
                    // pointer release.
                    interval: 16
                    repeat: false
                    onTriggered: {
                        pinnedItemLoader.settling = false
                        pinnedItemLoader.dragged = false
                        if (container.draggedPinnedLoader === pinnedItemLoader)
                            container.draggedPinnedLoader = null
                        // The drag session is complete; editing ends with the
                        // drop. Reordering again simply starts a new drag.
                        container.editMode = false
                    }
                }

                Row {
                            anchors.centerIn: parent
                            spacing: container.itemSpacing

                            DockIcon {
                                magnificationRoot: container
                                magnificationPointer: container.magnificationPointer
                                targetScreen: container.targetScreen
                                surfaceOriginX: container.surfaceOriginX
                                surfaceOriginY: container.surfaceOriginY
                                vertical: container.vertical
                                dockEdge: ConfigService.position
                                iconSize: container.iconSize
                                activeBackgroundGap: container.activeBackgroundGap
                                iconSource: pinnedItemLoader.itemData.icon ?? ""
                                displayName: pinnedItemLoader.itemData.name ?? ""
                                isRunning: pinnedItemLoader.itemData.isRunning ?? false
                                windowCount: pinnedItemLoader.itemData.windowCount ?? 0
                                isActivated: DockModelService.isAppActivated(
                                    pinnedItemLoader.itemData.appId ?? "")
                                isUrgent: pinnedItemLoader.itemData.isUrgent ?? false
                                appId: pinnedItemLoader.itemData.appId ?? ""
                                isWindowItem: false
                                isPinnedItem: true
                                editMode: container.isEditing
                                isDragging: reorderDrag.active || pinnedItemLoader.settling
                                onRequestEdit: container.editMode = true
                                onRequestEditExit: container.editMode = false
                                onActivate: {
                                    // DockIcon also guards this, but keeping the
                                    // action boundary defensive ensures pinned
                                    // apps can never launch while sorting.
                                    if (!container.isEditing)
                                        DockModelService.activateApp(appId)
                                }
                            }

                            Repeater {
                                model: pinnedItemLoader.itemData.extraWindows ?? []
                                delegate: DockIcon {
                                    required property var modelData
                                    magnificationRoot: container
                                    magnificationPointer: container.magnificationPointer
                                    targetScreen: container.targetScreen
                                    surfaceOriginX: container.surfaceOriginX
                                    surfaceOriginY: container.surfaceOriginY
                                    vertical: container.vertical
                                    dockEdge: ConfigService.position
                                    iconSize: container.iconSize
                                    activeBackgroundGap: container.activeBackgroundGap
                                    iconSource: modelData.iconSource
                                        ?? modelData.identity.iconSource ?? ""
                                    displayName: modelData.title ?? ""
                                    isRunning: true
                                    windowCount: 1
                                    isActivated: modelData.toplevel.activated ?? false
                                    isUrgent: modelData.isUrgent ?? false
                                    appId: modelData.identity.desktopId ?? ""
                                    windowId: modelData.windowId ?? ""
                                    animationWindowId: modelData.provider === "kwin"
                                        ? String(modelData.handleId ?? "") : ""
                                    isWindowItem: true
                                    isPinnedItem: false
                                    onActivate: {
                                        container.editMode = false
                                        DockModelService.toggleWindow(windowId)
                                    }
                                }
                            }
                        }

            }
        }

        // ── Divider: persistent launchers | temporary windows ──
        DockDivider {
            dockHeight: container.computedDockHeight
            // Make the app/window boundary read as a deliberate section break.
            dividerWidth: 2
            sideMargin: container.dividerMargin
            lineColor: Qt.rgba(1, 1, 1, 1)
            lineOpacity: 0.46
            lineRadius: 999
            visible: pinnedRepeater.count > 0 && windowsRepeater.count > 0
        }

        // ── Unpinned window tasks ──
        Repeater {
            id: windowsRepeater
            model: DockModelService.windowModel
            delegate: DockIcon {
                magnificationRoot: container
                magnificationPointer: container.magnificationPointer
                targetScreen: container.targetScreen
                surfaceOriginX: container.surfaceOriginX
                surfaceOriginY: container.surfaceOriginY
                vertical: container.vertical
                dockEdge: ConfigService.position
                iconSize: container.iconSize
                activeBackgroundGap: container.activeBackgroundGap
                iconSource: model.icon ?? ""
                displayName: model.title ?? ""
                isRunning: true
                windowCount: model.windowCount ?? 1
                isActivated: model.isActivated ?? false
                isUrgent: model.isUrgent ?? false
                appId: model.appId ?? ""
                windowId: model.isWindowItem ? (model.windowId ?? "") : ""
                animationWindowId: model.effectWindowId ?? ""
                isWindowItem: model.isWindowItem ?? false
                isPinnedItem: false
                onActivate: {
                    container.editMode = false
                    if (model.isWindowItem)
                        DockModelService.toggleWindow(model.windowId)
                    else
                        DockModelService.activateApp(model.appId)
                }
            }
        }

        // ── Stretch slack: push the information slot to the far end ──
        // Only a stretched dock has slack. Spending it between the window
        // tasks and the information slot keeps launchers and running windows
        // against the starting edge while the clock, weather and the trailing
        // status area sit at the opposite one — a taskbar-style split. The
        // spacer carries no content, so an auto-width dock collapses it to 0
        // and the row keeps its historical compact layout.
        Item {
            width: container.relaxed ? container.distributionSlack : 0
            height: 1
            visible: width > 0
        }

        // ── Divider 2: windows | information slot (conditional) ──
        DockDivider {
            dockHeight: container.computedDockHeight
            dividerWidth: 2
            sideMargin: container.dividerMargin
            visible: container.hasInfo
        }

        // ── Shared music / weather / clock / temperature information slot ──
        DockInfoCarousel {
            id: horizontalInfoCarousel
            iconSize: container.iconSize
            dockHeight: container.computedDockHeight
            widthUnits: container.infoUnits
            showClock: container.hasClock
            showTemperature: container.hasTemperature
            cardOrder: ConfigService.infoCardOrder
            expanded: container.infoExpanded
            autoRotate: ConfigService.infoCardAutoRotate
            onEditRequested: componentEditor.openFor(horizontalInfoCarousel)
            visible: container.hasInfo && !container.vertical
        }

        // Counter-rotated, one-line counterpart for side Docks. The parent
        // Row rotates 90 degrees, so this component keeps text upright while
        // reserving only two icon lengths along the edge.
        DockSideInfoCarousel {
            id: verticalInfoCarousel
            iconSize: container.iconSize
            dockHeight: container.computedDockHeight
            widthUnits: container.infoUnits
            showClock: container.hasClock
            showTemperature: container.hasTemperature
            cardOrder: ConfigService.infoCardOrder
            expanded: container.infoExpanded
            autoRotate: ConfigService.infoCardAutoRotate
            onEditRequested: componentEditor.openFor(verticalInfoCarousel)
            visible: container.hasInfo && container.vertical
        }

        DockDivider {
            dockHeight: container.computedDockHeight
            dividerWidth: 2
            sideMargin: container.dividerMargin
            visible: trailingAccessoryLoader.active
        }

        Loader {
            id: trailingAccessoryLoader
            active: container.trailingAccessory !== null
            sourceComponent: container.trailingAccessory
            width: active && item ? item.implicitWidth : 0
            height: container.computedDockHeight
            visible: active
        }
    }

    Rectangle {
        id: componentEditButton
        z: 80
        visible: container.editMode
        anchors { top: parent.top; right: parent.right; margins: 4 }
        width: componentEditLabel.implicitWidth + 22
        height: 26
        radius: AppearanceTokens.isMaterial ? 13 : 9
        color: AppearanceTokens.surface.pick(
            AppearanceTokens.colors.primaryContainer,
            ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.16)
                : Qt.rgba(1, 1, 1, 0.92))
        border.width: 1
        border.color: AppearanceTokens.surface.pick(
            AppearanceTokens.colors.primary,
            Qt.rgba(ThemeService.foregroundColor.r,
                ThemeService.foregroundColor.g,
                ThemeService.foregroundColor.b, 0.18))

        Text {
            id: componentEditLabel
            anchors.centerIn: parent
            text: "+ 组件"
            color: AppearanceTokens.surface.pick(
                AppearanceTokens.colors.primaryContainerForeground,
                ThemeService.foregroundColor)
            font { pixelSize: 10; weight: Font.DemiBold }
        }

        TapHandler {
            onTapped: componentEditor.openFor(componentEditButton)
        }
    }

    DockComponentEditor {
        id: componentEditor
        onVisibleChanged: {
            if (visible)
                container.editMode = true
        }
    }
}
