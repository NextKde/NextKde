import QtQuick
import qs.desktop.modules.common

// Shared by popup artwork and history/source badges. Notification images are
// content, not app identity: never replace them with a theme icon. For identity
// artwork, try the installed app's theme icon before any fixed app-supplied
// image. Keep this policy local to notifications, not the shared app resolver.
Item {
    id: root
    property string image: ""
    property string appIcon: ""
    property string desktopEntry: ""
    property color ink: "white"
    property int candidateIndex: 0

    // Desktop files and notification senders sometimes supply an absolute
    // hicolor/vendor path instead of a theme name. A matching basename in the
    // current theme is a better source badge; arbitrary URLs remain artwork.
    function themeName(candidate) {
        let value = String(candidate || "").trim()
        if (value.startsWith("image://icon/"))
            value = value.substring("image://icon/".length)
        if (value.startsWith("file://")) {
            if (!value.startsWith("file:///")) return ""
            try { value = decodeURIComponent(value.substring(7)) } catch (e) { return "" }
        }
        if (value.startsWith("/"))
            value = value.substring(value.lastIndexOf("/") + 1).replace(/\.(svgz?|png|xpm|ico|jpe?g|webp)$/i, "")
        // Preserve the common resolver's safe alias for malformed hwloc SVGs.
        if (value.toLowerCase() === "hwloc") return "preferences-devices-cpu"
        return /[/:]/.test(value) ? "" : value
    }

    readonly property var candidates: {
        const revision = IconThemeReloadService.revision
        const catalogRevision = AppPresentationService.catalogRevision
        const result = []
        function append(source) {
            if (source && result.indexOf(source) < 0) result.push(source)
        }
        // Render actual content URLs/files directly, without the common
        // resolver's app-brand aliases or icon-provider path wrapping.
        const content = String(image || "").trim()
        if (content.startsWith("/")) append("file://" + content)
        else if (/^[a-z][a-z0-9+.-]*:/i.test(content) || content.startsWith(":")) append(content)
        else append(AppPresentationService.iconSource(content))
        const entry = desktopEntry ? AppPresentationService.entryFor(desktopEntry) : null
        const entryIcon = String(entry?.icon || "")
        // Bypass bundled-brand aliases only for themed notification artwork.
        // Custom fallback sources still use the common source normalization.
        for (const value of [entryIcon, appIcon, String(entry?.id || desktopEntry).replace(/\.desktop$/i, "")]) {
            const name = themeName(value)
            if (name) append(SystemIconResolver.sourceFromCandidates([name], name))
        }
        append(AppPresentationService.iconSource(appIcon))
        append(AppPresentationService.iconSource(entryIcon))
        return result
    }
    readonly property bool usesFallback: candidateIndex >= candidates.length
    readonly property string source: candidates[candidateIndex] || ""
    readonly property int imageStatus: renderer.item?.imageStatus ?? Image.Null
    onCandidatesChanged: candidateIndex = 0

    Connections {
        target: IconThemeReloadService
        function onRevisionChanged() {
            // A themed provider URL can stay identical across themes. Changing
            // candidates/cache alone does not reload that Image. Recreate only
            // this renderer, after the shared cache invalidation has completed.
            renderer.active = false
            Qt.callLater(function() {
                root.candidateIndex = 0
                renderer.active = true
            })
        }
    }

    Loader {
        id: renderer
        anchors.fill: parent
        visible: !root.usesFallback
        sourceComponent: AppIcon {
            source: root.source
            asynchronous: false
            onImageStatusChanged: {
                if (imageStatus !== Image.Error || root.usesFallback) return
                const failedSource = source
                const failedIndex = root.candidateIndex
                Qt.callLater(function() {
                    if (root.source === failedSource && root.candidateIndex === failedIndex
                            && root.imageStatus === Image.Error && !root.usesFallback)
                        root.candidateIndex++
                })
            }
        }
    }
    BundledIcon {
        anchors.fill: parent
        visible: root.usesFallback
        name: "notification.sourceFallback"
        color: root.ink
    }
}
