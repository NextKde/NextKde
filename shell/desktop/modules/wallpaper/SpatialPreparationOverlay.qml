import QtQuick
import qs.desktop.modules.common

// Preparation and failures use the same global dialog as trash confirmation.
DesktopConfirmDialog {
    id: root
    property bool presentationAllowed: true
    readonly property bool preparing: SpatialWallpaperService.preparationRequested
    readonly property string message: SpatialWallpaperService.errorMessage
    readonly property bool hasStatus: preparing || message.length > 0

    titleText: preparing ? "正在生成空间壁纸" : "空间壁纸未开启"
    bodyText: preparing
        ? ((SpatialResourceService.stage || "正在准备景深效果…")
            + (SpatialResourceService.busy && SpatialResourceService.progress >= 0
                ? " · " + Math.round(SpatialResourceService.progress * 100) + "%" : ""))
        : message
    iconName: "spatial-wallpaper"
    destructive: false
    confirmVisible: false
    cancelText: preparing ? "取消" : "关闭"
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
