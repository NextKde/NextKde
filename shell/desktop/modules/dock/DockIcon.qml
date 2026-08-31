import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.applauncher

// ────────────────────────────────────────────────────────────────
// DockIcon — Single icon in the dock.
// Used for both pinned launcher icons and open window icons.
//
// Hover: gentle NumberAnimation via Behavior.
// ────────────────────────────────────────────────────────────────

Item {
    id: icon

    // ═══════════════════════════════════════════════════════════
    // Inputs
    // ═══════════════════════════════════════════════════════════
    property int    iconSize:    44
    property string iconSource:  ""
    // Optional bundled-font glyph for shell controls. Unlike a themed icon
    // name it is guaranteed to render even when the active KDE theme lacks it.
    property string glyph:       ""
    property string displayName: ""
    property string appId:       ""
    property string windowId:    ""
    // KWin's real internal UUID, kept separate from WindowService's synthetic
    // windowId used by Dock actions and previews.
    property string animationWindowId: ""
    // The owning DockWindow supplies its real layer-surface origin. QWindow's
    // mapToGlobal is not reliable for layer-shell surfaces on Wayland,
    // especially when the Dock lives on a non-primary output.
    property var targetScreen: null
    property real surfaceOriginX: 0
    property real surfaceOriginY: 0
    // `isRunning` is visual runtime state. `isWindowItem` identifies which
    // context-menu actions are valid, because a pinned running app has no
    // single windowId even though it displays a running indicator.
    property bool   isWindowItem: false
    // A non-window item can be either a fixed launcher or an unpinned running
    // app aggregate. The context menu needs this distinction for pin/unpin.
    property bool   isPinnedItem: false
    // A visual-only DockIcon (the fixed application launcher) deliberately
    // shares sizing and rendering with tasks without exposing task actions.
    property bool   interactive: true
    // Any normal Dock task is an interaction outside the launcher sheet and
    // should dismiss it first. The fixed launcher icon opts out so it can
    // keep its expected toggle behavior.
    property bool   dismissAppLauncherOnInteraction: true
    // Shell controls can use the standard left-click activation pipeline while
    // opting out of application-specific right-click context-menu actions.
    property bool   showContextMenu: true
    // Fixed shell controls can keep DockIcon's complete visual/hover behavior
    // while routing their right click to a dedicated native menu.
    property bool   customContextMenu: false
    // The fixed launcher is not a persisted pinned app, so holding it must not
    // enter the pinned-app edit/reorder state.
    property bool   allowEdit: true
    property bool   isRunning:   false
    property bool   isActivated: false
    // Urgency is independent from activation. A window requesting attention
    // paints an orange-red slot until the compositor clears that state.
    property bool   isUrgent:    false
    // Pinned delegates enable this while a sibling is being dragged. Window
    // icons intentionally leave it false.
    property bool   editMode: false
    property bool   isDragging: false
    // A small neutral marker for persistent shell-control state, currently
    // used by the Trash icon while it contains recoverable items.
    property bool   statusBadge: false
    // This is proportional to iconSize (3px when iconSize is 44px). It is
    // also included in AdaptiveMath, so the active background never overlaps
    // a neighbour or makes the real Row wider than the calculated width.
    property real   activeBackgroundGap: 4.4
    // Side-dock layout: the whole row is rotated 90 degrees; the icon image
    // counter-rotates so the artwork stays upright.
    property bool   vertical: false
    // Which screen edge the dock is attached to: "bottom", "left" or
    // "right". The running dot sits on the icon edge facing that edge —
    // below the icon on a bottom dock, on the screen-edge side of side docks.
    property string dockEdge: "bottom"
    // Active task backgrounds are painted locally for reliability.
    // The shared indicator approach caused coordinate bugs during layout changes.
    property bool   useSharedActiveBackground: false

    // Active background radius is proportional to the icon height. This is
    // intentionally independent from the icon/background gap.
    readonly property real activeBackgroundRadius: iconSize
        * AppearanceTokens.dock.activeRadiusRatio
    readonly property real iconSlotSize: iconSize + activeBackgroundGap * 2
    readonly property bool dotIndicator:
        AppearanceTokens.dock.indicatorStyle === "dot"
    readonly property real runningIndicatorWidth: dotIndicator
        ? Math.max(4, Math.round(iconSize * AppearanceTokens.dock.indicatorLengthRatio))
        : Math.max(12, Math.round(iconSize * AppearanceTokens.dock.indicatorLengthRatio))
    readonly property real runningIndicatorHeight: dotIndicator
        ? runningIndicatorWidth
        : Math.max(3, Math.round(iconSize
            * AppearanceTokens.dock.indicatorThicknessRatio))
    readonly property real runningIndicatorGap: Math.max(1,
        (iconSize * AppearanceTokens.dock.verticalPaddingRatio
            - runningIndicatorHeight) / 2)
    readonly property real activeBackgroundAlpha: {
        const configuredAlpha = ConfigService.iconMode === "color"
            ? 0.5 : Math.max(0.1, ConfigService.iconOpacity)
        if (AppearanceTokens.dock.activeBackgroundMode === "tonal")
            return Math.min(0.34, configuredAlpha)
        if (AppearanceTokens.dock.activeBackgroundMode === "subtle")
            return Math.min(0.22, configuredAlpha)
        return configuredAlpha
    }
    readonly property bool showActiveBackground: isRunning && isActivated
    readonly property bool showUrgentBackground: isRunning && isUrgent
        && !showActiveBackground

    signal activate()
    signal requestEdit()
    // Emitted when a plain tap (not the press-and-hold that started editing)
    // lands on the icon while editing; the owning surface ends its edit state.
    signal requestEditExit()
    signal contextRequested()
    property bool _heldForEdit: false
    property real _windowHandoffOpacity: 1.0
    opacity: _windowHandoffOpacity

    function playWindowToIconHandoff(durationMs) {
        windowHandoffOpacity.stop()
        _windowHandoffOpacity = 1.0
        windowHandoffPause.duration = Math.max(0, Number(durationMs) - 210)
        windowHandoffOpacity.start()
    }

    SequentialAnimation {
        id: windowHandoffOpacity
        PauseAnimation {
            id: windowHandoffPause
            duration: 270
        }
        NumberAnimation {
            target: icon
            property: "_windowHandoffOpacity"
            from: 1.0
            to: 0.0
            duration: 50
            easing.type: Easing.Linear
        }
        PauseAnimation { duration: 150 }
        NumberAnimation {
            target: icon
            property: "_windowHandoffOpacity"
            from: 0.0
            to: 1.0
            duration: 10
            easing.type: Easing.Linear
        }
    }

    // KWin's private KOS Effect consumes compositor-global icon rectangles.
    // The target uses the stable slot centre rather than iconImage's hover
    // scale/lift. Ancestor transforms still preserve the Dock's live hide and
    // surface scale, while minimize/restore now share one exact centre.
    function windowAnimationTarget() {
        if (!icon.visible || !icon.appId || icon.iconSize <= 0)
            return null
        const slotParent = icon.parent
        const centerX = icon.x + icon.width / 2
        const centerY = icon.y + icon.height / 2
        const topLeft = slotParent
            ? slotParent.mapToItem(null, centerX - icon.iconSize / 2,
                                   centerY - icon.iconSize / 2)
            : iconImage.mapToItem(null, 0, 0)
        const bottomRight = slotParent
            ? slotParent.mapToItem(null, centerX + icon.iconSize / 2,
                                   centerY + icon.iconSize / 2)
            : iconImage.mapToItem(null, iconImage.width, iconImage.height)
        const left = icon.surfaceOriginX
            + Math.min(topLeft.x, bottomRight.x)
        const top = icon.surfaceOriginY
            + Math.min(topLeft.y, bottomRight.y)
        const targetWidth = Math.abs(bottomRight.x - topLeft.x)
        const targetHeight = Math.abs(bottomRight.y - topLeft.y)
        if (targetWidth < 1 || targetHeight < 1)
            return null
        let animationIconSource = String(icon.iconSource || "")
        // Compatibility for icons resolved before AppPresentationService was
        // changed to preserve local files. KWin cannot access Quickshell's
        // private image provider, but it can read the underlying PNG.
        if (animationIconSource.startsWith("image://icon//"))
            animationIconSource = animationIconSource.substring("image://icon/".length)
        return {
            appId: icon.appId,
            windowId: icon.animationWindowId,
            // KWin uses the same artwork as this Dock delegate during the
            // final thumbnail-to-icon texture handoff. Most application
            // icons resolve to a local file URL; the effect falls back to
            // EffectWindow::icon() for providers it cannot read directly.
            iconSource: animationIconSource,
            dockEdge: icon.dockEdge,
            outputName: icon.targetScreen ? icon.targetScreen.name : "",
            x: left,
            y: top,
            width: targetWidth,
            height: targetHeight
        }
    }

    Component.onCompleted: DockWindowAnimationTargetService.registerIcon(icon)
    Component.onDestruction: DockWindowAnimationTargetService.unregisterIcon(icon)
    onAppIdChanged: DockWindowAnimationTargetService.schedulePublish()
    onWindowIdChanged: DockWindowAnimationTargetService.schedulePublish()
    onAnimationWindowIdChanged: DockWindowAnimationTargetService.schedulePublish()
    onIconSourceChanged: DockWindowAnimationTargetService.schedulePublish()
    onVisibleChanged: DockWindowAnimationTargetService.schedulePublish()
    onIconSizeChanged: DockWindowAnimationTargetService.schedulePublish()

    // Reserve the background's outer slot for every app icon. Only the active
    // window paints it; reserving the slot prevents focus changes from moving
    // the surrounding icons.
    width:  iconSlotSize
    height: iconSlotSize
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    // ═══════════════════════════════════════════════════════════
    // Scale model
    // ═══════════════════════════════════════════════════════════
    // Final scale: 1.0 (or larger on hover).
    property real _targetScale: _hovering
        ? AppearanceTokens.dock.hoverScale : 1.0
    // Lift non-focused tasks to make pointer feedback unmistakable. The active
    // task keeps its shared background vertically stable, while scale alone
    // still makes its hover state clear.
    readonly property real _hoverLift: _hovering && !showActiveBackground
        && AppearanceTokens.dock.hoverLiftRatio > 0
        ? -Math.max(2, Math.round(iconSize
            * AppearanceTokens.dock.hoverLiftRatio)) : 0
    property real _attentionScale: 1.0
    property real _attentionLift: 0
    property real _attentionGlow: 0
    scale: _targetScale * _attentionScale
    // The icon artwork is cached in `iconImage`/`GlassText` below instead of
    // on this whole item: an offscreen texture is sized to the item's bounds
    // and clips overflow, which would hide the running/status indicators
    // that deliberately extend past the icon edge.
    transform: Translate {
        y: icon._hoverLift + icon._attentionLift
        Behavior on y {
            NumberAnimation {
                duration: DockAnimation.iconHoverDuration
                easing.type: DockAnimation.iconHoverEasing
            }
        }
    }

    function acknowledgeAttention() {
        _attentionScale = 1.0
        _attentionLift = 0
        _attentionGlow = 0
        attentionPulse.restart()
    }
    SequentialAnimation {
        id: attentionPulse
        ParallelAnimation {
            NumberAnimation { target: icon; property: "_attentionScale"; to: 1.18; duration: 115; easing.type: Easing.OutCubic }
            NumberAnimation { target: icon; property: "_attentionLift"; to: -6; duration: 115; easing.type: Easing.OutCubic }
            NumberAnimation { target: icon; property: "_attentionGlow"; to: 1.0; duration: 115; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: icon; property: "_attentionScale"; to: 1.0; duration: 210; easing.type: Easing.OutBack }
            NumberAnimation { target: icon; property: "_attentionLift"; to: 0; duration: 210; easing.type: Easing.OutBounce }
            NumberAnimation { target: icon; property: "_attentionGlow"; to: 0; duration: 210; easing.type: Easing.OutCubic }
        }
    }

    // ── Hover animation ──
    property bool _hovering: false
    readonly property var _appWindows: {
        WindowService.revision
        if (icon.windowId) {
            const win = WindowService.windowById(icon.windowId)
            return win ? [win] : []
        }
        if (icon.appId)
            return WindowService.windowsForApp(icon.appId)
        return []
    }
    readonly property bool _hasWindows: _appWindows.length > 0
    readonly property string _previewWindowId: _hasWindows ? _appWindows[0].windowId : (icon.windowId || "")
    readonly property int _effectiveWindowCount: _hasWindows ? _appWindows.length : (icon.isRunning ? 1 : 0)

    Behavior on scale {
        NumberAnimation {
            duration: DockAnimation.iconHoverDuration
            easing.type: DockAnimation.iconHoverEasing
        }
    }

    Timer {
        id: previewDelay
        // Previews dwell time: 600ms responsive hover
        interval: 600
        repeat: false
        onTriggered: {
            if (icon._hovering && icon._hasWindows && !icon.editMode
                    && !DockModelService.activeContextMenu) {
                console.log("[DockIcon] preview request app=" + icon.appId
                    + " windowCount=" + icon._appWindows.length);
                preview.appId = icon.appId
                preview.windowId = icon._previewWindowId
                preview.title = WindowService.windowById(icon._previewWindowId)?.title
                    ?? icon.displayName
                preview.windows = icon._appWindows
                DockModelService.openDockPopup(preview)
            } else if (icon._hovering && icon.isRunning) {
                console.log("[DockIcon] preview skipped app=" + icon.appId
                    + " no window record")
            }
        }
    }

    // The preview is a separate Wayland surface. Leave a comfortable hand-off window
    // after the pointer exits the icon so it can cross the anchor gap and enter
    // the preview smoothly without premature dismissal.
    Timer {
        id: previewCloseDelay
        interval: 480
        repeat: false
        onTriggered: {
            if (!icon._hovering && !preview.pointerInside)
                DockModelService.setDockPopupVisible(preview, false)
        }
    }

    // iPadOS-style edit-state wiggle. The held icon stays steady so it reads
    // as the object under direct manipulation rather than a background item.
    SequentialAnimation {
        id: editWiggle
        running: icon.editMode && !icon.isDragging
        loops: Animation.Infinite
        NumberAnimation {
            target: icon; property: "rotation"
            from: -3.4; to: 3.4; duration: 105
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: icon; property: "rotation"
            from: 3.4; to: -3.4; duration: 115
            easing.type: Easing.InOutSine
        }
        onRunningChanged: {
            if (!running)
                icon.rotation = 0
        }
    }

    // ═══════════════════════════════════════════════════════════
    // Icon image
    // ═══════════════════════════════════════════════════════════
    Rectangle {
        id: activeBackground
        width: icon.iconSlotSize
        height: icon.iconSlotSize
        anchors.centerIn: parent
        radius: icon.activeBackgroundRadius
        // The active window paints a white slot; urgency paints orange-red.
        // Both are local to the icon, so the highlight always tracks its task
        // without any shared indicator or geometry tracking.
        color: icon.showActiveBackground
            ? (AppearanceTokens.dock.activeBackgroundMode === "tonal"
                ? Qt.rgba(ThemeService.accentColor.r,
                    ThemeService.accentColor.g, ThemeService.accentColor.b,
                    icon.activeBackgroundAlpha)
                : AppearanceTokens.dock.activeBackgroundMode === "subtle"
                    ? Qt.rgba(1, 1, 1, icon.activeBackgroundAlpha)
                    : Qt.rgba(1, 1, 1, icon.activeBackgroundAlpha))
            : Qt.rgba(1.0, 0.30, 0.12, icon.activeBackgroundAlpha)
        visible: (icon.showActiveBackground && !icon.useSharedActiveBackground)
            || icon.showUrgentBackground
        z: -1
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
    }

    // External shell actions need feedback that stays visible even when the
    // Dock's internal scale transform is constrained by its layout. This ring
    // is a separate painted layer behind the icon.
    Rectangle {
        width: icon.iconSlotSize * 1.28
        height: width
        anchors.centerIn: parent
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.72)
        opacity: icon._attentionGlow * 0.48
        scale: 0.80 + icon._attentionGlow * 0.35
        visible: opacity > 0
        z: -2
    }

    // A faint white slot gives hover a little contrast on liquid glass without
    // changing the icon's reserved geometry. Focused and urgent tasks already
    // have stronger state backgrounds, so they intentionally do not stack it.
    Rectangle {
        id: hoverHighlight
        width: icon.iconSize
        height: icon.iconSize
        anchors.centerIn: parent
        radius: icon.activeBackgroundRadius
        color: Qt.rgba(1, 1, 1, 0.12)
        opacity: icon._hovering && !icon.showActiveBackground
            && !icon.showUrgentBackground ? 1.0 : 0.0
        visible: opacity > 0.0
        z: -1

        Behavior on opacity {
            NumberAnimation {
                duration: DockAnimation.iconHoverDuration
                easing.type: DockAnimation.iconHoverEasing
            }
        }
    }

    // A brief brightening on press gives tactile feedback without any
    // geometry work: pure opacity on the already-cached icon layer. The
    // fade uses directional semantics — decelerate on press, accelerate on
    // release — so the feedback reads as push in / relax out.
    Rectangle {
        id: pressHighlight
        width: icon.iconSize
        height: icon.iconSize
        anchors.centerIn: parent
        radius: icon.activeBackgroundRadius
        color: Qt.rgba(1, 1, 1, 0.12)
        opacity: 0.0
        visible: opacity > 0.0
        z: -1
    }
    NumberAnimation {
        id: pressFadeIn
        target: pressHighlight
        property: "opacity"
        to: 1.0
        duration: 150
        easing.type: DockAnimation.elementEnterEasing
    }
    NumberAnimation {
        id: pressFadeOut
        target: pressHighlight
        property: "opacity"
        to: 0.0
        duration: 150
        easing.type: DockAnimation.elementExitEasing
    }

    AppIcon {
        id: iconImage
        width: icon.iconSize
        height: icon.iconSize
        anchors.centerIn: parent
        source: icon.iconSource || ""
        // A newly opened window has no previous Dock texture to retain. Decode
        // this small themed icon before its first frame instead of exposing an
        // empty Image/ShaderEffect while several windows arrive together.
        asynchronous: false
        visible: !icon.glyph
        rotation: icon.vertical ? -90 : 0
        transformOrigin: Item.Center
        // Cache the icon bitmap so scale animations (hover, attention pulse)
        // transform a cached texture instead of re-rasterizing the image on
        // the main thread (measured 100% CPU under the heaviest scale
        // animation; 4.8% with the layer enabled). Only the artwork itself
        // is layered: the texture is sized to this item's bounds, so caching
        // the whole DockIcon would clip the indicators past its edges.
        layer.enabled: true
        layer.smooth: true

        // Icon appearance style from ConfigService
        opacityMultiplier: ConfigService.iconMode === "color"
            ? 1.0 : ConfigService.iconOpacity
        saturation: ConfigService.iconSaturation
        tintEnabled: ConfigService.iconTintEnabled
        tintColor: ConfigService.iconTintColor
    }

    Rectangle {
        width: Math.max(5, Math.round(icon.iconSize * 0.15))
        height: width
        anchors { right: parent.right; top: parent.top; rightMargin: 2; topMargin: 2 }
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.88)
        border { width: 1; color: Qt.rgba(0, 0, 0, 0.48) }
        opacity: icon.statusBadge ? 1 : 0
        visible: opacity > 0.01
        z: 2
        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    // Style-driven running indicator: macOS uses dots (single dot for 1 window,
    // multi-dot for multiple windows), Windows a longer underline, and Material a shorter tonal pill.
    Item {
        id: runningIndicator
        width: indicatorRow.implicitWidth
        height: icon.runningIndicatorHeight
        opacity: icon.isRunning ? 1 : 0
        visible: opacity > 0.01
        z: 2
        anchors.horizontalCenter: iconImage.horizontalCenter
        anchors.top: icon.vertical && icon.dockEdge === "right"
            ? undefined : iconImage.bottom
        anchors.bottom: icon.vertical && icon.dockEdge === "right"
            ? iconImage.top : undefined
        anchors.topMargin: icon.runningIndicatorGap
        anchors.bottomMargin: icon.runningIndicatorGap

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Row {
            id: indicatorRow
            anchors.centerIn: parent
            spacing: icon._effectiveWindowCount >= 3 ? 2 : 2.5

            Repeater {
                model: icon.dotIndicator
                    ? Math.min(3, Math.max(1, icon._effectiveWindowCount))
                    : 1
                delegate: Rectangle {
                    required property int index
                    readonly property real dotSize: icon._effectiveWindowCount >= 3
                        ? Math.max(3, icon.runningIndicatorWidth * 0.82)
                        : icon.runningIndicatorWidth
                    width: icon.dotIndicator ? dotSize : icon.runningIndicatorWidth
                    height: icon.dotIndicator ? dotSize : icon.runningIndicatorHeight
                    radius: width / 2
                    color: icon.dotIndicator ? Qt.rgba(1, 1, 1, 0.95)
                        : ThemeService.accentColor
                    border {
                        width: 0
                        color: Qt.rgba(0, 0, 0, 0.40)
                    }
                }
            }
        }
    }

    GlassText {
        anchors.centerIn: parent
        text: icon.glyph
        visible: !!icon.glyph
        rotation: icon.vertical ? -90 : 0
        transformOrigin: Item.Center
        color: Qt.rgba(1, 1, 1, 0.92)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font {
            family: "Font Awesome 7 Free"
            pixelSize: Math.round(icon.iconSize * 0.58)
            weight: Font.Black
        }
        // Same cached-texture rationale as iconImage: glyph text is expensive
        // to re-rasterize under scale animation.
        layer.enabled: true
        layer.smooth: true
    }
    // The active/hover-style background already communicates the focused
    // running app, so no separate running marker is painted.

    // ═══════════════════════════════════════════════════════════
    // Interaction
    // ═══════════════════════════════════════════════════════════
    MouseArea {
        id: _mouseArea
        anchors.fill: parent
        enabled: icon.interactive
        hoverEnabled: true
        acceptedButtons: (icon.showContextMenu || icon.customContextMenu)
            ? Qt.LeftButton | Qt.RightButton : Qt.LeftButton
        // Never resist pointer stealing: a deliberate drag must let the
        // pinned delegate's DragHandler take the grab and reorder directly
        // (macOS-style), not only after a long press enters edit mode. Plain
        // clicks still complete here because the handler only steals after
        // its drag threshold, which cancels this MouseArea instead of
        // emitting clicked.
        preventStealing: false
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            icon._heldForEdit = false
            if (icon.dismissAppLauncherOnInteraction && AppLauncherService.open)
                AppLauncherService.hide()
            pressFadeIn.start()
        }
        onReleased: pressFadeOut.start()
        onCanceled: pressFadeOut.start()
        onPressAndHold: {
            if (!icon.allowEdit)
                return
            // Entering edit mode steals the pointer for reordering; the press
            // feedback should not linger while the icon wiggles.
            pressFadeOut.start()
            icon._heldForEdit = true
            icon.requestEdit()
        }
        onClicked: function(mouse) {
            // Dock editing is spatial manipulation, not app activation. The
            // hold that started editing must not immediately end it, but any
            // later plain tap on a dock icon finishes the session.
            if (icon.editMode) {
                if (!icon._heldForEdit)
                    icon.requestEditExit()
                return
            }
            if (mouse.button === Qt.RightButton) {
                if (icon.customContextMenu) {
                    icon.contextRequested()
                    return
                }
                // A delayed preview may already be armed from pointer entry.
                // Right-click is a distinct interaction and must own the
                // shared popup coordinator until the menu is dismissed.
                previewDelay.stop()
                if (DockModelService.activeContextMenu
                        && DockModelService.activeContextMenu !== contextMenu) {
                    if (DockModelService.activeContextMenu.visible)
                        DockModelService.dismissDockPopupImmediately(
                            DockModelService.activeContextMenu)
                    else
                        DockModelService.activeContextMenu = null
                }
                // Rebuild items from the icon's current state (window task vs
                // pinned launcher, persisted pin state), then open.
                const pinned = icon.isPinnedItem || DockModelService.isAppPinned(icon.appId)
                contextMenu.clear()
                if (icon.isWindowItem) {
                    contextMenu.addItem("", "激活窗口", "activate")
                    contextMenu.addItem("", "最小化", "minimize")
                    contextMenu.addItem("", "关闭窗口", "close")
                    contextMenu.addItem("", "新建窗口", "new_window")
                    contextMenu.addItem(pinned ? "" : "",
                        pinned ? "取消固定" : "固定此应用", pinned ? "unpin" : "pin")
                } else {
                    contextMenu.addItem("", "打开", "open")
                    contextMenu.addItem("", "新建窗口", "new_window")
                    if (icon.isRunning)
                        contextMenu.addItem("", "关闭所有窗口", "close_all")
                    contextMenu.addItem(pinned ? "" : "",
                        pinned ? "取消固定" : "固定此应用", pinned ? "unpin" : "pin")
                }
                DockModelService.activeContextMenu = contextMenu
                DockModelService.openDockPopup(contextMenu)
            } else if (!icon._heldForEdit) {
                icon.activate()
            }
        }
        onEntered: {
            icon._hovering = true
            if (icon._previewWindowId && !icon.editMode
                    && !DockModelService.activeContextMenu)
                previewDelay.restart()
        }
        onExited: {
            icon._hovering = false
            previewDelay.stop()
            previewCloseDelay.restart()
        }
    }

    ContextMenu {
        id: contextMenu
        property bool hasBeenVisible: false
        anchorItem: icon
        position: ConfigService.position
        baseColor: ThemeService.backgroundColor
        foregroundColor: ThemeService.foregroundColor
        onAboutToShow: hasBeenVisible = true
        onAboutToHide: {
            if (hasBeenVisible) {
                hasBeenVisible = false
                if (DockModelService.activeContextMenu === contextMenu)
                    DockModelService.activeContextMenu = null
                DockModelService.releaseDockPopup(contextMenu)
            }
        }
        onAction: function(name) {
            switch (name) {
            case "open":
                DockModelService.activateApp(icon.appId)
                break
            case "new_window":
                DockModelService.launchNewWindow(icon.appId)
                break
            case "close_all":
                const wins = WindowService.windowsForApp(icon.appId)
                for (let i = 0; i < wins.length; i++)
                    WindowService.closeWindow(wins[i].windowId)
                break
            case "unpin":
                AppActionService.unpin(icon.appId)
                break
            case "activate":
                DockModelService.activateWindow(icon.windowId)
                break
            case "minimize":
                DockModelService.minimizeWindow(icon.windowId)
                break
            case "close":
                DockModelService.closeWindow(icon.windowId)
                break
            case "pin":
                AppActionService.pin(icon.appId)
                break
            }
        }
    }

    DockWindowPreview {
        id: preview
        anchorItem: icon
        onPointerInsideChanged: {
            if (pointerInside)
                previewCloseDelay.stop()
            else if (!icon._hovering)
                previewCloseDelay.restart()
        }
        onActivateRequested: {
            DockModelService.activateWindow(preview.windowId)
            DockModelService.setDockPopupVisible(preview, false)
        }
        onVisibleChanged: {
            if (!visible)
                DockModelService.releaseDockPopup(preview)
        }
    }

}
