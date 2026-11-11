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
    BundledIcon {
        anchors.fill: parent
        visible: root.usesFallback
        name: "bell"
        color: root.ink
    }
}
