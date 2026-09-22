import QtQuick
import Quickshell
import Quickshell.Wayland
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
    property string displayName: ""
    property string appId:       ""
    property string windowId:    ""
    // KWin's real internal UUID, kept separate from WindowService's synthetic
    // windowId used by Dock actions and previews.
    property string animationWindowId: ""
    // The icon provider URL deliberately stays stable across KDE theme
    // changes (for example, `image://icon/kate`). Recreate only the image
    // renderer after a theme revision so that stable URL is requested again;
    // the Dock's task Repeater and window model remain intact.
    property bool _iconRendererActive: true
    property Timer _iconRendererReloadTimer: Timer {
        interval: 0
        repeat: false
        onTriggered: icon._iconRendererActive = true
    }
    function _reloadIconRenderer() {
        icon._iconRendererActive = false
        icon._iconRendererReloadTimer.restart()
    }
    property Connections _iconThemeConnections: Connections {
        target: IconThemeReloadService
        function onRevisionChanged() {
            icon._reloadIconRenderer()
        }
    }
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
    property int    windowCount: isRunning ? 1 : 0
    property bool   isActivated: false
    // Urgency is independent from activation. A window requesting attention
    // paints an orange-red slot until the compositor clears that state.
    property bool   isUrgent:    false
    // Pinned delegates enable this while a sibling is being dragged. Window
    // icons intentionally leave it false.
    property bool   editMode: false
    property bool   isDragging: false
    readonly property int notificationCount:
        AppNotificationService.countForApp(icon.appId, icon.displayName)
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
    // Pointer input is kept in DockContainer's local coordinate space. This
    // avoids scene-coordinate mismatches on Wayland layer-shell surfaces.
    property Item magnificationRoot: null
    property point magnificationPointer: Qt.point(-10000, -10000)
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
        const configuredAlpha = IconAppearanceService.mode === "color"
            ? 0.5 : Math.max(0.1, IconAppearanceService.opacity)
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

    // When the compositor's window-to-icon animation finishes, the redirected
    // window texture disappears and the Dock must already show the real icon.
    // Previously the whole icon blinked (opacity 1 -> 0 -> 1) to mask that
    // seam; that read as a flicker on every minimize/restore. Now the icon
    // stays fully opaque and only the AppIcon image is recycled exactly when
    // the animation completes, so the handoff has no visible flash.
    function playWindowToIconHandoff(durationMs) {
        windowHandoffTimer.interval = Math.max(0, Number(durationMs) - 60)
        windowHandoffTimer.restart()
    }

    property Timer windowHandoffTimer: Timer {
        interval: 240
        repeat: false
        onTriggered: icon._reloadIconRenderer()
    }

    // KWin's private KOS Effect consumes compositor-global icon rectangles.
    // The target uses the stable slot centre rather than the renderer's hover
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
            : iconRenderer.mapToItem(null, 0, 0)
        const bottomRight = slotParent
            ? slotParent.mapToItem(null, centerX + icon.iconSize / 2,
                                   centerY + icon.iconSize / 2)
            : iconRenderer.mapToItem(null, iconRenderer.width, iconRenderer.height)
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
        // Bundled icons are inline data URIs. KWin reads that field as a file
        // path, so send nothing (the effect falls back to EffectWindow::icon())
        // rather than pushing kilobytes of base64 through the payload that is
        // republished four times a second.
        if (animationIconSource.startsWith("data:"))
            animationIconSource = ""
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
    // Distance-based magnification. The Item's width/height remain the fixed
    // layout slot; only its visual transform changes.
    readonly property bool _distanceMagnificationEnabled:
        AppearanceTokens.dock.magnificationEnabled
        && magnificationRoot !== null
        && magnificationPointer.x > -9999
        && magnificationPointer.y > -9999
    // Stable slot centre in the magnification root's coordinates, mapped from
    // the layout parent and never from the icon, so nothing derived from it can
    // read the hover transform it drives. Mapping the icon itself would fold in
    // its own lift/scale. On today's Dock the two happen to agree on the
    // influence axis -- a side Dock rotates its row, so the local lift lands on
    // the axis the influence ignores -- so this is not a behaviour change; it
    // makes the independence explicit rather than accidental, and lets the
    // hover test below share one definition of "the slot".
    function _slotCentreInRoot() {
        const slotParent = icon.parent
        const cx = icon.x + icon.width / 2
        const cy = icon.y + icon.height / 2
        return slotParent
            ? slotParent.mapToItem(magnificationRoot, cx, cy)
            : icon.mapToItem(magnificationRoot, cx, cy)
    }
    readonly property real _magnificationInfluence: {
        if (!_distanceMagnificationEnabled || !visible)
            return 0.0
        const center = icon._slotCentreInRoot()
        const iconAxis = vertical ? center.y : center.x
        const pointerAxis = vertical ? magnificationPointer.y
                                     : magnificationPointer.x
        const radius = Math.max(icon.iconSize * 2.0,
            AppearanceTokens.dock.magnificationRadius)
        if (!Number.isFinite(iconAxis) || !Number.isFinite(pointerAxis)
                || radius <= 0)
            return 0.0
        const normalized = Math.max(0.0, Math.min(1.0,
            1.0 - Math.abs(iconAxis - pointerAxis) / radius))
        return normalized * normalized * (3.0 - 2.0 * normalized)
    }
    readonly property real _magnificationScale:
        1.0 + _magnificationInfluence
            * (AppearanceTokens.dock.magnificationMaxScale - 1.0)
    // Continuous (sub-pixel) lift: rounding this to whole pixels would quantise
    // the small magnification lift into a couple of visible steps.
    readonly property real _magnificationLift:
        -(icon.iconSize
            * AppearanceTokens.dock.magnificationLiftRatio
            * _magnificationInfluence)
    // The distance curve already includes the hovered icon. Keep the original
    // one-icon fallback for non-macOS shell styles.
    readonly property real _hoverScale:
        !_distanceMagnificationEnabled && _hovering
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
    scale: _hoverScale * _magnificationScale * _attentionScale
    // The icon artwork is cached in `iconRenderer`/`GlassText` below instead of
    // on this whole item: an offscreen texture is sized to the item's bounds
    // and clips overflow, which would hide the running/status indicators
    // that deliberately extend past the icon edge.
    transform: Translate {
        y: icon._hoverLift + icon._magnificationLift + icon._attentionLift
        Behavior on y {
            SpringAnimation {
                spring: DockAnimation.iconSpring
                damping: DockAnimation.iconDamping
                mass: DockAnimation.iconMass
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
    // Hover is resolved against the icon's *static* layout slot rather than the
    // MouseArea's live geometry. `_mouseArea` is anchored to this item, so it
    // moves with the very hover lift/scale it triggers: with the pointer parked
    // on the slot's bottom edge the icon lifts out from under the cursor (the
    // measured band is ~0.75px, one row at 1x), the hover clears, the icon drops
    // back and the cycle repeats — an endless jitter. Testing the untransformed
    // slot against the container pointer makes hover a pure function of the
    // pointer again.
    //
    // The slot is not the zoomed artwork, and that is deliberate: a pointer in
    // the gap between two slots, or in the overhang a magnified neighbour leaves
    // past its slot, is no longer reported as hovering. The old test covered the
    // 1.19x-scaled rect, which grew ~4.5px past the slot and therefore bridged
    // the 4px inter-icon gap.
    //
    // A DockIcon whose container publishes no pointer (magnificationRoot unset,
    // or the pointer outside it) keeps the MouseArea answer. The Dock's own
    // icons, including the pinned launcher and trash, all receive the container
    // root, so they take the pointer path; the fallback is for isolated hosts.
    readonly property bool _hovering: {
        if (!icon.interactive || !icon.visible)
            return false
        if (magnificationRoot === null || magnificationPointer.x < -9999
                || magnificationPointer.y < -9999)
            // No container pointer to test against. This path does read the
            // item's own transform, which is acceptable here because a host that
            // publishes no pointer is not running the hover magnification.
            return _mouseArea.containsMouse
        const centre = icon._slotCentreInRoot()
        return Math.abs(centre.x - magnificationPointer.x) <= icon.width / 2
            && Math.abs(centre.y - magnificationPointer.y) <= icon.height / 2
    }
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

    Behavior on scale {
        SpringAnimation {
            spring: DockAnimation.iconSpring
            damping: DockAnimation.iconDamping
            mass: DockAnimation.iconMass
        }
    }

    // Lazily instantiated popups. Creating a PopupWindow allocates a real
    // QWindow (and its scene-graph resources) even when never shown, so the
    // context menu and window preview only exist after the first request.
    property var _contextMenuInstance: null
    property var _previewInstance: null
    property Component _contextMenuComponent: Component {
        ContextMenu {
            property bool hasBeenVisible: false
            anchorItem: icon
            position: ConfigService.position
            baseColor: ThemeService.backgroundColor
            foregroundColor: ThemeService.foregroundColor
            onAboutToShow: hasBeenVisible = true
            onAboutToHide: {
                if (hasBeenVisible) {
                    hasBeenVisible = false
                    if (DockModelService.activeContextMenu === this)
                        DockModelService.activeContextMenu = null
                    DockModelService.releaseDockPopup(this)
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
    }
    property Component _previewComponent: Component {
        DockWindowPreview {
            id: preview
            anchorItem: icon
            onPointerInsideChanged: {
                // Re-entering the preview while it is closing must cancel the
                // close and hand off, not restart the glass from zero.
                if (pointerInside) {
                    previewCloseDelay.stop()
                    preview.cancelClosing()
                } else if (!icon._hovering) {
                    previewCloseDelay.restart()
                }
            }
            onActivateRequested: {
                DockModelService.activateWindow(windowId)
                DockModelService.setDockPopupVisible(this, false)
            }
            onVisibleChanged: {
                if (!visible)
                    DockModelService.releaseDockPopup(this)
            }
        }
    }
    function ensureContextMenuLoaded() {
        if (!_contextMenuInstance)
            _contextMenuInstance = _contextMenuComponent.createObject(icon)
        return _contextMenuInstance
    }
    function ensurePreviewLoaded() {
        if (!_previewInstance)
            _previewInstance = _previewComponent.createObject(icon)
        return _previewInstance
    }
    readonly property var contextMenu: _contextMenuInstance
    readonly property var preview: _previewInstance

    Timer {
        id: previewDelay
        // Short, deliberate dwell so a real hover feels immediate without
        // opening previews during a quick pointer pass.
        interval: DockAnimation.windowPreviewDelay
        repeat: false
        onTriggered: {
            if (icon._hovering && icon._hasWindows && !icon.editMode
                    && !DockModelService.activeContextMenu) {
                const p = ensurePreviewLoaded()
                console.log("[DockIcon] preview request app=" + icon.appId
                    + " windowCount=" + icon._appWindows.length);
                p.appId = icon.appId
                p.windowId = icon._previewWindowId
                // The strip is labelled with the application; each card labels
                // its own window (see DockWindowPreview's per-card title).
                p.appName = icon.displayName
                p.windows = icon._appWindows
                DockModelService.openDockPopup(p)
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
        interval: DockAnimation.windowPreviewCloseDelay
        repeat: false
        onTriggered: {
            if (!icon._hovering && !(icon.preview && icon.preview.pointerInside))
                DockModelService.setDockPopupVisible(icon.preview, false)
        }
    }

    // A pinned app with no live window has no thumbnail to show. Use a small
    // edge-aware label instead of opening an empty preview surface.
    PopupWindow {
        id: appNameTooltip
        readonly property bool shouldShow:
            icon._hovering
            && !icon._hasWindows
            && !icon.isRunning
            && icon.displayName.trim().length > 0
            && !icon.editMode
            && !DockModelService.activeContextMenu

        visible: shouldShow
        implicitWidth: appNameText.implicitWidth + 16
        implicitHeight: appNameText.implicitHeight + 10
        color: "transparent"

        anchor {
            item: icon
            edges: icon.dockEdge === "bottom" ? Edges.Top
                : icon.dockEdge === "left" ? Edges.Right : Edges.Left
            gravity: icon.dockEdge === "bottom" ? Edges.Top
                : icon.dockEdge === "left" ? Edges.Right : Edges.Left
            margins.top: icon.dockEdge === "bottom" ? -6 : 0
            margins.left: icon.dockEdge === "right" ? -6 : 0
            margins.right: icon.dockEdge === "left" ? -6 : 0
        }

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: ThemeService.tooltipBackground
            border.width: 1
            border.color: ThemeService.borderColor

            Text {
                id: appNameText
                anchors.centerIn: parent
                text: icon.displayName
                color: ThemeService.foregroundColor
                font {
                    family: "Noto Sans CJK SC, sans-serif"
                    pixelSize: 11
                    weight: Font.DemiBold
                }
            }
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

    Loader {
        id: iconRenderer
        width: icon.iconSize
        height: icon.iconSize
        anchors.centerIn: parent
        active: icon._iconRendererActive
        sourceComponent: Component {
            AppIcon {
                width: icon.iconSize
                height: icon.iconSize
                source: icon.iconSource || ""
                // A newly opened window has no previous Dock texture to retain.
                asynchronous: false
                rotation: icon.vertical ? -90 : 0
                transformOrigin: Item.Center
                layer.enabled: true
                layer.smooth: true
                opacityMultiplier: IconAppearanceService.mode === "color"
                    ? 1.0 : IconAppearanceService.opacity
                saturation: IconAppearanceService.saturation
                tintEnabled: IconAppearanceService.tintEnabled
                tintColor: IconAppearanceService.tintColor
            }
        }
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

    Rectangle {
        id: attentionBadge
        readonly property bool hasCount: icon.notificationCount > 0
        readonly property real badgeHeight: hasCount
            ? Math.max(16, Math.round(icon.iconSize * 0.36))
            : Math.max(8, Math.round(icon.iconSize * 0.2))
        width: hasCount
            ? Math.max(badgeHeight,
                badgeText.implicitWidth + Math.round(badgeHeight * 0.55))
            : badgeHeight
        height: badgeHeight
        radius: badgeHeight / 2
        anchors { right: iconRenderer.right; top: iconRenderer.top }
        anchors.rightMargin: hasCount ? -Math.round(icon.iconSize * 0.06) : 0
        anchors.topMargin: hasCount ? -Math.round(icon.iconSize * 0.06) : 0
        rotation: icon.vertical ? -90 : 0
        transformOrigin: Item.Center
        color: "#ff3b30"
        border.width: 0
        opacity: (hasCount || icon.isUrgent) && !icon.editMode ? 1 : 0
        scale: opacity > 0 ? 1 : 0
        visible: opacity > 0.01
        z: 3
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutBack }
        }

        Text {
            id: badgeText
            anchors.centerIn: parent
            visible: attentionBadge.hasCount
            text: icon.notificationCount > 99
                ? "99+" : String(icon.notificationCount)
            color: "white"
            renderType: Text.NativeRendering
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font {
                family: AppearanceTokens.typography.displayFamily
                pixelSize: Math.max(8,
                    Math.round(attentionBadge.badgeHeight * 0.52))
                weight: Font.Bold
            }
        }
    }

    // Keep the dots inside the existing indicator slot. In particular, the
    // side Dock rotates this item with the row, so an unbounded window-count
    // strip would protrude past the icon edge.
    Item {
        id: runningIndicator
        readonly property int dotCount: Math.min(3,
            Math.max(1, icon.windowCount))
        readonly property real dotSize: dotCount >= 3 ? 4 : 5
        readonly property real dotSpacing: 2
        width: icon.dotIndicator
            ? dotCount * dotSize + (dotCount - 1) * dotSpacing
            : icon.runningIndicatorWidth
        height: icon.runningIndicatorHeight
        opacity: icon.isRunning ? 1 : 0
        visible: opacity > 0.01
        z: 2
        anchors.horizontalCenter: iconRenderer.horizontalCenter
        anchors.top: icon.vertical && icon.dockEdge === "right"
            ? undefined : iconRenderer.bottom
        anchors.bottom: icon.vertical && icon.dockEdge === "right"
            ? iconRenderer.top : undefined
        anchors.topMargin: icon.runningIndicatorGap
        anchors.bottomMargin: icon.runningIndicatorGap

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        Row {
            anchors.centerIn: parent
            spacing: runningIndicator.dotSpacing
            visible: icon.dotIndicator
            Repeater {
                model: runningIndicator.dotCount
                delegate: Rectangle {
                    required property int index
                    width: runningIndicator.dotSize
                    height: width
                    radius: width / 2
                    color: Qt.rgba(ThemeService.foregroundColor.r,
                        ThemeService.foregroundColor.g,
                        ThemeService.foregroundColor.b, 0.95)
                    Behavior on color {
                        enabled: runningIndicator.opacity > 0.01
                        ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: !icon.dotIndicator
            radius: width / 2
            color: ThemeService.accentColor
            Behavior on color {
                enabled: visible
                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
        }
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
                const menu = ensureContextMenuLoaded()
                if (DockModelService.activeContextMenu
                        && DockModelService.activeContextMenu !== menu) {
                    if (DockModelService.activeContextMenu.visible)
                        DockModelService.dismissDockPopupImmediately(
                            DockModelService.activeContextMenu)
                    else
                        DockModelService.activeContextMenu = null
                }
                // Rebuild items from the icon's current state (window task vs
                // pinned launcher, persisted pin state), then open.
                const pinned = icon.isPinnedItem || DockModelService.isAppPinned(icon.appId)
                menu.clear()
                if (icon.isWindowItem) {
                    menu.addItem("window-restore", "激活窗口", "activate")
                    menu.addItem("window-minimize", "最小化", "minimize")
                    menu.addItem("window-close", "关闭窗口", "close")
                    menu.addItem("window-new", "新建窗口", "new_window")
                    menu.addItem(pinned ? "unpin" : "pin",
                        pinned ? "取消固定" : "固定此应用", pinned ? "unpin" : "pin")
                } else {
                    menu.addItem("folder-open", "打开", "open")
                    menu.addItem("window-new", "新建窗口", "new_window")
                    if (icon.isRunning)
                        menu.addItem("window-close", "关闭所有窗口", "close_all")
                    menu.addItem(pinned ? "unpin" : "pin",
                        pinned ? "取消固定" : "固定此应用", pinned ? "unpin" : "pin")
                }
                DockModelService.activeContextMenu = menu
                DockModelService.openDockPopup(menu)
            } else if (!icon._heldForEdit) {
                icon.activate()
            }
        }
        onEntered: {
            if (icon._previewWindowId && !icon.editMode
                    && !DockModelService.activeContextMenu)
                previewDelay.restart()
        }
        onExited: {
            previewDelay.stop()
            previewCloseDelay.restart()
        }
    }

}
