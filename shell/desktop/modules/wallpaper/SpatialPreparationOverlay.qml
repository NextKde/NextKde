import QtQuick
import "../../../shared/qml/i18n"
import qs.desktop.modules.common

// Preparation and failures use the same global dialog as trash confirmation.
DesktopConfirmDialog {
    id: root
    property bool presentationAllowed: true
    readonly property bool preparing: SpatialWallpaperService.preparationRequested
    readonly property string message: SpatialWallpaperService.errorMessage
    readonly property bool hasStatus: preparing || message.length > 0

    titleText: preparing ? I18n.tr("Generating spatial wallpaper") : I18n.tr("Spatial wallpaper is not enabled")
    bodyText: preparing
        ? ((SpatialResourceService.stage || I18n.tr("Preparing depth effect…"))
            + (SpatialResourceService.busy && SpatialResourceService.progress >= 0
                ? " · " + Math.round(SpatialResourceService.progress * 100) + "%" : ""))
        : message
    iconName: "spatial-wallpaper"
    destructive: false
    confirmVisible: false
    cancelText: preparing ? I18n.tr("Cancel") : I18n.tr("Close")
    dismissOnBackdrop: !preparing
    onRejected: SpatialWallpaperService.cancelActivation()

    function syncPresentation() {
        if (presentationAllowed && hasStatus) {
            if (!requestedOpen) open()
        } else if (requestedOpen) close()
    }
    onPresentationAllowedChanged: Qt.callLater(syncPresentation)
    onHasStatusChanged: Qt.callLater(syncPresentation)
    Component.onCompleted: Qt.callLater(syncPresentation)
}
