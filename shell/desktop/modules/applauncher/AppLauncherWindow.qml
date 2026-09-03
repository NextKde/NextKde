import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "../../../shared/qml/controls" as LiquidControls

// Output-bound application-launcher surface. The panel itself spans the
// output only to make centering reliable. The visible glass card follows Dock
// once it is large enough, but keeps a usable minimum at initial/small sizes.
PanelWindow {
    id: root

    // Distinguish this surface from other quickshell panels so the glass
    // plugin can give it its own highlight direction.
    WlrLayershell.namespace: "quickshell-applauncher"
    // The Dock and Bar are Top-layer surfaces. In card presentations the
    // launcher rides Overlay so it sits above the Dock rather than compete
    // with its icon hit region. The fullscreen presentation covers the whole
    // output, and the user wants the Bar and Dock visible above it there —
    // so fullscreen demotes this surface to Top while Dock/Bar promote
    // themselves to Overlay in lockstep (all three rebind live; layer-shell
    // supports runtime layer changes).
    WlrLayershell.layer: isFullscreenMode ? WlrLayer.Top : WlrLayer.Overlay

    // The module root passes this state explicitly (as QuickSearch does) so
    // every output-bound variant shares one reliable visibility binding.
    property bool open: false
    // Opening animates the foreground only (fade + slight scale + slide up);
    // closing is atomic because the compositor backdrop blur cannot fade in
    // lockstep with a QML layer. The blur region stays fixed at full card size
    // throughout.
    //
    // Driven imperatively: onOpenChanged snaps to 0 and starts a NumberAnimation
    // to 1.0 so the transition reliably plays every time the window shows.
    property real contentRevealProgress: 0.0
    property bool gridEntranceActive: false
    readonly property bool panelVisible: open && (AppLauncherService.dockWidth > 0 || isFullscreenMode || isCenterMode)

    readonly property string displayMode: AppLauncherConfigService.displayMode
    readonly property var layoutProfile: AppLauncherConfigService.profileForMode(displayMode)
    readonly property real configIconSize: AppLauncherConfigService.iconPixelSize(displayMode)
    readonly property real configFontSize: AppLauncherConfigService.fontPixelSize(displayMode)
    readonly property real gridGap: AppLauncherConfigService.gridGap(displayMode)
    readonly property int resolvedFontWeight: {
        const w = layoutProfile.fontWeight
        if (w === "bold") return Font.Bold
        if (w === "medium") return Font.Medium
        return Font.Normal
    }

    readonly property bool isFullscreenMode: displayMode === "fullscreen"
    readonly property bool isCenterMode: displayMode === "center"
    readonly property bool isBottomMode: displayMode === "bottom"
    // Fullscreen is a separate Launchpad presentation, not a stretched bottom
    // sheet. Keep its pages independent from the persisted application order.
    property int fullscreenPage: 0
    readonly property int fullscreenPageSize: Math.max(1,
        appGrid ? appGrid.fullscreenPageSize : 1)
    readonly property int fullscreenPageCount: Math.max(1,
        Math.ceil(filteredApplications.length / fullscreenPageSize))
    readonly property int fullscreenPageOffset: isFullscreenMode
        ? fullscreenPage * fullscreenPageSize : 0
    readonly property real gridIconSize: configIconSize
    readonly property color launcherForegroundColor: isFullscreenMode
        ? Qt.rgba(1, 1, 1, 0.94) : AppLauncherService.dockForegroundColor
    // KWin sees the exact live backdrop; QML cannot. The wallpaper palette is
    // nevertheless a useful stable cue for the Launchpad's large scrim. Keep
    // ordinary imagery translucent, and only protect against the low-contrast
    // ends of the range (near white or black).
    readonly property real wallpaperLuminance: WallpaperPaletteService.primary.r * 0.2126
        + WallpaperPaletteService.primary.g * 0.7152
        + WallpaperPaletteService.primary.b * 0.0722
    readonly property real launcherBackdropDistance: Math.min(
        wallpaperLuminance, 1.0 - wallpaperLuminance)
    // 1 at the two extremes, easing down to 0 for normal mid-tone imagery.
    readonly property real launcherBackdropProtection: {
        const t = Math.min(1.0, Math.max(0.0,
            (launcherBackdropDistance - 0.08) / 0.30))
        return 1.0 - t * t * (3.0 - 2.0 * t)
    }
    readonly property color launcherScrimColor: {
        const lightMix = Math.min(1.0, Math.max(0.0,
            (wallpaperLuminance - 0.30) / 0.40))
        // A Launchpad is a large dark material in every environment. Bright
        // backgrounds need more of this tint, but dark backgrounds must never
        // flip to a white veil: that reads as grey plastic rather than glass.
        const baseAlpha = 0.13 + 0.08 * lightMix
        const extremeAlpha = (0.09 + 0.12 * lightMix)
            * launcherBackdropProtection
        const modeScale = isFullscreenMode ? 1.0 : 0.72
        return Qt.rgba(0.018, 0.028, 0.052,
            (baseAlpha + extremeAlpha) * modeScale)
    }
    onFilteredApplicationsChanged: {
        root.cancelFullscreenPageTransition();
        _clampFullscreenPage();
    }
    // Synchronous page moves (keyboard paging, search reset, clamping) go
    // through a full pager resync; animated transitions rotate slots inside
    // commitFullscreenPageTransition while the state guard keeps this off.
    onFullscreenPageChanged: {
        if (fullscreenSwipeState === 0)
            syncPagerSlots();
    }

    // Automatically determine whether dark or light mode is active based on foreground color
    readonly property bool isDark: {
        const c = AppLauncherService.dockForegroundColor
        return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.5
    }

    // The card follows the Dock edge: bottom dock floats centered above the
    // dock, side docks float vertically centered beside it.
    readonly property bool dockAtBottom: AppLauncherService.dockPosition !== "left"
        && AppLauncherService.dockPosition !== "right"
    readonly property bool dockAtLeft: AppLauncherService.dockPosition === "left"
    readonly property bool dockAtRight: AppLauncherService.dockPosition === "right"

    Component.onCompleted: console.log("[AppLauncherWindow] created")
    onOpenChanged: {
        console.log("[AppLauncherWindow] received open=" + open);
        if (open) {
            root.cancelFullscreenPageTransition();
            root.syncPagerSlots();
            contentRevealProgress = 0.0;
            openForeground.restart();
        } else {
            contentRevealProgress = 0.0;
        }
    }

    NumberAnimation {
        id: openForeground
        target: root
        property: "contentRevealProgress"
        from: 0.0
        to: 1.0
        duration: 150
        easing.type: Easing.OutCubic
    }
    onScreenChanged: console.log("[AppLauncherWindow] screen changed=" + !!screen)
    readonly property real minimumLauncherWidth: screen ? Math.round(screen.width * 0.50) : 600
    readonly property real minimumLauncherHeight: 500
    readonly property bool usesMinimumSize: AppLauncherService.dockWidth < minimumLauncherWidth
    // Sizing depends on display mode: fullscreen fills screen, center floats
    // with comfortable dialogue dimensions, bottom follows the Dock.
    readonly property real launcherWidth: isFullscreenMode
        ? (screen ? screen.width : 1920)
        : (isCenterMode
            ? (screen ? Math.min(Math.max(680, Math.round(screen.width * 0.65)), 1040) : 760)
            : (usesMinimumSize ? minimumLauncherWidth : AppLauncherService.dockWidth))

    readonly property real launcherHeight: isFullscreenMode
        ? (screen ? screen.height : 1080)
        : (isCenterMode
            ? (screen ? Math.min(Math.max(520, Math.round(screen.height * 0.68)), 760) : 560)
            : (!dockAtBottom
                ? Math.min(Math.max(minimumLauncherHeight, AppLauncherService.dockWidth),
                    Math.round(screen.height * 0.85))
                : (usesMinimumSize ? minimumLauncherHeight
                    : Math.round(screen.height * 0.50))))
    readonly property var applications: {
        // This window stays instantiated while hidden. Do not enumerate every
        // desktop entry or resolve its icon until the launcher is actually
        // opened; otherwise application updates rebuild the hidden grid and
        // stall the whole shell.
        if (!root.open)
            return [];
        AppPresentationService.catalogRevision;
        AppPresentationService.revision;
        const catalogue = AppPresentationService.catalog();
        const apps = [];
        for (let i = 0; i < catalogue.length; i++) {
            const presentation = catalogue[i];
            const appId = presentation.rawAppId;
            if (!appId || AppLauncherConfigService.hiddenAppIds.indexOf(appId) >= 0)
                continue;
            apps.push({
                id: appId,
                name: presentation.displayName,
                icon: presentation.iconSource,
                defaultName: presentation.defaultName,
                defaultIcon: presentation.defaultIcon,
                entry: presentation.entry
            });
        }
        return apps;
    }
    property string query: ""
    property int selectedIndex: 0
    // Selection is shown only when it has keyboard/search intent. Leaving a
    // permanent highlight on the first icon makes the resting grid look like
    // it already has focus, especially on a translucent background.
    property bool keyboardSelectionActive: false
    // Long press enters an iPadOS-like editing state. This is launcher-local:
    // it never changes the Dock's separate pinned-app edit mode.
    property bool editMode: false
    readonly property var orderedApplications: AppLauncherConfigService.orderedApplications(applications)
    readonly property var rootGridItems: AppLauncherConfigService.rootGridItems(applications)
    property var openFolder: null
    // Keep a stable snapshot during the close animation. `openFolder` remains
    // the live persistence target; `displayedFolder` is only presentation.
    property var displayedFolder: null
    property bool folderDialogOpen: false
    property bool folderRenameActive: false
    property string folderRenameText: ""
    property var editingApplication: null
    property string editorName: ""
    property string editorIcon: ""
    property string editorIconStatus: ""
    // Native file choosers are ordinary toplevel dialogs. Temporarily lower
    // this layer-shell surface and release its keyboard focus so the chooser
    // can sit above it and receive input on Hyprland.
    property bool externalDialogOpen: false
    // Folder editing is intentionally independent from root edit mode: the
    // root grid must not start wiggling behind an open folder dialog.
    property bool folderEditMode: false
    // Reordering updates the GridView model asynchronously. Preserve its
    // viewport across that update so a drag release never looks like the
    // launcher panel itself has jumped vertically.
    property real pendingGridContentY: -1
    // Root-grid drag preview is presentation-only. The persisted model changes
    // once on release; these indices make neighboring tiles smoothly reserve
    // the prospective slot while the pointer is moving.
    property int rootDragSourceIndex: -1
    property int rootDragTargetIndex: -1
    // Folder contents use an independent preview state. The root grid stays
    // frozen behind the modal, so sharing indices would make the two GridViews
    // calculate offsets against incompatible cell geometry.
    property int folderPreviewSourceIndex: -1
    property int folderPreviewTargetIndex: -1
    // Folder creation is intentionally a slower gesture than sorting. A tile
    // only becomes a merge target after the dragged app rests on it briefly.
    property string folderMergeTargetKey: ""
    property bool folderMergeArmed: false
    // This is visual-only feedback for the same 650ms dwell used by
    // `folderMergeTimer`. It makes the distinction between "reorder" and
    // "create/add to folder" explicit without adding a second gesture rule.
    property real folderMergeProgress: 0
    Behavior on folderMergeProgress {
        NumberAnimation {
            duration: 650
            easing.type: Easing.Linear
        }
    }
    // A short press acknowledgement belongs to the launcher presentation,
    // not the app-launch operation. The app starts immediately; this keeps
    // the UI responsive while still letting the user see what was activated.
    property var launchFeedbackItem: null

    // ===== Fullscreen Launchpad drag paging =====
    // Pages slide 1:1 with the pointer like the macOS Launchpad: the live
    // grid moves together with a real neighbor-page copy, and release snaps
    // by travel distance plus release velocity. 0 = idle, 1 = finger is
    // dragging, 2 = settling toward fullscreenSettleTarget.
    property int fullscreenSwipeState: 0
    property real fullscreenPageDragOffset: 0
    property int fullscreenSettleTarget: 0
    property real fullscreenSwipeVelocity: 0
    // A drag past the system threshold must never also register as a click
    // on a tile or the dismiss catcher. Cleared one loop turn after release.
    property bool fullscreenSwipeSuppressClick: false
    readonly property real fullscreenPageSlideWidth: Math.max(1, launcherContentArea.width)
    readonly property real fullscreenPageTrackOffset: isFullscreenMode
        ? fullscreenPageDragOffset : 0
    // Float page position drives the page dots so they interpolate while a
    // drag or settle animation is in flight instead of snapping on commit.
    readonly property real fullscreenPageProgress: isFullscreenMode
        ? fullscreenPage - fullscreenPageDragOffset / fullscreenPageSlideWidth
        : fullscreenPage
    // +1 = travelling toward the next page, -1 = previous, 0 = resting.
    readonly property int fullscreenSwipeDirection: {
        if (fullscreenSwipeState === 1) {
            if (fullscreenPageDragOffset < -1)
                return 1;
            if (fullscreenPageDragOffset > 1)
                return -1;
        } else if (fullscreenSwipeState === 2) {
            if (fullscreenSettleTarget > fullscreenPage)
                return 1;
            if (fullscreenSettleTarget < fullscreenPage)
                return -1;
        }
        return 0;
    }
    NumberAnimation {
        id: fullscreenSettleAnimation
        target: root
        property: "fullscreenPageDragOffset"
        easing.type: Easing.OutCubic
        onFinished: root.commitFullscreenPageTransition()
    }
    Timer {
        id: fullscreenSwipeClickReset
        interval: 1
        repeat: false
        onTriggered: root.fullscreenSwipeSuppressClick = false
    }

    function searchScore(app, needle) {
        const name = String(app.name || "").toLowerCase();
        const appId = String(app.id || "").toLowerCase();
        if (name === needle)
            return 0;
        if (name.startsWith(needle))
            return 1;
        // Treat spaces and common desktop-entry separators as word breaks.
        // This lets e.g. "code" find "Visual Studio Code" before a loose
        // substring while still behaving sensibly for non-Latin app names.
        const words = name.split(/[\\s._-]+/);
        for (let i = 0; i < words.length; i++) {
            if (words[i].startsWith(needle))
                return 2;
        }
        if (appId.startsWith(needle))
            return 3;
        if (name.includes(needle))
            return 4;
        return appId.includes(needle) ? 5 : 6;
    }

    readonly property var filteredApplications: {
        const needle = query.trim().toLowerCase();
        if (!needle)
            return rootGridItems;
        const ranked = [];
        for (let i = 0; i < orderedApplications.length; i++) {
            const app = orderedApplications[i];
            const score = searchScore(app, needle);
            if (score < 6)
                ranked.push({
                    app: app,
                    score: score,
                    originalIndex: i
                });
        }
        // Preserve the user's existing order whenever two results are equally
        // relevant. Search ranking is therefore ephemeral presentation, not a
        // hidden rewrite of the launcher layout.
        ranked.sort(function (left, right) {
            return left.score !== right.score ? left.score - right.score : left.originalIndex - right.originalIndex;
        });
        return ranked.map(function (result) {
            return {
                type: "app",
                app: result.app
            };
        });
    }

    function launchApplication(app, feedbackItem) {
        if (!AppActionService.launch(app))
            return;
        // Launching an app completes this first-stage launcher flow.
        // Future settings can make this behavior configurable.
        if (feedbackItem) {
            launchFeedbackItem = feedbackItem;
            launchFeedbackTimer.restart();
        } else {
            AppLauncherService.hide();
        }
    }

    function showApplicationMenu(app, anchorItem) {
        if (!app)
            return;
        if (appContextMenu.visible && appContextMenu.application
                && appContextMenu.application.id === app.id) {
            dismissApplicationMenu()
            return
        }
        appContextMenu.application = app
        appContextMenu.anchorItem = anchorItem
        appContextMenu.clear()
        appContextMenu.addItem("", "打开应用", "open")
        appContextMenu.addItem("", "编辑应用", "edit")
        appContextMenu.addItem("", "固定到 Dock", "pin")
        appContextMenu.show()
    }

    function dismissApplicationMenu() {
        appContextMenu.hide()
    }

    function showApplicationEditor(app) {
        if (!app)
            return;
        editingApplication = app;
        editorName = app.name;
        // Store the editable source form, not the resolved theme path, so an
        // icon theme change can still resolve a user-entered icon name.
        editorIcon = (AppLauncherConfigService.appOverrides[app.id] || ({})).icon || app.defaultIcon;
        editorIconStatus = "";
        appEditorNameFocusTimer.restart();
    }

    function closeApplicationEditor() {
        editingApplication = null;
        editorName = "";
        editorIcon = "";
        editorIconStatus = "";
    }

    function saveApplicationEditor() {
        if (!editingApplication)
            return;
        console.log("[AppLauncher] save editor app=" + editingApplication.id + " icon=" + editorIcon);
        AppLauncherConfigService.updateAppOverride(editingApplication.id, editorName, editorIcon, editingApplication.defaultName, editingApplication.defaultIcon);
        closeApplicationEditor();
    }

    function hideEditedApplication() {
        if (!editingApplication)
            return;
        AppActionService.hide(editingApplication.id);
        closeApplicationEditor();
    }

    function chooseCustomIcon() {
        if (editingApplication) {
            editorIconStatus = "";
            customIconFileDialog.open();
        }
    }

    function pasteClipboardIcon() {
        if (!editingApplication)
            return;
        editorIconStatus = "正在从剪贴板导入 PNG…";
        AppLauncherConfigService.importClipboardPngIcon(editingApplication.id);
    }

    function showFolder(folder, _originDelegate) {
        displayedFolder = folder;
        openFolder = folder;
        // Opening a folder from root edit mode continues the same editing
        // session, so its children are immediately sortable/removable.
        folderEditMode = editMode;
        folderRenameActive = false;
        folderRenameText = folder.name;
        // Construct at the collapsed state first, then drive the open
        // transition next frame so the fade+scale Behavior catches it.
        folderDialogOpen = false;
        folderOpenTimer.restart();
    }

    function closeFolder() {
        if (!displayedFolder)
            return;
        folderEditMode = false;
        folderRenameActive = false;
        // The dialog fades+scales out via its Behaviors; the close timer
        // outlasts that so the page only tears down once it has visually
        // collapsed.
        folderDialogOpen = false;
        folderCloseTimer.restart();
    }

    function beginFolderRename() {
        if (!openFolder)
            return;
        folderRenameText = openFolder.name;
        folderRenameActive = true;
        folderRenameFocusTimer.restart();
    }

    function commitFolderRename() {
        if (!openFolder)
            return;
        const name = folderRenameText.trim() || "文件夹";
        AppLauncherConfigService.renameFolder(openFolder.id, name);
        const refreshed = rootGridItems.find(function (item) {
            return item.type === "folder" && item.id === root.openFolder.id;
        });
        if (refreshed) {
            openFolder = refreshed;
            displayedFolder = refreshed;
            folderRenameText = refreshed.name;
        }
        folderRenameActive = false;
    }

    function moveSelection(delta) {
        root.cancelFullscreenPageTransition();
        const count = filteredApplications.length;
        if (count === 0)
            return;
        keyboardSelectionActive = true;
        // Grid navigation should stop at its edges. Wrapping from the first
        // result to the final row is fast but surprising in an app launcher.
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta));
        if (isFullscreenMode) {
            // onFullscreenPageChanged resyncs the pager slots.
            fullscreenPage = Math.floor(selectedIndex / fullscreenPageSize)
        } else {
            appGrid.positionViewAtIndex(selectedIndex, GridView.Contain);
        }
    }

    function clearSearch() {
        root.cancelFullscreenPageTransition();
        if (!query.length)
            return false;
        searchBar.text = "";
        query = "";
        selectedIndex = 0;
        fullscreenPage = 0;
        keyboardSelectionActive = false;
        return true;
    }

    function fullscreenPageSlice(page) {
        const start = Math.max(0, page) * fullscreenPageSize
        return filteredApplications.slice(start, start + fullscreenPageSize)
    }

    function stepFullscreenPage(delta) {
        return gotoFullscreenPage(fullscreenPage + delta)
    }

    // Animated page switch shared by the wheel, the dots and drag release.
    // Returns false when the pager is busy or the target equals the current
    // page, so callers can decide whether to swallow the input.
    function gotoFullscreenPage(page) {
        if (!isFullscreenMode || fullscreenSwipeState !== 0)
            return false
        const target = Math.max(0, Math.min(fullscreenPageCount - 1,
            Math.round(page)))
        if (target === fullscreenPage)
            return false
        if (Math.abs(target - fullscreenPage) > 1) {
            // Multi-slot dot jumps have no rendered neighbor to slide in;
            // fall back to the synchronous path. The pager resyncs through
            // onFullscreenPageChanged.
            fullscreenPage = target
            selectedIndex = target * fullscreenPageSize
            keyboardSelectionActive = false
            return true
        }
        startFullscreenPageTransition(target)
        return true
    }

    function updateFullscreenSwipeTranslation(dx) {
        let offset = dx
        // Edge pages resist with rubber-band friction instead of exposing
        // an empty neighbor slot.
        if (offset > 0 && fullscreenPage <= 0)
            offset *= 0.35
        else if (offset < 0 && fullscreenPage >= fullscreenPageCount - 1)
            offset *= 0.35
        fullscreenPageDragOffset = offset
    }

    function settleFullscreenSwipe() {
        const dx = fullscreenPageDragOffset
        const v = fullscreenSwipeVelocity
        let target = fullscreenPage
        if (dx < -fullscreenPageSlideWidth * 0.32 || v < -700)
            target = fullscreenPage + 1
        else if (dx > fullscreenPageSlideWidth * 0.32 || v > 700)
            target = fullscreenPage - 1
        startFullscreenPageTransition(target)
    }

    function startFullscreenPageTransition(target) {
        const clamped = Math.max(0, Math.min(fullscreenPageCount - 1,
            Math.round(target)))
        const w = fullscreenPageSlideWidth
        const to = clamped > fullscreenPage ? -w : (clamped < fullscreenPage ? w : 0)
        if (clamped === fullscreenPage && Math.abs(to - fullscreenPageDragOffset) < 1) {
            fullscreenPageDragOffset = 0
            return
        }
        fullscreenSettleTarget = clamped
        fullscreenSwipeState = 2
        // Duration scales with the remaining travel so a late flick settles
        // quickly while a full page turn keeps the Launchpad's unhurried glide.
        const dist = Math.abs(to - fullscreenPageDragOffset)
        fullscreenSettleAnimation.duration = Math.max(180,
            Math.min(420, Math.round(dist / w * 480)))
        fullscreenSettleAnimation.to = to
        fullscreenSettleAnimation.restart()
    }

    function commitFullscreenPageTransition() {
        const dir = fullscreenSettleTarget > fullscreenPage ? 1
            : (fullscreenSettleTarget < fullscreenPage ? -1 : 0)
        // Slot rotation happens while the state is still "settling" so the
        // fullscreenPage assignment below cannot trigger a pager resync.
        if (dir !== 0)
            rotatePagerSlots(dir);
        fullscreenPage = fullscreenSettleTarget;
        if (dir !== 0) {
            selectedIndex = fullscreenSettleTarget * fullscreenPageSize;
            keyboardSelectionActive = false;
        }
        fullscreenSwipeState = 0;
        fullscreenPageDragOffset = 0;
    }

    // The fullscreen pager keeps three persistent page grids (previous,
    // current, next). Committing a page turn only re-labels which grid owns
    // which slot: the page that just slid into place already rendered for
    // the whole gesture, so its delegates are never recreated and the
    // landing cannot flash. Only the vacated far slot reloads — offscreen
    // and invisible.
    function pagerGridAtSlot(slot) {
        if (pagerA.slot === slot)
            return pagerA;
        if (pagerB.slot === slot)
            return pagerB;
        return pagerC;
    }

    function rotatePagerSlots(dir) {
        const current = pagerGridAtSlot(0);
        const incoming = pagerGridAtSlot(dir);
        const outgoing = pagerGridAtSlot(-dir);
        incoming.slot = 0;
        current.slot = -dir;
        outgoing.slot = dir;
        outgoing.assignedPage = Math.max(0, Math.min(fullscreenPageCount - 1,
            fullscreenPage + 2 * dir));
    }

    // Full resync for paths that move the page synchronously (open, search,
    // keyboard paging): visible recreation is fine there because those
    // transitions are instant today anyway.
    function syncPagerSlots() {
        if (!isFullscreenMode)
            return;
        const count = fullscreenPageCount;
        pagerA.assignedPage = Math.max(0, Math.min(count - 1, fullscreenPage));
        pagerB.assignedPage = Math.max(0, Math.min(count - 1, fullscreenPage + 1));
        pagerC.assignedPage = Math.max(0, Math.min(count - 1, fullscreenPage - 1));
        pagerA.slot = 0;
        pagerB.slot = 1;
        pagerC.slot = -1;
    }

    // Input that reassigns the page synchronously (keyboard paging, search
    // edits, model changes) must tear down any in-flight swipe first, or a
    // stale settle target would yank the page back afterwards.
    function cancelFullscreenPageTransition() {
        fullscreenSettleAnimation.stop()
        fullscreenPageDragOffset = 0
        fullscreenSwipeState = 0
    }

    function _clampFullscreenPage() {
        fullscreenPage = Math.max(0, Math.min(fullscreenPageCount - 1,
            fullscreenPage))
    }

    function activateSelected() {
        const item = filteredApplications[selectedIndex];
        if (!item)
            return;
        if (item.type === "folder")
            showFolder(item, null);
        else
            launchApplication(item.app);
    }

    function dragTargetIndex(delegate) {
        const centerX = delegate.x + delegate.width / 2 + delegate.lastDragX;
        const centerY = delegate.y + delegate.height / 2 + delegate.lastDragY;
        const column = Math.max(0, Math.min(appGrid.columnCount - 1, Math.floor(centerX / appGrid.cellWidth)));
        const row = Math.max(0, Math.floor(centerY / appGrid.cellHeight));
        return Math.max(0, Math.min(filteredApplications.length - 1, row * appGrid.columnCount + column));
    }

    function rootPreviewOffset(index) {
        const source = rootDragSourceIndex;
        const target = rootDragTargetIndex;
        // A possible folder merge holds its target in place. This prevents the
        // reorder preview from moving that target out from under the pointer;
        // ordinary sorting resumes immediately when the pointer leaves it.
        if (folderMergeTargetKey || source < 0 || target < 0 || source === target)
            return {
                x: 0,
                y: 0
            };
        let previewIndex = index;
        if (target > source && index > source && index <= target)
            previewIndex = index - 1;
        else if (target < source && index >= target && index < source)
            previewIndex = index + 1;
        if (previewIndex === index)
            return {
                x: 0,
                y: 0
            };
        const originalX = (index % appGrid.columnCount) * appGrid.cellWidth;
        const originalY = Math.floor(index / appGrid.columnCount) * appGrid.cellHeight;
        const previewX = (previewIndex % appGrid.columnCount) * appGrid.cellWidth;
        const previewY = Math.floor(previewIndex / appGrid.columnCount) * appGrid.cellHeight;
        return {
            x: previewX - originalX,
            y: previewY - originalY
        };
    }

    function folderPreviewOffset(index) {
        const source = folderPreviewSourceIndex;
        const target = folderPreviewTargetIndex;
        if (source < 0 || target < 0 || source === target)
            return {
                x: 0,
                y: 0
            };
        let previewIndex = index;
        if (target > source && index > source && index <= target)
            previewIndex = index - 1;
        else if (target < source && index >= target && index < source)
            previewIndex = index + 1;
        if (previewIndex === index)
            return {
                x: 0,
                y: 0
            };
        const originalX = (index % folderGrid.columnCount) * folderGrid.cellWidth;
        const originalY = Math.floor(index / folderGrid.columnCount) * folderGrid.cellHeight;
        const previewX = (previewIndex % folderGrid.columnCount) * folderGrid.cellWidth;
        const previewY = Math.floor(previewIndex / folderGrid.columnCount) * folderGrid.cellHeight;
        return {
            x: previewX - originalX,
            y: previewY - originalY
        };
    }

    function _itemKey(item) {
        return item && item.type === "folder" ? "folder:" + item.id : (item && item.type === "app" ? "app:" + item.app.id : "");
    }

    function potentialFolderDropTarget(appId, delegate) {
        const target = dragTargetIndex(delegate);
        const candidate = filteredApplications[target];
        if (!candidate || (candidate.type === "app" && candidate.app.id === appId))
            return null;
        const targetColumn = target % appGrid.columnCount;
        const targetRow = Math.floor(target / appGrid.columnCount);
        const targetX = targetColumn * appGrid.cellWidth + appGrid.cellWidth / 2;
        const targetY = targetRow * appGrid.cellHeight + appGrid.cellHeight / 2;
        const dragX = delegate.x + delegate.width / 2 + delegate.lastDragX;
        const dragY = delegate.y + delegate.height / 2 + delegate.lastDragY;
        // Sorting is the default operation. The target remains stationary
        // while this centre zone is held, so a deliberate folder merge stays
        // reachable instead of being moved away by the reorder preview.
        const insideMergeCenter = Math.abs(dragX - targetX) <= Math.min(36, appGrid.cellWidth * 0.36) && Math.abs(dragY - targetY) <= Math.min(42, appGrid.cellHeight * 0.40);
        return insideMergeCenter ? candidate : null;
    }

    function updateFolderMergeCandidate(appId, delegate) {
        const candidate = potentialFolderDropTarget(appId, delegate);
        const key = _itemKey(candidate);
        if (key === folderMergeTargetKey)
            return candidate;
        folderMergeTargetKey = key;
        folderMergeArmed = false;
        folderMergeTimer.stop();
        // Restart the visual dwell together with the logical timer. Keeping
        // this state at the launcher root ensures recycled grid delegates
        // cannot leave a stale progress indicator behind.
        folderMergeProgress = 0;
        if (key) {
            folderMergeProgress = 1;
            folderMergeTimer.restart();
        }
        return candidate;
    }

    function clearFolderMergeCandidate() {
        folderMergeTimer.stop();
        folderMergeTargetKey = "";
        folderMergeArmed = false;
        folderMergeProgress = 0;
    }

    function folderDropTarget(appId, delegate) {
        const candidate = potentialFolderDropTarget(appId, delegate);
        return folderMergeArmed && _itemKey(candidate) === folderMergeTargetKey ? candidate : null;
    }

    function commitApplicationDrag(appId, delegate) {
        // Reordering a filtered search result would make target indices
        // ambiguous in the complete persisted catalog. Exit search first.
        if (query.length > 0)
            return;
        const preservedGridContentY = appGrid.contentY;
        const folderTarget = folderDropTarget(appId, delegate);
        const changed = folderTarget ? (folderTarget.type === "folder" ? AppLauncherConfigService.addApplicationToFolder(appId, folderTarget.id, applications) : AppLauncherConfigService.createFolder(appId, folderTarget.app.id, applications)) : AppLauncherConfigService.moveApplication(appId, dragTargetIndex(delegate), applications);
        if (changed) {
            pendingGridContentY = preservedGridContentY;
            gridScrollRestore.restart();
            console.log(folderTarget ? (folderTarget.type === "folder" ? "[AppLauncher] added app=" + appId + " folder=" + folderTarget.id : "[AppLauncher] created folder source=" + appId + " target=" + folderTarget.app.id) : "[AppLauncher] reordered app=" + appId);
        }
    }

    function commitRootItemDrag(item, delegate) {
        if (item.type === "app") {
            commitApplicationDrag(item.app.id, delegate);
        } else if (!query.length) {
            const preservedGridContentY = appGrid.contentY;
            const changed = AppLauncherConfigService.moveRootItem("folder", item.id, dragTargetIndex(delegate), applications);
            if (changed) {
                pendingGridContentY = preservedGridContentY;
                gridScrollRestore.restart();
                console.log("[AppLauncher] reordered folder=" + item.id);
            }
        }
        rootDragSourceIndex = -1;
        rootDragTargetIndex = -1;
        clearFolderMergeCandidate();
    }

    function folderDragTargetIndex(delegate) {
        const centerX = delegate.x + delegate.width / 2 + delegate.lastDragX;
        const centerY = delegate.y + delegate.height / 2 + delegate.lastDragY;
        const column = Math.max(0, Math.min(folderGrid.columnCount - 1, Math.floor(centerX / folderGrid.cellWidth)));
        const row = Math.max(0, Math.floor(centerY / folderGrid.cellHeight));
        return Math.max(0, Math.min(folderGrid.count - 1, row * folderGrid.columnCount + column));
    }

    function commitFolderApplicationDrag(appId, delegate) {
        if (!openFolder) {
            folderPreviewSourceIndex = -1;
            folderPreviewTargetIndex = -1;
            return;
        }
        const changed = AppLauncherConfigService.moveApplicationWithinFolder(appId, openFolder.id, folderDragTargetIndex(delegate));
        if (!changed) {
            folderPreviewSourceIndex = -1;
            folderPreviewTargetIndex = -1;
            return;
        }
        // The projection is regenerated from persisted data immediately after
        // every mutation; retain the dialog identity by its stable folder id.
        const refreshed = rootGridItems.find(function (item) {
            return item.type === "folder" && item.id === root.openFolder.id;
        });
        openFolder = refreshed || null;
        displayedFolder = refreshed || displayedFolder;
        folderPreviewSourceIndex = -1;
        folderPreviewTargetIndex = -1;
        console.log("[AppLauncher] reordered folder app=" + appId);
    }

    function removeFolderApplication(appId) {
        if (!openFolder)
            return;
        const folderId = openFolder.id;
        if (!AppLauncherConfigService.removeApplicationFromFolder(appId, folderId))
            return;
        const refreshed = rootGridItems.find(function (item) {
            return item.type === "folder" && item.id === folderId;
        });
        openFolder = refreshed || null;
        if (!openFolder) {
            folderEditMode = false;
            closeFolder();
        } else {
            displayedFolder = refreshed;
        }
    }

    visible: root.panelVisible
    onVisibleChanged: {
        console.log("[AppLauncherWindow] visible=" + visible + " card=" + launcherWidth + "x" + launcherHeight);
        if (visible) {
            selectedIndex = 0;
            fullscreenPage = 0;
            keyboardSelectionActive = false;
            searchFocusTimer.restart();
        } else {
            dismissApplicationMenu();
            editMode = false;
            folderEditMode = false;
            openFolder = null;
            displayedFolder = null;
            folderDialogOpen = false;
        }
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // A layer-shell Overlay is above ordinary xdg dialogs. Lower this one
    // only for the native icon chooser, then restore the launcher overlay.
    aboveWindows: !externalDialogOpen
    // The closing card remains visible only as an animation; it must not
    // continue to capture keyboard input after Escape or a click on Dock.
    focusable: root.open && !externalDialogOpen
    Timer {
        id: searchFocusTimer
        interval: 1
        repeat: false
        onTriggered: searchBar.forceActiveFocus()
    }

    Timer {
        id: gridScrollRestore
        interval: 1
        repeat: false
        onTriggered: {
            if (root.pendingGridContentY < 0)
                return;
            const maxContentY = Math.max(0, appGrid.contentHeight - appGrid.height);
            appGrid.contentY = Math.max(0, Math.min(maxContentY, root.pendingGridContentY));
            root.pendingGridContentY = -1;
        }
    }

    // A physical wheel emits several events for one gesture. Keep page turns
    // intentional rather than skipping multiple Launchpad pages at once.
    Timer {
        id: fullscreenPageWheelCooldown
        interval: 180
        repeat: false
    }

    Timer {
        id: folderMergeTimer
        // A short dwell makes ordinary cross-grid sorting reliable. Users who
        // actually want a folder still receive a clear blue target cue before
        // releasing, rather than creating folders accidentally in transit.
        interval: 650
        repeat: false
        onTriggered: {
            if (root.folderMergeTargetKey) {
                root.folderMergeArmed = true;
                console.log("[AppLauncher] folder merge armed target=" + root.folderMergeTargetKey);
            }
        }
    }

    Timer {
        id: launchFeedbackTimer
        // Enough to read as a tap response, but below the threshold where the
        // launcher feels slower than directly launching an application.
        interval: 90
        repeat: false
        onTriggered: {
            root.launchFeedbackItem = null;
            AppLauncherService.hide();
        }
    }

    Timer {
        id: folderOpenTimer
        interval: 1
        repeat: false
        onTriggered: root.folderDialogOpen = true
    }

    Timer {
        id: folderRenameFocusTimer
        interval: 1
        repeat: false
        onTriggered: folderNameInput.forceActiveFocus()
    }

    Timer {
        id: appEditorNameFocusTimer
        interval: 1
        repeat: false
        onTriggered: appEditorNameInput.forceActiveFocus()
    }

    Timer {
        id: folderCloseTimer
        // Outlasts the dialog fade+scale-out so the page only tears down once
        // it has visually collapsed.
        interval: 400
        repeat: false
        onTriggered: {
            root.openFolder = null;
            root.displayedFolder = null;
        }
    }

    ContextMenu {
        id: appContextMenu
        property var application: null
        baseColor: ThemeService.backgroundColor
        foregroundColor: ThemeService.foregroundColor
        onAction: function (name) {
            const app = application;
            if (!app)
                return;
            if (name === "open")
                root.launchApplication(app);
            else if (name === "edit")
                AppActionService.edit(app);
            else if (name === "pin")
                AppActionService.pin(app.id);
        }
    }

    // AppActionService carries cross-surface intent; launcher-specific state
    // remains here so the common module never owns launcher persistence/UI.
    Connections {
        target: AppActionService
        function onEditRequested(application) {
            // Edit can originate in QuickSearch. Open this module first so
            // the editor is visible and owns focus rather than editing behind
            // another shell surface.
            AppLauncherService.show();
            root.showApplicationEditor(application);
        }
        function onHideRequested(appId) {
            AppLauncherConfigService.hideApplication(appId);
        }
    }

    Connections {
        target: AppLauncherConfigService
        function onCustomIconImportFinished(appId, path, success) {
            if (!root.editingApplication || root.editingApplication.id !== appId)
                return;
            root.editorIconStatus = success ? "图标已导入，点击保存生效" : "导入失败：请确认已复制 PNG 图片，且安装了 wl-clipboard";
            if (success)
                root.editorIcon = path;
        }
    }

    FileDialog {
        id: customIconFileDialog
        title: "选择应用图标"
        fileMode: FileDialog.OpenFile
        nameFilters: ["图片和 SVG (*.svg *.png *.jpg *.jpeg *.webp)", "所有文件 (*)"]
        // PanelWindow is a Quickshell proxy, not a QWindow. Its private
        // backing window is the QQuickWindow required by Qt Quick Dialogs.
        parentWindow: root._backingWindow
        modality: Qt.ApplicationModal
        onVisibleChanged: {
            root.externalDialogOpen = visible;
            console.log("[AppLauncher] icon file dialog visible=" + visible);
            if (!visible && root.editingApplication)
                appEditorNameFocusTimer.restart();
        }
        onAccepted: {
            if (!root.editingApplication)
                return;
            const importedPath = AppLauncherConfigService.importCustomIcon(root.editingApplication.id, selectedFile);
            if (importedPath)
                root.editorIconStatus = "正在导入图标…";
        }
    }

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }
    // Dock is 5px above the output edge. Leave a 10px gap above its true
    // height without asking this module to reimplement Dock measurements.
    // The same margin is applied at the top to clear the top bar; this also
    // makes the launcher's vertical centre line up with the Dock's centre
    // (the Dock lives in the bar-cleared area).
    margins.top: root.isFullscreenMode ? 0 : AppLauncherService.barHeight
    margins.bottom: root.isFullscreenMode ? 0 : (root.dockAtBottom ? AppLauncherService.dockHeight + 15 : 0)
    margins.left: root.isFullscreenMode ? 0 : (root.dockAtLeft ? AppLauncherService.dockHeight + 15 : 0)
    margins.right: root.isFullscreenMode ? 0 : (root.dockAtRight ? AppLauncherService.dockHeight + 15 : 0)
    implicitHeight: launcherHeight

    // The layer-shell surface spans the output so this catcher can dismiss
    // the launcher from any empty area, while the visible card remains the
    // same Dock-anchored size below. Clicks inside the revealed card are
    // ignored here and continue to its normal controls.
    MouseArea {
        id: outsideDismissArea
        anchors.fill: parent
        z: -1
        enabled: root.open && !root.externalDialogOpen
        acceptedButtons: Qt.LeftButton
        onClicked: function (mouse) {
            if (root.fullscreenSwipeSuppressClick)
                return;
            if (root.isFullscreenMode) {
                AppLauncherService.hide();
                return;
            }
            const insideCard = mouse.x >= launcherRevealClip.x && mouse.x <= launcherRevealClip.x + launcherRevealClip.width && mouse.y >= launcherRevealClip.y && mouse.y <= launcherRevealClip.y + launcherRevealClip.height;
            if (!insideCard)
                AppLauncherService.hide();
        }
    }

    // Keep a fixed card geometry while testing the compositor path: changing
    // this clip every frame is precisely what used to exercise the artefact.
    Item {
        id: launcherRevealClip
        anchors.fill: root.isFullscreenMode ? parent : undefined
        anchors.centerIn: root.isCenterMode ? parent : undefined
        anchors.horizontalCenter: (root.isBottomMode && root.dockAtBottom)
            ? parent.horizontalCenter : undefined
        anchors.bottom: (root.isBottomMode && root.dockAtBottom) ? parent.bottom : undefined
        anchors.verticalCenter: (root.isBottomMode && !root.dockAtBottom)
            ? parent.verticalCenter : undefined
        anchors.left: (root.isBottomMode && root.dockAtLeft) ? parent.left : undefined
        anchors.right: (root.isBottomMode && root.dockAtRight) ? parent.right : undefined
        width: root.isFullscreenMode ? parent.width : root.launcherWidth
        height: root.isFullscreenMode ? parent.height : root.launcherHeight
        clip: true

        // The fullscreen presentation owns the entire output, not merely the
        // centered app grid. Create this wheel receiver only for that mode so
        // edge scrolling flips pages too, while other presentations retain no
        // extra wheel receiver at all.
        Loader {
            active: root.isFullscreenMode
            anchors.fill: parent
            z: 90
            sourceComponent: Component {
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        const delta = wheel.angleDelta.y + wheel.pixelDelta.y
                        if (delta === 0 || fullscreenPageWheelCooldown.running)
                            return
                        if (root.stepFullscreenPage(delta >= 0 ? -1 : 1)) {
                            fullscreenPageWheelCooldown.restart()
                            wheel.accepted = true
                        }
                    }
                }
            }
        }

        Item {
            id: launcherCard
            anchors.fill: parent
            enabled: root.open
            opacity: 1.0

            Item {
                id: background
                anchors.fill: parent
                property real radius: root.isFullscreenMode ? 0 : 28

                // KWin owns the launcher card's actual blur and refraction
                // through BackgroundEffect below. Keeping this client-side
                // layer transparent avoids a duplicate grey QML sheen.
                Rectangle {
                    anchors.fill: parent
                    radius: background.radius
                    // A launcher is a text-dense regular material. The scrim
                    // stays light through ordinary imagery, then gradually
                    // increases only near pure white or black backdrops.
                    color: root.launcherScrimColor
                    Behavior on color {
                        ColorAnimation { duration: 260; easing.type: Easing.InOutCubic }
                    }
                    border.width: root.isFullscreenMode ? 0 : 1
                    border.color: root.isDark
                        ? Qt.rgba(1, 1, 1, 0.16)
                        : Qt.rgba(1, 1, 1, 0.42)
                }

                // This foreground layer deliberately excludes the backdrop
                // material. Its animation cannot change the Wayland blur region.
                Item {
                    id: launcherContent
                    anchors.fill: parent
                    focus: root.open && !root.externalDialogOpen
                    opacity: root.contentRevealProgress
                    // Keys is an Item attachment. Keeping the handler on the
                    // common visual ancestor lets Escape bubble up from the
                    // search, folder and editor controls without attaching it
                    // to the non-Item PanelWindow proxy.
                    Keys.onPressed: function (event) {
                        if (event.key !== Qt.Key_Escape)
                            return;
                        if (root.editingApplication) {
                            root.closeApplicationEditor();
                        } else if (root.openFolder) {
                            if (root.folderRenameActive)
                                root.folderRenameActive = false;
                            else if (root.folderEditMode)
                                root.folderEditMode = false;
                            else
                                root.closeFolder();
                        } else if (root.editMode) {
                            root.editMode = false;
                        } else if (root.clearSearch()) {
                            // Escape first returns to the complete app grid. A
                            // second Escape closes the launcher.
                        } else {
                            AppLauncherService.hide();
                        }
                        event.accepted = true;
                    }
                    // A subtle settle zoom + slide up from the dock direction
                    // as the foreground fades in. Both fold into the same
                    // contentRevealProgress Behavior; the backdrop blur stays
                    // fixed at full card size, so this never fights it.
                    transform: [
                        Scale {
                            origin.x: launcherContent.width / 2
                            origin.y: launcherContent.height / 2
                            xScale: 0.96 + 0.04 * root.contentRevealProgress
                            yScale: 0.96 + 0.04 * root.contentRevealProgress
                        },
                        Translate {
                            y: Math.round((root.isFullscreenMode ? 60 : 200) * (1.0 - root.contentRevealProgress))
                        }
                    ]

                    MouseArea {
                        id: fullscreenBgDismiss
                        anchors.fill: parent
                        z: 0
                        enabled: root.isFullscreenMode && root.open && !root.externalDialogOpen
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            if (root.fullscreenSwipeSuppressClick)
                                return;
                            AppLauncherService.hide()
                        }
                    }

                    // Launchpad-style drag paging. The handler grabs presses
                    // passively, so tile MouseAreas keep their exclusive grab
                    // and ordinary taps still launch; only a horizontal drag
                    // past the system threshold activates paging. While it is
                    // active the release click is suppressed everywhere.
                    DragHandler {
                        id: fullscreenPageDrag
                        enabled: root.isFullscreenMode && root.open && !root.externalDialogOpen
                            && !root.openFolder && root.editingApplication === null
                            && root.fullscreenPageCount > 1
                            && root.fullscreenSwipeState <= 1
                        target: null
                        // Horizontal-only: disabling the y axis keeps vertical
                        // gestures from activating pager translation.
                        yAxis.enabled: false
                        acceptedButtons: Qt.LeftButton
                        onActiveChanged: {
                            if (active) {
                                root.fullscreenSwipeState = 1;
                                root.fullscreenSwipeVelocity = 0;
                                root.fullscreenSwipeSuppressClick = true;
                            } else if (root.fullscreenSwipeState === 1) {
                                root.settleFullscreenSwipe();
                                fullscreenSwipeClickReset.restart();
                            }
                        }
                        onTranslationChanged: {
                            if (!active || root.fullscreenSwipeState !== 1)
                                return;
                            root.fullscreenSwipeVelocity = centroid.velocity.x;
                            root.updateFullscreenSwipeTranslation(translation.x);
                        }
                    }

                    Item {
                        id: launcherContentArea
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        // Fullscreen content follows the output at a fixed
                        // 95% share; the centered/floating presentations keep
                        // the full card width. The inner 96px inset of the old
                        // Math.min(1280, ...) cap silently throttled the grid
                        // no matter what width the grid itself requested.
                        width: root.isFullscreenMode
                            ? Math.round(parent.width * 0.95)
                            : parent.width

                        Item {
                            id: header
                            enabled: root.editingApplication === null
                            z: 1
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                topMargin: root.isFullscreenMode
                                    // Launchpad content should sit near the
                                    // top of the screen rather than start at
                                    // an oversized 13% inset on tall outputs.
                                    ? Math.round(Math.max(48,
                                        Math.min(76, parent.height * 0.07))) : 14
                                leftMargin: 22
                                rightMargin: 22
                            }
                            height: 49

                            LiquidControls.LiquidTextField {
                                id: searchBar
                                anchors {
                                    horizontalCenter: parent.horizontalCenter
                                    verticalCenter: parent.verticalCenter
                                }
                                // The pill stays centered in the header band;
                                // only its width follows the band.
                                width: Math.min(460, Math.max(300, parent.width * 0.46))
                                height: 35

                                placeholderText: "搜索应用"
                                liquidFinish: true
                                liquidStrength: AppearanceConfigService.effectiveLauncherLiquid
                                ambientPrimary: WallpaperPaletteService.primary
                                ambientSecondary: WallpaperPaletteService.secondary
                                ambientStrength: 0.35 * AppearanceTokens.glass.ambientMultiplier
                                textColor: root.launcherForegroundColor
                                mutedTextColor: Qt.rgba(root.launcherForegroundColor.r,
                                    root.launcherForegroundColor.g,
                                    root.launcherForegroundColor.b, 0.45)
                                font.pixelSize: 12
                                leftPadding: 32
                                rightPadding: text.length > 0 ? 32 : 12
                                selectionColor: Qt.rgba(1, 1, 1, 0.30)
                                selectedTextColor: AppLauncherService.dockForegroundColor
                                enabled: !root.editMode && !root.openFolder

                                onTextEdited: {
                                    root.cancelFullscreenPageTransition();
                                    root.query = text;
                                    root.selectedIndex = 0;
                                    root.fullscreenPage = 0;
                                    root.keyboardSelectionActive = text.length > 0;
                                }
                                Keys.onPressed: function (event) {
                                    const columns = appGrid.columnCount;
                                    if (event.key === Qt.Key_Left) {
                                        root.moveSelection(-1);
                                    } else if (event.key === Qt.Key_Right) {
                                        root.moveSelection(1);
                                    } else if (event.key === Qt.Key_Up) {
                                        root.moveSelection(-columns);
                                    } else if (event.key === Qt.Key_Down) {
                                        root.moveSelection(columns);
                                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                        root.activateSelected();
                                    } else if (event.key === Qt.Key_Escape) {
                                        if (!root.clearSearch())
                                            AppLauncherService.hide();
                                    } else {
                                        return;
                                    }
                                    event.accepted = true;
                                }

                                GlassText {
                                    anchors {
                                        left: parent.left
                                        leftMargin: 11
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "⌕"
                                    color: root.launcherForegroundColor
                                    // The icon lights up while the field is
                                    // expanded (focused or holding a query).
                                    opacity: (searchBar.activeFocus || searchBar.text.length > 0) ? 0.95 : 0.65
                                    Behavior on opacity { NumberAnimation { duration: 300 } }
                                    font.pixelSize: 17
                                }

                                GlassText {
                                    anchors {
                                        right: parent.right
                                        rightMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    // Liquid orb pop-in/out, after the reference's
                                    // spring cubic-bezier(0.34, 1.56, 0.64, 1):
                                    // scale 0.5 -> 1 with overshoot, rotate -90 -> 0.
                                    visible: opacity > 0.01
                                    opacity: searchBar.text.length > 0
                                        ? (searchClearMouse.containsMouse ? 0.95 : 0.58) : 0.0
                                    scale: searchBar.text.length > 0 ? 1.0 : 0.5
                                    rotation: searchBar.text.length > 0 ? 0 : -90
                                    Behavior on opacity { NumberAnimation { duration: 180 } }
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 450
                                            easing.type: Easing.Bezier
                                            easing.bezierCurve: [0.34, 1.56, 0.64, 1, 1, 1]
                                        }
                                    }
                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: 450
                                            easing.type: Easing.Bezier
                                            easing.bezierCurve: [0.34, 1.56, 0.64, 1, 1, 1]
                                        }
                                    }
                                    text: "×"
                                    color: root.launcherForegroundColor
                                    font {
                                        pixelSize: 17
                                        weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        id: searchClearMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.clearSearch()
                                    }
                                }
                            }

                            Rectangle {
                                id: rootEditDoneButton
                                width: 48
                                height: 26
                                radius: height / 2
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: opacity > 0.01
                                opacity: root.editMode ? 1.0 : 0.0
                                scale: root.editMode ? 1.0 : 0.82
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 140
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 140
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                color: Qt.rgba(0.027, 0.753, 0.376, 1.0)

                                Text {
                                    anchors.centerIn: parent
                                    text: "完成"
                                    color: "white"
                                    font {
                                        pixelSize: 13
                                        weight: Font.Bold
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: root.editMode
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.editMode = false
                                }
                            }
                        }

                        GridView {
                            id: appGrid
                            enabled: root.editingApplication === null
                            // Never switch between mutually exclusive anchor
                            // sets at runtime. Qt can retain both for one frame
                            // and reports an anchor conflict, leaving the grid's
                            // input region unreliable after returning from
                            // fullscreen. Explicit geometry is stable in every
                            // presentation.
                            // Fullscreen grid width follows the output: a
                            // fixed 95% share keeps side breathing room
                            // proportional across resolutions instead of a
                            // hard 1280px cap that strands huge margins on
                            // wide outputs.
                            width: root.isFullscreenMode
                                ? Math.round(parent.width * 0.95)
                                : parent.width - 36
                            // Fullscreen's search header occupies real space
                            // above the Launchpad grid. Derive rows from the
                            // remaining area instead of forcing four rows into
                            // a short output, which pushed the first row into
                            // the input field at larger icon sizes.
                            readonly property real fullscreenTopClearance:
                                header.y + header.height + 12
                            // The Bar and Dock float above the fullscreen
                            // launcher, so the grid must clear them exactly:
                            // the Bar's reserved height (0 when fused with the
                            // Dock), the Dock's glass height, plus the same
                            // 15px standoff the card presentations use.
                            readonly property real fullscreenBottomClearance:
                                Math.max(Math.round(parent.height * 0.06),
                                    AppLauncherService.barHeight
                                    + (root.dockAtBottom
                                        ? AppLauncherService.dockHeight + 15 : 0))
                            readonly property real fullscreenAvailableHeight:
                                Math.max(0, parent.height - fullscreenTopClearance
                                    - fullscreenBottomClearance)
                            readonly property int fullscreenRowCount: root.isFullscreenMode
                                ? Math.max(1, Math.min(5,
                                    Math.floor(fullscreenAvailableHeight / cellHeight))) : 0
                            height: root.isFullscreenMode
                                ? fullscreenRowCount * cellHeight : parent.height - 32
                            x: Math.round((parent.width - width) / 2)
                            y: root.isFullscreenMode
                                // Keep Launchpad content visually connected to
                                // its search header. A small capped breathing
                                // gap is more balanced here than centering a
                                // short grid in all remaining vertical space.
                                ? fullscreenTopClearance + Math.round(Math.min(24,
                                    Math.max(0, fullscreenAvailableHeight - height) * 0.20))
                                : 14
                            clip: true
                            interactive: !root.isFullscreenMode
                            boundsBehavior: Flickable.StopAtBounds
                            // Reserve the search header in the resting
                            // layout without moving the viewport itself. The
                            // first row therefore never crowds the input, but
                            // scrolling tiles can still travel behind the
                            // header and emerge naturally below it.
                            topMargin: root.isFullscreenMode ? 0
                                : header.height + 8
                            // The visible card and grid cell share one source
                            // of truth. Density supplies the desired gap; cell
                            // width is then evenly divided across the usable
                            // width, so changing icon size never leaves a
                            // stranded right-side strip.
                            readonly property real tileWidth: root.gridIconSize + 30
                            readonly property real tileHeight: Math.max(88,
                                Math.round(root.gridIconSize + root.configFontSize * 2 + 24))
                            readonly property real targetCellWidth: tileWidth + root.gridGap
                            readonly property int columnCount: root.isFullscreenMode
                                ? Math.max(6, Math.min(10, Math.floor(width / targetCellWidth)))
                                : Math.max(4, Math.floor((width + root.gridGap)
                                    / Math.max(68, targetCellWidth)))
                            readonly property int fullscreenPageSize: root.isFullscreenMode
                                ? Math.max(1, columnCount * fullscreenRowCount) : 1
                            cellWidth: width > 0 ? width / columnCount : targetCellWidth
                            cellHeight: root.isFullscreenMode
                                ? Math.max(122, tileHeight + root.gridGap)
                                : tileHeight + root.gridGap
                            model: root.open && !root.isFullscreenMode
                                ? root.filteredApplications : []
                            // Card presentations only. In fullscreen the
                            // persistent slot pager takes over entirely, so
                            // this grid neither renders nor recreates
                            // delegates during page turns.
                            visible: !root.isFullscreenMode
                            // Delegate selection highlight resolves against the
                            // page the delegate lives on (this grid or a ghost).
                            property int pageBaseIndex: root.fullscreenPageOffset
                            // Fullscreen drag paging slides the whole page —
                            // this grid and both ghost neighbors share one
                            // horizontal offset so they travel in lockstep.
                            transform: Translate {
                                x: root.fullscreenPageTrackOffset
                            }

                        delegate: Item {
                            id: appDelegate
                            required property var modelData
                            required property int index
                            property bool dragging: reorderDrag.active && dragReorderStarted
                            property bool heldForEdit: false
                            property bool dragReorderStarted: false
                            property real lastDragX: 0
                            property real lastDragY: 0
                            // Commit only after this visual drop has reached the
                            // previewed slot. Updating GridView's model first would
                            // recreate delegates and flash the source through its old
                            // cell for one frame.
                            property bool dropping: false
                            property real dropOffsetX: 0
                            property real dropOffsetY: 0
                            readonly property bool launching: root.launchFeedbackItem === appDelegate
                            readonly property real dropTargetOffsetX: (root.rootDragTargetIndex % appGrid.columnCount) * appGrid.cellWidth + appGrid.cellWidth / 2 - (appDelegate.x + appDelegate.width / 2)
                            readonly property real dropTargetOffsetY: Math.floor(root.rootDragTargetIndex / appGrid.columnCount) * appGrid.cellHeight + appGrid.cellHeight / 2 - (appDelegate.y + appDelegate.height / 2)
                            // Rows fade in together in a restrained cascade only
                            // while the launcher initially opens. This remains a
                            // visual layer and never changes GridView cell geometry.
                            property bool entrancePending: root.gridEntranceActive && root.query.trim().length === 0
                            width: appGrid.cellWidth
                            height: appGrid.cellHeight
                            readonly property bool manipulating: dragging || dropping
                            z: manipulating ? 10 : 0
                            scale: manipulating ? 1.10 : (launching ? 0.93 : 1.0)
                            opacity: manipulating ? 0.90 : (launching ? 0.82 : (entrancePending ? 0.0 : 1.0))

                            Component.onCompleted: {
                                if (entrancePending)
                                    entranceDelay.restart();
                            }

                            Timer {
                                id: entranceDelay
                                // Delay by row, not every individual app, so the grid
                                // feels composed rather than like a typewriter.
                                interval: Math.min(120, Math.floor(index / Math.max(1, appGrid.columnCount)) * 24)
                                repeat: false
                                onTriggered: appDelegate.entrancePending = false
                            }
                            transform: Translate {
                                x: appDelegate.dragging ? reorderDrag.translation.x : (appDelegate.dropping ? appDelegate.dropOffsetX : root.rootPreviewOffset(index).x)
                                y: appDelegate.dragging ? reorderDrag.translation.y : (appDelegate.dropping ? appDelegate.dropOffsetY : root.rootPreviewOffset(index).y)
                                Behavior on x {
                                    enabled: !appDelegate.dragging
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on y {
                                    enabled: !appDelegate.dragging
                                    NumberAnimation {
                                        duration: 160
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on opacity {
                                enabled: !appDelegate.dragging
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Rectangle {
                                id: appCard
                                anchors.centerIn: parent
                                width: Math.round(root.gridIconSize + 30)
                                height: Math.round(root.gridIconSize
                                    + root.configFontSize * 2 + 20)
                                radius: Math.max(10, Math.round(root.gridIconSize * 0.25))
                                color: root.folderMergeArmed && root.folderMergeTargetKey === root._itemKey(modelData) ? Qt.rgba(0.36, 0.68, 1, 0.30) : (root.folderMergeTargetKey === root._itemKey(modelData) ? Qt.rgba(0.36, 0.68, 1, 0.14) : (root.keyboardSelectionActive && (index + appDelegate.GridView.view.pageBaseIndex) === root.selectedIndex ? Qt.rgba(1, 1, 1, 0.18) : (appMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")))
                                border.width: root.folderMergeTargetKey === root._itemKey(modelData) ? 1 : 0
                                border.color: Qt.rgba(0.36, 0.68, 1, root.folderMergeTargetKey === root._itemKey(modelData) ? 0.20 + root.folderMergeProgress * 0.42 : 0)
                                rotation: 0
                                SequentialAnimation {
                                    id: editWiggle
                                    running: root.editMode && !appDelegate.manipulating
                                    loops: Animation.Infinite
                                    NumberAnimation {
                                        target: appCard
                                        property: "rotation"
                                        from: -2.2
                                        to: 2.2
                                        duration: 110
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        target: appCard
                                        property: "rotation"
                                        from: 2.2
                                        to: -2.2
                                        duration: 110
                                        easing.type: Easing.InOutSine
                                    }
                                    onRunningChanged: {
                                        if (!running)
                                            appCard.rotation = 0;
                                    }
                                }

                                // Holding a dragged app over this card fills the
                                // line during the folderMergeTimer dwell. The line is
                                // deliberately light: it explains the gesture while
                                // leaving the app artwork and glass treatment intact.
                                Rectangle {
                                    visible: root.folderMergeTargetKey === root._itemKey(modelData)
                                    anchors {
                                        left: parent.left
                                        bottom: parent.bottom
                                        leftMargin: 13
                                        bottomMargin: 5
                                    }
                                    width: Math.max(0, (parent.width - 26) * root.folderMergeProgress)
                                    height: 2
                                    radius: height / 2
                                    color: Qt.rgba(0.48, 0.76, 1, 0.95)
                                }

                                AppIcon {
                                    visible: modelData.type === "app"
                                    width: root.gridIconSize
                                    height: root.gridIconSize
                                    anchors {
                                        top: parent.top
                                        horizontalCenter: parent.horizontalCenter
                                        topMargin: 8
                                    }
                                    source: modelData.type === "app" ? modelData.app.icon : ""
                                    opacityMultiplier: IconAppearanceService.mode === "color" ? 1.0 : IconAppearanceService.opacity
                                    saturation: IconAppearanceService.saturation
                                    tintEnabled: IconAppearanceService.tintEnabled
                                    tintColor: IconAppearanceService.tintColor
                                }

                                // Folder artwork is a compact 3×3 preview of its first
                                // nine apps. It intentionally stays within the same
                                // icon footprint as ordinary root applications. KWin owns
                                // the transparent glass beneath this preview.
                                Rectangle {
                                    visible: modelData.type === "folder"
                                    width: root.gridIconSize
                                    height: root.gridIconSize
                                    anchors {
                                        top: parent.top
                                        horizontalCenter: parent.horizontalCenter
                                        topMargin: 8
                                    }
                                    radius: Math.max(8, Math.round(root.configIconSize * 0.23))
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.isDark
                                        ? Qt.rgba(1, 1, 1, 0.14)
                                        : Qt.rgba(0, 0, 0, 0.12)

                                    Grid {
                                        anchors {
                                            top: parent.top
                                        topMargin: Math.max(3, Math.round(root.gridIconSize * 0.115))
                                            horizontalCenter: parent.horizontalCenter
                                        }
                                        columns: 3
                                        spacing: Math.max(1, Math.round(root.gridIconSize * 0.04))
                                        Repeater {
                                            model: modelData.type === "folder" ? modelData.apps.slice(0, 9) : []
                                            delegate: AppIcon {
                                                required property var modelData
                                                width: Math.max(8, Math.round(root.gridIconSize * 0.23))
                                                height: width
                                                source: modelData.icon
                                                opacityMultiplier: IconAppearanceService.mode === "color" ? 1.0 : IconAppearanceService.opacity
                                                saturation: IconAppearanceService.saturation
                                                tintEnabled: IconAppearanceService.tintEnabled
                                                tintColor: IconAppearanceService.tintColor
                                            }
                                        }
                                    }
                                }

                                // A restrained outline keeps labels readable over the
                                // translucent launcher material and changing wallpaper.
                                GlassText {
                                    id: appName
                                    anchors {
                                        top: parent.top
                                        topMargin: root.gridIconSize + 13
                                        horizontalCenter: parent.horizontalCenter
                                    }
                                    width: Math.min(Math.round(root.gridIconSize + Math.max(24, root.configFontSize * 3)), implicitWidth)
                                    text: modelData.type === "folder" ? modelData.name : modelData.app.name
                                    color: root.launcherForegroundColor
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    wrapMode: Text.NoWrap
                                    font {
                                        pixelSize: root.isFullscreenMode
                                            ? Math.max(11, root.configFontSize + 1)
                                            : root.configFontSize
                                        weight: root.resolvedFontWeight
                                        letterSpacing: 0.3
                                    }
                                }

                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    enabled: root.editingApplication === null
                                    hoverEnabled: true
                                    preventStealing: !root.editMode
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onPressed: appDelegate.heldForEdit = false
                                    onPressAndHold: {
                                        // Long press is spatial editing: it enables
                                        // drag sorting and app-to-app folder creation.
                                        // App settings remain a deliberate right-click
                                        // menu action so the two gestures never clash.
                                        // Launchpad pages deliberately remain stable;
                                        // rearranging across page boundaries belongs in
                                        // the bottom/center organizer views.
                                        if (root.isFullscreenMode)
                                            return;
                                        appDelegate.heldForEdit = true;
                                        root.editMode = true;
                                    }
                                    onClicked: function (mouse) {
                                        if (root.fullscreenSwipeSuppressClick)
                                            return;
                                        if (appDelegate.heldForEdit)
                                            return;
                                        // Edit mode is spatial manipulation. Root apps
                                        // neither launch nor open a context menu while
                                        // it is active; folders still open so their
                                        // contained apps can be sorted/removed.
                                        if (root.editMode) {
                                            if (mouse.button === Qt.LeftButton && modelData.type === "folder")
                                                root.showFolder(modelData, appDelegate);
                                            return;
                                        }
                                        if (mouse.button === Qt.RightButton && modelData.type === "app") {
                                            root.showApplicationMenu(modelData.app, appDelegate);
                                        } else {
                                            if (modelData.type === "folder")
                                                root.showFolder(modelData, appDelegate);
                                            else if (!root.editMode)
                                                root.launchApplication(modelData.app, appDelegate);
                                        }
                                    }
                                }
                            }

                            // GridView owns delegate geometry. The handler moves only
                            // the visual transform, then commits a durable order on
                            // release; it never fights GridView's layout bindings.
                            DragHandler {
                                id: reorderDrag
                                // Arm only after the long press has entered edit mode.
                                // If this handler captures the initial press early,
                                // `active` arrives before editMode becomes true and
                                // the live slot-preview state is never initialized.
                                enabled: root.editMode && !root.isFullscreenMode
                                    && root.editingApplication === null && !appDelegate.dropping
                                target: null
                                acceptedButtons: Qt.LeftButton
                                onActiveChanged: {
                                    if (active) {
                                        appDelegate.dragReorderStarted = true;
                                        appDelegate.dropping = false;
                                        appDelegate.lastDragX = 0;
                                        appDelegate.lastDragY = 0;
                                        root.rootDragSourceIndex = index;
                                        root.rootDragTargetIndex = index;
                                        root.clearFolderMergeCandidate();
                                    } else if (appDelegate.dragReorderStarted) {
                                        appDelegate.dropOffsetX = appDelegate.lastDragX;
                                        appDelegate.dropOffsetY = appDelegate.lastDragY;
                                        appDelegate.dropping = true;
                                        rootDropAnimation.restart();
                                    }
                                }
                                onTranslationChanged: {
                                    if (active && appDelegate.dragReorderStarted) {
                                        appDelegate.lastDragX = translation.x;
                                        appDelegate.lastDragY = translation.y;
                                        root.rootDragTargetIndex = root.dragTargetIndex(appDelegate);
                                        if (modelData.type === "app") {
                                            root.updateFolderMergeCandidate(modelData.app.id, appDelegate);
                                            // `rootPreviewOffset` uses this candidate
                                            // to hold the target still until merge is
                                            // armed or the pointer leaves it.
                                        } else {
                                            root.clearFolderMergeCandidate();
                                        }
                                    }
                                }
                            }

                            ParallelAnimation {
                                id: rootDropAnimation
                                NumberAnimation {
                                    target: appDelegate
                                    property: "dropOffsetX"
                                    to: appDelegate.dropTargetOffsetX
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: appDelegate
                                    property: "dropOffsetY"
                                    to: appDelegate.dropTargetOffsetY
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                                onFinished: {
                                    // At this point the old visual preview exactly
                                    // matches the new persisted GridView order.
                                    root.commitRootItemDrag(modelData, appDelegate);
                                    appDelegate.dropping = false;
                                    appDelegate.dragReorderStarted = false;
                                    appDelegate.heldForEdit = false;
                                }
                            }
                        }
                    }

                    // Fullscreen pager: three persistent page grids that own
                    // one page each (previous / current / next). Committing a
                    // page turn only re-labels slots, so the page that just
                    // slid into place keeps its already-rendered delegates
                    // and the landing cannot flash; only the vacated far
                    // slot reloads, offscreen and invisible. All three share
                    // the app grid's delegate and mirror its geometry.
                    GridView {
                        id: pagerA
                        property int slot: 0
                        property int assignedPage: 0
                        readonly property int clampedPage: Math.max(0,
                            Math.min(root.fullscreenPageCount - 1, assignedPage))
                        visible: root.open && root.isFullscreenMode
                            && (slot === 0
                                || (slot > 0 && root.fullscreenSwipeDirection === 1
                                    && root.fullscreenPage < root.fullscreenPageCount - 1)
                                || (slot < 0 && root.fullscreenSwipeDirection === -1
                                    && root.fullscreenPage > 0))
                        enabled: slot === 0
                        interactive: false
                        clip: true
                        x: appGrid.x + slot * root.fullscreenPageSlideWidth
                        y: appGrid.y
                        width: appGrid.width
                        height: appGrid.height
                        cellWidth: appGrid.cellWidth
                        cellHeight: appGrid.cellHeight
                        property int pageBaseIndex: clampedPage * appGrid.fullscreenPageSize
                        model: root.open && root.isFullscreenMode
                            ? root.fullscreenPageSlice(clampedPage) : []
                        delegate: appGrid.delegate
                        transform: Translate {
                            x: root.fullscreenPageTrackOffset
                        }
                    }

                    GridView {
                        id: pagerB
                        property int slot: 1
                        property int assignedPage: 0
                        readonly property int clampedPage: Math.max(0,
                            Math.min(root.fullscreenPageCount - 1, assignedPage))
                        visible: root.open && root.isFullscreenMode
                            && (slot === 0
                                || (slot > 0 && root.fullscreenSwipeDirection === 1
                                    && root.fullscreenPage < root.fullscreenPageCount - 1)
                                || (slot < 0 && root.fullscreenSwipeDirection === -1
                                    && root.fullscreenPage > 0))
                        enabled: slot === 0
                        interactive: false
                        clip: true
                        x: appGrid.x + slot * root.fullscreenPageSlideWidth
                        y: appGrid.y
                        width: appGrid.width
                        height: appGrid.height
                        cellWidth: appGrid.cellWidth
                        cellHeight: appGrid.cellHeight
                        property int pageBaseIndex: clampedPage * appGrid.fullscreenPageSize
                        model: root.open && root.isFullscreenMode
                            ? root.fullscreenPageSlice(clampedPage) : []
                        delegate: appGrid.delegate
                        transform: Translate {
                            x: root.fullscreenPageTrackOffset
                        }
                    }

                    GridView {
                        id: pagerC
                        property int slot: -1
                        property int assignedPage: 0
                        readonly property int clampedPage: Math.max(0,
                            Math.min(root.fullscreenPageCount - 1, assignedPage))
                        visible: root.open && root.isFullscreenMode
                            && (slot === 0
                                || (slot > 0 && root.fullscreenSwipeDirection === 1
                                    && root.fullscreenPage < root.fullscreenPageCount - 1)
                                || (slot < 0 && root.fullscreenSwipeDirection === -1
                                    && root.fullscreenPage > 0))
                        enabled: slot === 0
                        interactive: false
                        clip: true
                        x: appGrid.x + slot * root.fullscreenPageSlideWidth
                        y: appGrid.y
                        width: appGrid.width
                        height: appGrid.height
                        cellWidth: appGrid.cellWidth
                        cellHeight: appGrid.cellHeight
                        property int pageBaseIndex: clampedPage * appGrid.fullscreenPageSize
                        model: root.open && root.isFullscreenMode
                            ? root.fullscreenPageSlice(clampedPage) : []
                        delegate: appGrid.delegate
                        transform: Translate {
                            x: root.fullscreenPageTrackOffset
                        }
                    }

                    GlassText {
                        anchors.centerIn: parent
                        visible: !root.openFolder && root.filteredApplications.length === 0
                        text: root.applications.length === 0 ? "正在加载应用程序…" : "未找到匹配的应用"
                        color: root.launcherForegroundColor
                        opacity: 0.55
                        font.pixelSize: 14
                    }

                    // Launchpad-style page dots replace the long scrolling
                    // application sheet in fullscreen mode. They are kept
                    // outside the GridView, so changing pages never affects
                    // persisted application order or folder data. The dots
                    // sit in a horizontal translucent capsule whose radius is
                    // a true half-circle of its thickness.
                    Rectangle {
                        id: fullscreenPageDots
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            bottom: parent.bottom
                            // Sit just above the Bar/Dock strip the grid also
                            // clears: at least the 6% aesthetic margin, but
                            // pushed up under the floating Dock when present.
                            bottomMargin: Math.max(
                                Math.max(26, Math.round(parent.height * 0.055)),
                                appGrid.fullscreenBottomClearance - 8)
                        }
                        visible: root.isFullscreenMode && !root.openFolder
                            && root.fullscreenPageCount > 1

                        readonly property int dotSize: 6
                        readonly property int activeDotSize: 8
                        readonly property int dotSpacing: 7
                        readonly property int pad: 9
                        // Height fits the fat active dot; width grows with the
                        // page count. radius = thickness / 2 gives the
                        // half-circle endcaps.
                        height: pad * 2 + activeDotSize
                        width: pad * 2 + fullscreenPageCount * dotSize
                            + (fullscreenPageCount - 1) * dotSpacing
                        radius: height / 2
                        color: Qt.rgba(0.05, 0.06, 0.09, 0.34)
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                        Row {
                            anchors.centerIn: parent
                            spacing: fullscreenPageDots.dotSpacing
                            Repeater {
                                model: root.fullscreenPageCount
                                delegate: Rectangle {
                                    required property int index
                                    // The active state interpolates from the
                                    // float page position, so the dots track a
                                    // drag or settle animation continuously
                                    // instead of snapping when a page commits.
                                    readonly property real dotDistance: Math.abs(index - root.fullscreenPageProgress)
                                    readonly property real dotActiveShare: Math.max(0, Math.min(1, 1 - dotDistance))
                                    // Active dot swells to 8px while idle dots
                                    // stay 6px; verticalCenter alignment keeps
                                    // every dot on one shared midline instead
                                    // of the Row's default top edge, which made
                                    // the fat dot sag below the others.
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: fullscreenPageDots.dotSize
                                        + dotActiveShare * (fullscreenPageDots.activeDotSize - fullscreenPageDots.dotSize)
                                    height: width
                                    radius: width / 2
                                    color: Qt.rgba(1, 1, 1, 0.38 + 0.50 * dotActiveShare)
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.gotoFullscreenPage(index)
                                    }
                                }
                            }
                        }
                    }
                }

                    // Folder contents live in a centered modal rather than replacing
                    // the root grid. This preserves spatial context and keeps its
                    // membership/order mutations isolated from root ordering.
                    Item {
                        id: folderPage
                        anchors.fill: parent
                        z: 100
                        visible: root.displayedFolder !== null
                        enabled: root.folderDialogOpen && root.editingApplication === null

                        Rectangle {
                            anchors.fill: parent
                            // The backdrop dims as the folder opens, focusing attention
                            // on the scattered icons, then lifts as they collapse back.
                            color: Qt.rgba(0, 0, 0, 0.20)
                            opacity: root.folderDialogOpen ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.OutCubic
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.closeFolder()
                            }
                        }

                        Rectangle {
                            id: folderDialog
                            // The dialog is a true square whose side follows 80% of
                            // launcher height (or capped in fullscreen).
                            width: root.isFullscreenMode
                                ? Math.min(560, root.launcherHeight * 0.72)
                                : root.launcherHeight * 0.80
                            height: width
                            anchors.centerIn: parent
                            opacity: root.folderDialogOpen ? 1 : 0
                            scale: root.folderDialogOpen ? 1 : 0.85
                            radius: 22
                            // KWin supplies the glass; QML only defines dialog geometry
                            // and a minimal edge for pointer and text affordance.
                            color: "transparent"
                            border.width: 1
                            border.color: root.isDark
                                ? Qt.rgba(1, 1, 1, 0.16)
                                : Qt.rgba(0, 0, 0, 0.14)

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 160
                                    easing.type: Easing.OutCubic
                                }
                            }
                            // Liquid inflation: shrink then expand with a soft
                            // overshoot bounce, like the folder is swelling open.
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 220
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.6
                                }
                            }

                            Item {
                                id: folderHeader
                                anchors {
                                    top: parent.top
                                    left: parent.left
                                    right: parent.right
                                    margins: 20
                                }
                                height: 28

                                GlassText {
                                    anchors {
                                        left: parent.left
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "‹"
                                    color: AppLauncherService.dockForegroundColor
                                    font {
                                        pixelSize: 28
                                        weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.closeFolder()
                                    }
                                }

                                Text {
                                    id: folderTitle
                                    anchors.centerIn: parent
                                    visible: !root.folderRenameActive
                                    text: root.displayedFolder ? root.displayedFolder.name : "文件夹"
                                    color: AppLauncherService.dockForegroundColor
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.38)
                                    font {
                                        pixelSize: 16
                                        weight: Font.DemiBold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        // The title is deliberately visually quiet.
                                        // Double-click is the only edit affordance.
                                        onDoubleClicked: root.beginFolderRename()
                                    }
                                }

                                TextInput {
                                    id: folderNameInput
                                    anchors.centerIn: parent
                                    visible: root.folderRenameActive
                                    width: Math.min(180, parent.width - 100)
                                    horizontalAlignment: Text.AlignHCenter
                                    color: AppLauncherService.dockForegroundColor
                                    selectionColor: Qt.rgba(1, 1, 1, 0.30)
                                    selectedTextColor: AppLauncherService.dockForegroundColor
                                    text: root.folderRenameText
                                    font {
                                        pixelSize: 16
                                        weight: Font.DemiBold
                                    }
                                    onTextEdited: root.folderRenameText = text
                                    Keys.onPressed: function (event) {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            root.commitFolderRename();
                                            event.accepted = true;
                                        } else if (event.key === Qt.Key_Escape) {
                                            root.folderRenameActive = false;
                                            event.accepted = true;
                                        }
                                    }
                                }

                                // Only the active rename field receives an underline;
                                // the resting folder title remains visually minimal.
                                Rectangle {
                                    visible: root.folderRenameActive
                                    width: folderNameInput.width
                                    height: 1
                                    anchors {
                                        horizontalCenter: folderNameInput.horizontalCenter
                                        top: folderNameInput.bottom
                                        topMargin: 3
                                    }
                                    color: Qt.rgba(1, 1, 1, 0.68)
                                }

                                Text {
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                    }
                                    visible: opacity > 0.01
                                    opacity: root.folderEditMode ? 1.0 : 0.0
                                    scale: root.folderEditMode ? 1.0 : 0.82
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 140
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 140
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    text: "完成"
                                    color: AppLauncherService.dockForegroundColor
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.38)
                                    font {
                                        pixelSize: 13
                                        weight: Font.Bold
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        enabled: root.folderEditMode
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.commitFolderRename();
                                            root.folderEditMode = false;
                                        }
                                    }
                                }
                            }

                            GridView {
                                id: folderGrid
                                anchors {
                                    top: folderHeader.bottom
                                    topMargin: 10
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                    margins: 18
                                }
                                clip: true
                                readonly property real folderTileWidth: root.configIconSize + 30
                                readonly property real folderTargetCellWidth: folderTileWidth + root.gridGap
                                readonly property int columnCount: Math.max(3,
                                    Math.floor((width + root.gridGap)
                                        / Math.max(68, folderTargetCellWidth)))
                                cellWidth: width > 0 ? width / columnCount : folderTargetCellWidth
                                cellHeight: Math.max(88, Math.round(root.configIconSize
                                    + root.configFontSize * 2 + 24)) + root.gridGap
                                model: root.displayedFolder ? root.displayedFolder.apps : []

                                delegate: Item {
                                    id: folderAppDelegate
                                    required property var modelData
                                    required property int index
                                    property bool dragging: folderReorderDrag.active
                                    property bool heldForEdit: false
                                    property bool dragReorderStarted: false
                                    property real lastDragX: 0
                                    property real lastDragY: 0
                                    readonly property bool launching: root.launchFeedbackItem === folderAppDelegate
                                    // As in the root grid, delay the persistent model
                                    // update until this tile has visually landed in its
                                    // preview slot. That removes the old-cell flash.
                                    property bool dropping: false
                                    property real dropOffsetX: 0
                                    property real dropOffsetY: 0
                                    readonly property real dropTargetOffsetX: (root.folderPreviewTargetIndex % folderGrid.columnCount) * folderGrid.cellWidth + folderGrid.cellWidth / 2 - (folderAppDelegate.x + folderAppDelegate.width / 2)
                                    readonly property real dropTargetOffsetY: Math.floor(root.folderPreviewTargetIndex / folderGrid.columnCount) * folderGrid.cellHeight + folderGrid.cellHeight / 2 - (folderAppDelegate.y + folderAppDelegate.height / 2)
                                    width: folderGrid.cellWidth
                                    height: folderGrid.cellHeight
                                    readonly property bool manipulating: dragging || dropping
                                    z: manipulating ? 10 : 0
                                    scale: manipulating ? 1.10 : (launching ? 0.93 : 1.0)
                                    opacity: manipulating ? 0.90 : (launching ? 0.82 : 1.0)
                                    transform: Translate {
                                        x: folderAppDelegate.dragging ? folderReorderDrag.translation.x : (folderAppDelegate.dropping ? folderAppDelegate.dropOffsetX : root.folderPreviewOffset(index).x)
                                        y: folderAppDelegate.dragging ? folderReorderDrag.translation.y : (folderAppDelegate.dropping ? folderAppDelegate.dropOffsetY : root.folderPreviewOffset(index).y)
                                        Behavior on x {
                                            enabled: !folderAppDelegate.dragging
                                            NumberAnimation {
                                                duration: 160
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                        Behavior on y {
                                            enabled: !folderAppDelegate.dragging
                                            NumberAnimation {
                                                duration: 160
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 120
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 120
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    Rectangle {
                                        id: folderAppCard
                                        anchors.centerIn: parent
                                        width: Math.round(root.configIconSize + 30)
                                        height: Math.round(root.configIconSize
                                            + root.configFontSize * 2 + 20)
                                        // Keep the remove button above the delegate's
                                        // full-card MouseArea, otherwise that area
                                        // consumes its click before the button sees it.
                                        z: 1
                                        radius: Math.max(10, Math.round(root.configIconSize * 0.25))
                                        color: folderAppMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                        rotation: 0
                                        SequentialAnimation {
                                            id: folderWiggleAnimation
                                            running: root.folderEditMode && !folderAppDelegate.manipulating
                                            loops: Animation.Infinite
                                            alwaysRunToEnd: false
                                            NumberAnimation {
                                                target: folderAppCard
                                                property: "rotation"
                                                from: (index % 2 === 0) ? -1.8 : 1.8
                                                to: (index % 2 === 0) ? 1.8 : -1.8
                                                duration: (index % 3 === 0) ? 140 : 160
                                                easing.type: Easing.InOutSine
                                            }
                                            NumberAnimation {
                                                target: folderAppCard
                                                property: "rotation"
                                                from: (index % 2 === 0) ? 1.8 : -1.8
                                                to: (index % 2 === 0) ? -1.8 : 1.8
                                                duration: (index % 3 === 0) ? 140 : 160
                                                easing.type: Easing.InOutSine
                                            }
                                        }

                                        AppIcon {
                                            width: root.configIconSize
                                            height: root.configIconSize
                                            anchors {
                                                top: parent.top
                                                horizontalCenter: parent.horizontalCenter
                                                topMargin: 8
                                            }
                                            source: modelData.icon
                                            opacityMultiplier: IconAppearanceService.mode === "color" ? 1.0 : IconAppearanceService.opacity
                                            saturation: IconAppearanceService.saturation
                                            tintEnabled: IconAppearanceService.tintEnabled
                                            tintColor: IconAppearanceService.tintColor
                                        }

                                        GlassText {
                                            anchors {
                                                top: parent.top
                                                topMargin: root.configIconSize + 13
                                                horizontalCenter: parent.horizontalCenter
                                            }
                                            width: Math.min(Math.round(root.configIconSize + Math.max(24, root.configFontSize * 3)), implicitWidth)
                                            text: modelData.name
                                            color: AppLauncherService.dockForegroundColor
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                            font {
                                                pixelSize: root.configFontSize
                                                weight: root.resolvedFontWeight
                                                letterSpacing: 0.3
                                            }
                                        }

                                        Rectangle {
                                            // Removal is an edit-only control. It
                                            // follows the same restrained entrance as
                                            // the Done actions rather than popping on
                                            // top of the folder artwork.
                                            visible: opacity > 0.01
                                            opacity: root.folderEditMode ? 1.0 : 0.0
                                            scale: root.folderEditMode ? 1.0 : 0.76
                                            Behavior on opacity {
                                                NumberAnimation {
                                                    duration: 140
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: 140
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                            width: 21
                                            height: 21
                                            radius: width / 2
                                            anchors {
                                                top: parent.top
                                                right: parent.right
                                                topMargin: -5
                                                rightMargin: -5
                                            }
                                            color: Qt.rgba(0.95, 0.27, 0.25, 0.96)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "−"
                                                color: "white"
                                                font {
                                                    pixelSize: 17
                                                    weight: Font.Bold
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                enabled: root.folderEditMode
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.removeFolderApplication(modelData.id)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: folderAppMouse
                                        anchors.fill: parent
                                        enabled: root.editingApplication === null
                                        hoverEnabled: true
                                        preventStealing: !root.folderEditMode
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: folderAppDelegate.heldForEdit = false
                                        onPressAndHold: {
                                            folderAppDelegate.heldForEdit = true;
                                            root.folderEditMode = true;
                                        }
                                        onClicked: {
                                            if (!root.folderEditMode && !folderAppDelegate.heldForEdit)
                                                root.launchApplication(modelData, folderAppDelegate);
                                        }
                                    }

                                    DragHandler {
                                        id: folderReorderDrag
                                        enabled: root.folderEditMode && root.editingApplication === null && !folderAppDelegate.dropping
                                        target: null
                                        acceptedButtons: Qt.LeftButton
                                        onActiveChanged: {
                                            if (active) {
                                                folderAppDelegate.dragReorderStarted = true;
                                                folderAppDelegate.dropping = false;
                                                folderAppDelegate.lastDragX = 0;
                                                folderAppDelegate.lastDragY = 0;
                                                root.folderPreviewSourceIndex = index;
                                                root.folderPreviewTargetIndex = index;
                                            } else if (folderAppDelegate.dragReorderStarted) {
                                                folderAppDelegate.dropOffsetX = folderAppDelegate.lastDragX;
                                                folderAppDelegate.dropOffsetY = folderAppDelegate.lastDragY;
                                                folderAppDelegate.dropping = true;
                                                folderDropAnimation.restart();
                                            }
                                        }
                                        onTranslationChanged: {
                                            if (active) {
                                                folderAppDelegate.lastDragX = translation.x;
                                                folderAppDelegate.lastDragY = translation.y;
                                                root.folderPreviewTargetIndex = root.folderDragTargetIndex(folderAppDelegate);
                                            }
                                        }
                                    }

                                    ParallelAnimation {
                                        id: folderDropAnimation
                                        NumberAnimation {
                                            target: folderAppDelegate
                                            property: "dropOffsetX"
                                            to: folderAppDelegate.dropTargetOffsetX
                                            duration: 180
                                            easing.type: Easing.OutCubic
                                        }
                                        NumberAnimation {
                                            target: folderAppDelegate
                                            property: "dropOffsetY"
                                            to: folderAppDelegate.dropTargetOffsetY
                                            duration: 180
                                            easing.type: Easing.OutCubic
                                        }
                                        onFinished: {
                                            root.commitFolderApplicationDrag(modelData.id, folderAppDelegate);
                                            folderAppDelegate.dropping = false;
                                            folderAppDelegate.dragReorderStarted = false;
                                            folderAppDelegate.heldForEdit = false;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Application presentation editor. It owns only launcher-local
                    // metadata (name/icon/hidden state), never the desktop entry.
                    Item {
                        id: appEditorOverlay
                        anchors.fill: parent
                        // This is a real modal layer: it must sit above every
                        // launcher child and the underlying models are disabled while
                        // visible, so no DragHandler can receive pointer input.
                        z: 1000
                        visible: root.editingApplication !== null
                        focus: visible

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(0, 0, 0, 0.18)
                            MouseArea {
                                anchors.fill: parent
                                // Consume every button before lower delegate handlers
                                // can observe it. This is the modal input barrier.
                                acceptedButtons: Qt.AllButtons
                                preventStealing: true
                                onClicked: root.closeApplicationEditor()
                            }
                        }

                        Rectangle {
                            id: appEditorDialog
                            width: Math.min(420, parent.width - 80)
                            height: 400
                            anchors.centerIn: parent
                            focus: true
                            radius: 18
                            color: Qt.rgba(0.08, 0.09, 0.12, 0.82)

                            Column {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 12

                                Item {
                                    width: parent.width
                                    height: 30
                                    Text {
                                        anchors {
                                            left: parent.left
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: "编辑应用"
                                        color: AppLauncherService.dockForegroundColor
                                        style: Text.Outline
                                        styleColor: Qt.rgba(0, 0, 0, 0.38)
                                        font {
                                            pixelSize: 17
                                            weight: Font.DemiBold
                                        }
                                    }
                                    GlassText {
                                        anchors {
                                            right: parent.right
                                            verticalCenter: parent.verticalCenter
                                        }
                                        text: "×"
                                        color: AppLauncherService.dockForegroundColor
                                        font.pixelSize: 22
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -8
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeApplicationEditor()
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: 56
                                    spacing: 12
                                    AppIcon {
                                        width: 52
                                        height: 52
                                        source: AppPresentationService.iconSource(root.editorIcon)
                                            || AppPresentationService.genericIconSource()
                                        opacityMultiplier: IconAppearanceService.mode === "color" ? 1.0 : IconAppearanceService.opacity
                                        saturation: IconAppearanceService.saturation
                                        tintEnabled: IconAppearanceService.tintEnabled
                                        tintColor: IconAppearanceService.tintColor
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.chooseCustomIcon()
                                        }
                                    }
                                    GlassText {
                                        width: parent.width - 64
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.editingApplication ? root.editingApplication.id : ""
                                        color: AppLauncherService.dockForegroundColor
                                        opacity: 0.52
                                        elide: Text.ElideRight
                                        font.pixelSize: 11
                                    }
                                }

                                Row {
                                    width: parent.width
                                    height: 24
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            {
                                                name: "file",
                                                label: "选择图片文件"
                                            },
                                            {
                                                name: "clipboard",
                                                label: "粘贴剪贴板图片"
                                            },
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: implicitWidth + 18
                                            implicitWidth: actionLabel.implicitWidth
                                            height: 24
                                            radius: 7
                                            color: iconActionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)
                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 120
                                                }
                                            }
                                            GlassText {
                                                id: actionLabel
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: AppLauncherService.dockForegroundColor
                                                font.pixelSize: 10
                                            }
                                            MouseArea {
                                                id: iconActionMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.name === "file")
                                                        root.chooseCustomIcon();
                                                    else
                                                        root.pasteClipboardIcon();
                                                }
                                            }
                                        }
                                    }
                                }

                                GlassText {
                                    width: parent.width
                                    height: 12
                                    visible: root.editorIconStatus.length > 0
                                    text: root.editorIconStatus
                                    color: AppLauncherService.dockForegroundColor
                                    opacity: 0.62
                                    elide: Text.ElideRight
                                    font.pixelSize: 10
                                }

                                GlassText {
                                    text: "显示名称"
                                    color: AppLauncherService.dockForegroundColor
                                    opacity: 0.72
                                    font.pixelSize: 11
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 34
                                    radius: 8
                                    color: Qt.rgba(0, 0, 0, 0.20)
                                    // TextInput does not elide on its own; keep user
                                    // supplied names inside the dialog bounds.
                                    clip: true
                                    TextInput {
                                        id: appEditorNameInput
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        color: AppLauncherService.dockForegroundColor
                                        selectionColor: Qt.rgba(1, 1, 1, 0.30)
                                        selectedTextColor: AppLauncherService.dockForegroundColor
                                        text: root.editorName
                                        onTextEdited: root.editorName = text
                                        Keys.onReturnPressed: root.saveApplicationEditor()
                                    }
                                }

                                GlassText {
                                    text: "图标名称或本地路径"
                                    color: AppLauncherService.dockForegroundColor
                                    opacity: 0.72
                                    font.pixelSize: 11
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 34
                                    radius: 8
                                    color: Qt.rgba(0, 0, 0, 0.20)
                                    // A managed icon path can be long. Clip it here
                                    // while preserving TextInput's native horizontal
                                    // scrolling when the user edits the value.
                                    clip: true
                                    TextInput {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: Text.AlignVCenter
                                        color: AppLauncherService.dockForegroundColor
                                        selectionColor: Qt.rgba(1, 1, 1, 0.30)
                                        selectedTextColor: AppLauncherService.dockForegroundColor
                                        text: root.editorIcon
                                        onTextEdited: root.editorIcon = text
                                    }
                                }

                                Item {
                                    width: 1
                                    height: 2
                                }

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            {
                                                name: "reset",
                                                label: "恢复默认"
                                            },
                                            {
                                                name: "hide",
                                                label: "隐藏应用"
                                            },
                                            {
                                                name: "save",
                                                label: "保存"
                                            },
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            width: (appEditorDialog.width - 40 - 16) / 3
                                            height: 32
                                            radius: 8
                                            color: editorButtonMouse.containsMouse ? (modelData.name === "save" ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.20)) : (modelData.name === "save" ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10))
                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 120
                                                }
                                            }
                                            GlassText {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: AppLauncherService.dockForegroundColor
                                                font {
                                                    pixelSize: 12
                                                    weight: Font.Medium
                                                }
                                            }
                                            MouseArea {
                                                id: editorButtonMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.name === "save") {
                                                        root.saveApplicationEditor();
                                                    } else if (modelData.name === "hide") {
                                                        root.hideEditedApplication();
                                                    } else if (root.editingApplication) {
                                                        AppLauncherConfigService.updateAppOverride(root.editingApplication.id, root.editingApplication.defaultName, root.editingApplication.defaultIcon, root.editingApplication.defaultName, root.editingApplication.defaultIcon);
                                                        root.closeApplicationEditor();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // BackgroundEffect is a Wayland window attachment, so it belongs to this
    // PanelWindow root. The blur region is fixed at full card size. It never
    // scales or fades — only the foreground content animates on open.
    BackgroundEffect.blurRegion: (root.visible
        && (root.isFullscreenMode
            || AppearanceConfigService.effectiveLauncherBlur > 0.005
            || AppearanceConfigService.effectiveLauncherLiquid > 0.005))
        ? launcherBlurRegion
        : null

    RoundedBlurRegion {
        id: launcherBlurRegion
        item: launcherRevealClip
        radius: background.radius
    }
}
