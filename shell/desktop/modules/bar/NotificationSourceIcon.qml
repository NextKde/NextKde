import QtQuick
import qs.desktop.modules.common

// Notification appIcon may be a theme name, path or URL. Shared application
// presentation resolves it, then the installed desktop entry supplies a
// fallback. Failed image decoding advances to the next candidate.
Item {
    id: root
    property string appIcon: ""
    property string desktopEntry: ""
    property color ink: "white"
    property int candidateIndex: 0
    readonly property var candidates: {
        const revision = AppPresentationService.revision
        const catalogRevision = AppPresentationService.catalogRevision
        const result = []
        const primary = AppPresentationService.iconSource(appIcon)
        if (primary) result.push(primary)
        const entry = desktopEntry ? AppPresentationService.entryFor(desktopEntry) : null
        const fallback = entry ? AppPresentationService.iconSource(entry.icon || "") : ""
        if (fallback && result.indexOf(fallback) < 0) result.push(fallback)
        return result
    }
    readonly property bool usesFallback: candidateIndex >= candidates.length
    onCandidatesChanged: candidateIndex = 0
    AppIcon {
        id: artwork
        anchors.fill: parent
        visible: !root.usesFallback
        source: root.candidates[root.candidateIndex] || ""
        asynchronous: false
        onImageStatusChanged: {
            if (imageStatus === Image.Error && !root.usesFallback) {
                const failedSource = source
                Qt.callLater(function() {
                    if (artwork.source === failedSource && artwork.imageStatus === Image.Error
                            && !root.usesFallback)
                        root.candidateIndex++
                })
            }
        }
    }
    Image {
        anchors.fill: parent
        visible: root.usesFallback
        // Reuse the registry's solid artwork, tinting its SVG directly. A
        // plain image also remains visible under Qt's software renderer.
        source: "data:image/svg+xml;utf8," + encodeURIComponent(
            BundledIcons.svg.bell.replace(/#ffffff/g, String(root.ink)))
        sourceSize.width: Math.max(8, Math.round(root.width * 2))
        sourceSize.height: Math.max(8, Math.round(root.height * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: false
    }
}
