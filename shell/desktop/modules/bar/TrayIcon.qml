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
    readonly property string bundledTemplate: Templates.bundledTemplate(applicationId, applicationName)
    readonly property bool needsAttention: entry !== null
        && entry.status === SystemTrayItem.NeedsAttention
    property bool dynamicArtwork: false
    readonly property bool useTemplate: followAppearance && !needsAttention && !dynamicArtwork

    // An application that changes its icon owns subsequent status artwork.
    Connections {
        target: root.entry
        function onIconChanged() { root.dynamicArtwork = true }
    }

    // The filled Clash silhouette needs less space to match the other tray glyphs.
    scale: useTemplate && bundledTemplate === "clash-verge.png" ? 0.85 : 1.0

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
    source: useTemplate ? templateSource : originalSource
    recolorEnabled: followAppearance
    recolorColor: ThemeService.barInk
}
