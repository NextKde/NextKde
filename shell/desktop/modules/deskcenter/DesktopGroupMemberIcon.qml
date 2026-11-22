import QtQuick
import Quickshell.Widgets
import qs.desktop.modules.common

// One small member artwork for the desktop type-group card and its overlay.
// Resolution mirrors the desktop grid: app shortcuts follow the shell-wide
// icon appearance, images keep their own thumbnail, and every other kind uses
// the system icon theme for that file kind.
Item {
    id: root

    required property var entry
    property real size: 40
    // Same path-keyed appearance record the normal icon field reads.
    property var folderCustom: null

    implicitWidth: size
    implicitHeight: size

    readonly property string kind: entry?.kind ?? "file"
    readonly property bool isLauncher: kind === "launcher"
    readonly property bool isImage: kind === "image"
    readonly property bool folderCustomized: kind === "folder"
        && folderCustom && (!!folderCustom.color || !!folderCustom.emoji)

    readonly property string launcherSource: {
        if (!isLauncher || !entry)
            return ""
        // AppLauncherConfigService publishes overrides asynchronously after
        // its tiny startup config read. Depend on the revision so existing
        // delegates update when that read completes.
        AppPresentationService.revision
        const launcherId = entry.name || entry.path.split("/").pop()
        const override = AppPresentationService.overrideFor(launcherId,
            launcherId)
        return AppPresentationService.iconSource(override.icon || entry.icon)
    }

    readonly property string themeSource: isLauncher || isImage
        ? "" : SystemIconResolver.sourceFromCandidates(
            SystemIconResolver.candidates("desktop.file." + kind),
            "text-x-generic")

    readonly property string fallbackName: {
        const type = ["folder", "image", "pdf", "code", "text", "launcher"]
            .indexOf(kind) >= 0 ? kind : "text"
        return "desktop.file." + type
    }

    readonly property bool launcherShown: isLauncher
        && launcherSource !== ""
    readonly property bool imageShown: isImage
        && thumbnail.status === Image.Ready
    readonly property bool themeShown: !isLauncher && !isImage
        && !folderCustomized && themeSource !== ""
        && themeIcon.status === Image.Ready
    // A still-loading image gets no fallback glyph (it would flash a file
    // icon); only a real decode failure falls back.
    readonly property bool fallbackShown: {
        if (isLauncher)
            return !launcherShown
        if (isImage)
            return thumbnail.status === Image.Error
        if (folderCustomized)
            return false
        return !themeShown
    }

    AppIcon {
        anchors.fill: parent
        visible: root.launcherShown
        source: root.launcherSource
        asynchronous: false
        opacityMultiplier: IconAppearanceService.mode === "color"
            ? 1.0 : IconAppearanceService.opacity
        saturation: IconAppearanceService.saturation
        tintEnabled: IconAppearanceService.tintEnabled
        tintColor: IconAppearanceService.tintColor
    }

    Image {
        id: thumbnail
        anchors.fill: parent
        visible: root.imageShown
        source: root.isImage && root.entry ? "file://" + root.entry.path : ""
        fillMode: Image.PreserveAspectCrop
        // The overlay draws around 46 px; request 2x so HiDPI stays sharp
        // without retaining the full decoded image.
        sourceSize: Qt.size(Math.max(1, Math.ceil(root.width * 2)),
            Math.max(1, Math.ceil(root.height * 2)))
        asynchronous: true
        cache: true
        smooth: true
    }

    IconImage {
        id: themeIcon
        anchors.fill: parent
        visible: root.themeShown
        source: root.themeSource
        // Theme icon: synchronous, see AppIcon.qml.
        asynchronous: false
    }

    // A customized folder keeps its user colour and emblem, exactly like the
    // normal desktop artwork, instead of falling back to the theme folder.
    DesktopFolderIcon {
        anchors.fill: parent
        visible: root.folderCustomized
        color: root.folderCustom && root.folderCustom.color
            ? root.folderCustom.color : "#70b6ff"
        emoji: root.folderCustom ? root.folderCustom.emoji || "" : ""
    }

    BundledIcon {
        anchors.centerIn: parent
        // Only the fallback cases draw this: an empty launcher source, an
        // image that failed to decode, or a kind the theme has no icon for.
        visible: root.fallbackShown
        name: root.fallbackName
        color: AppearanceTokens.surface.pick(
            AppearanceTokens.colors.surfaceVariantForeground,
            Qt.rgba(1, 1, 1, 0.82))
        size: Math.max(12, Math.min(root.width, root.height) * 0.68)
        outlined: true
    }
}
