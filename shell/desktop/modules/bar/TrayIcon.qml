import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock
import "TrayIconTemplates.mjs" as Templates

AppIcon {
    id: root
    property string originalSource: ""
    property string applicationId: ""
    property string applicationName: ""
    property bool followAppearance: IconAppearanceService.trayFollowsBarColor
    readonly property string bundledTemplate: Templates.bundledTemplate(applicationId, applicationName)

    // The filled Clash silhouette needs less space to match the other tray glyphs.
    scale: followAppearance && bundledTemplate === "clash-verge.png" ? 0.85 : 1.0

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
    source: followAppearance ? templateSource : originalSource
    recolorEnabled: followAppearance
    recolorColor: ThemeService.barInk
}
