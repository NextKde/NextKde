pragma Singleton

import QtQuick
import Quickshell
import qs.desktop.modules.dock
import qs.desktop.modules.platform

// WidgetGalleryService — cross-window control for the widget gallery panel.
//
// The gallery floats in its own Overlay-layer window (WidgetGalleryWindow) so
// it can render above the Dock and the desktop's own Bottom-layer widgets/
// icons instead of sharing their stacking plane. DeskCenterWindow owns the
// desktop grid, drop-preview highlighting and placement logic and has no
// shared item tree with that window, so every cross-window interaction (open
// state, catalog, add requests) is plumbed through this singleton instead of
// QML parent-chain signals/mapToItem.
QtObject {
    id: service

    property bool open: false
    property bool minimized: false
    // The screen edit mode was entered on. Multi-monitor setups only ever
    // show one gallery instance, matching DeskCenterWindow's own
    // screen.name === ScreenLifecycle.activeScreen restriction.
    property var triggerScreen: null
    // Which sidebar category WidgetGalleryWindow should land on when it next
    // opens (applied once, on the open transition — not bound continuously,
    // since the user can freely switch categories afterwards). Callers
    // outside the gallery itself, e.g. the Dock's own "+ Widgets" entry
    // point, use this to jump straight to the "dock" category instead of
    // "all".
    property string requestedCategory: "all"

    property var catalog: []
    property var invalidPackages: []
    property var trippedPackages: []
    property var missingInstances: []
    property bool loading: false
    property string feedback: ""

    // The panel's own on-screen rect, in the active screen's full-output
    // coordinate space. DeskCenterWindow computes this from its insets (bar/
    // dock clearance) since it already owns that layout math; publishing the
    // result here keeps WidgetGalleryWindow a dumb consumer instead of a
    // second, independently-drifting copy of the same formulas.
    property real galleryX: 0
    property real galleryY: 0
    property real galleryWidth: 0
    property real galleryHeight: 0

    // Drag-to-place was dropped as the primary add gesture (too much surface
    // for cross-window drag tracking to get right); adding a widget is now a
    // single click/tap on its (+) badge, resolved locally by
    // DeskCenterWindow's own addGalleryWidget() auto-placement.
    signal addRequested(var entry, string size)
    signal reEnableRequested(string packageId)
    signal removeRetiredInstanceRequested(string instanceId)
    signal done()

    function show(screen = null, category = "all") {
        service.triggerScreen = screen
        service.requestedCategory = category
        service.minimized = false
        service.open = true
    }
    function hide() {
        service.minimized = false
        service.open = false
    }
    function setMinimized(value) { service.minimized = !!value }
    function toggleMinimized() { service.minimized = !service.minimized }
    function _findSettingsWindow() {
        const records = WindowService.records || []
        for (let i = 0; i < records.length; i++) {
            const record = records[i]
            if (record && AppIdentityService.sameApp(record.identity, "kos-settings"))
                return record
        }
        return null
    }
    function _activateSettingsWindow() {
        const existing = service._findSettingsWindow()
        if (existing) {
            WindowService.activateWindow(existing.windowId)
            return true
        }
        return false
    }
    function openPluginStore() {
        // Activate any existing Settings window through KWin so minimized or
        // other-workspace windows are unminimized and brought forward, while
        // navigating it to the Plugins tab.
        service._activateSettingsWindow()
        PlatformClient.request("settings.launch", {
            shellDir: Quickshell.shellDir,
            app: "plugins"
        }, function(response) {
            if (response?.ok) {
                service._activateSettingsWindow()
                return
            }
            console.warn("[WidgetGalleryService] openPluginStore failed, falling back to Settings: "
                + (response?.error?.message || "platform unavailable"))
            if (!service._activateSettingsWindow()) {
                PlatformClient.request("settings.launch", {
                    shellDir: Quickshell.shellDir
                }, function() {})
            }
        })
    }
    function toggle(screen = null) {
        if (service.open) service.hide()
        else service.show(screen)
    }
}
