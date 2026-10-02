import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
DesktopConfirmDialog {
    id: popup
    confirmEnabled: !DockTrashService.emptying
    confirmBusy: DockTrashService.emptying
    onAccepted: DockTrashService.empty()
    onVisibleChanged: if(!visible) DockModelService.releaseDockPopup(popup)
}
