import QtQuick
import Quickshell.Services.SystemTray
import qs.desktop.modules.common

// One tray entry rendered through the same AppIcon styling the Dock uses.
// Claude and Magpie publish dark tray silhouettes, so prefer their installed
// application icons. Attention artwork and other apps keep their live pixels.
AppIcon {
    id: root
    property var entry: null
    property string originalSource: entry?.icon || ""
    // Never infer an app from the Chromium ID shared by unrelated processes.
    readonly property string desktopId: {
        const id = String(entry?.id || "")
        if (/^(claude(?:_status_icon_\d+)?|com\.anthropic\.claude)$/i.test(id))
            return "com.anthropic.Claude.desktop"
        return /^magpie$/i.test(id) ? "magpie.desktop" : ""
    }
    readonly property bool needsAttention: entry?.status === SystemTrayItem.NeedsAttention
    readonly property string applicationSource: {
        const catalogRevision = AppPresentationService.catalogRevision
        const presentationRevision = AppPresentationService.revision
        if (!desktopId || needsAttention)
            return ""
        const app = AppPresentationService.entryFor(desktopId)
        const override = AppPresentationService.overrideFor(desktopId, desktopId)
        return AppPresentationService.iconSource(override.icon || app?.icon || "")
    }
    property bool applicationIconFailed: false
    onApplicationSourceChanged: applicationIconFailed = false
    onOriginalSourceChanged: applicationIconFailed = false
    onImageStatusChanged: {
        if (imageStatus === Image.Error) {
            // Synchronous loading may fail inside the source binding. Defer
            // fallback until it unwinds and recheck so stale errors cannot win.
            Qt.callLater(function() {
                if (root.imageStatus === Image.Error && root.source !== root.originalSource)
                    root.applicationIconFailed = true
            })
        }
    }

    source: applicationSource && !applicationIconFailed ? applicationSource : originalSource
    opacityMultiplier: IconAppearanceService.mode === "color"
        ? 1.0 : IconAppearanceService.opacity
    saturation: IconAppearanceService.saturation
    tintEnabled: IconAppearanceService.tintEnabled
    tintColor: IconAppearanceService.tintColor
}
