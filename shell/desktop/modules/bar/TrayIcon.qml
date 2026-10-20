import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "TrayIconTemplates.mjs" as Templates

AppIcon {
    id: root
    property var entry: null
    property string originalSource: entry?.icon || ""
    property string applicationId: ""
    property string applicationName: ""
    property bool followAppearance: IconAppearanceService.trayFollowsBarColor
    property bool templateLoadFailed: false
    readonly property string bundledTemplate: Templates.bundledTemplate(applicationId, applicationName)
    readonly property bool needsAttention: entry !== null
        && entry.status === SystemTrayItem.NeedsAttention
    property bool dynamicArtwork: false
    // Clash refreshes its normal tray artwork as connection/proxy state changes.
    // Its colored badge has an opaque round background, so flattening that
    // artwork would erase the cat's details. Keep its template for normal
    // refreshes, while explicit attention artwork still belongs to the app.
    readonly property bool useTemplate: followAppearance && !needsAttention
        && (!dynamicArtwork || bundledTemplate === "clash-verge.png")

    // An application that changes its icon owns subsequent status artwork.
    Connections {
        target: root.entry
        function onIconChanged() { root.dynamicArtwork = true }
    }

    // The filled Clash silhouette needs less space to match the other tray glyphs.
    scale: useTemplate && !templateLoadFailed && bundledTemplate === "clash-verge.png" ? 0.85 : 1.0

    readonly property string templateSource: {
        const revision = IconThemeReloadService.revision
        const bundled = root.bundledTemplate
        if (bundled) return Qt.resolvedUrl("../../assets/tray/" + bundled).toString()
        const candidates = Templates.symbolicCandidates(originalSource, applicationId, applicationName)
        for (const candidate of candidates) {
            if (Quickshell.hasThemeIcon(candidate)) return Quickshell.iconPath(candidate)
        }
        return originalSource
    }
    onTemplateSourceChanged: templateLoadFailed = false
    onOriginalSourceChanged: templateLoadFailed = false
    onUseTemplateChanged: templateLoadFailed = false
    onImageStatusChanged: {
        if (imageStatus === Image.Error) {
            // A synchronous image failure can arrive while source is still
            // evaluating. Change it only after that binding has unwound, and
            // recheck the current image so a stale failure cannot win a race.
            Qt.callLater(function() {
                if (root.imageStatus === Image.Error && root.source !== root.originalSource)
                    root.templateLoadFailed = true
            })
        }
    }
    source: useTemplate && !templateLoadFailed ? templateSource : originalSource
    recolorEnabled: followAppearance
    recolorColor: ThemeService.barInk
}
