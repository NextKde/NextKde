pragma Singleton
import QtQuick
import qs.desktop.modules.common

// Runtime feedback only: canonical identities and window readiness belong to
// the existing services. Failed/windowless launches must never bounce forever.
QtObject {
    id: service
    property var pending: ({})
    function isLaunching(desktopId) { return pending[desktopId] !== undefined }
    function begin(desktopId) {
        const next = Object.assign({}, pending)
        next[desktopId] = Date.now()
        pending = next
    }
    function finish(desktopId) {
        if (!isLaunching(desktopId)) return
        const next = Object.assign({}, pending)
        delete next[desktopId]
        pending = next
    }
    function reconcile() {
        for (const desktopId of Object.keys(pending)) {
            if (WindowService.windowsForApp(desktopId).length > 0
                    || Date.now() - pending[desktopId] >= DockAnimation.launchFeedbackTimeoutMs)
                finish(desktopId)
        }
    }
    property Connections windows: Connections {
        target: WindowService
        function onRevisionChanged() { service.reconcile() }
    }
    property Connections actions: Connections {
        target: AppActionService
        function onLaunchFailed(appId) {
            service.finish(AppIdentityService.canonicalId(appId))
        }
    }
    property Timer expiry: Timer {
        running: Object.keys(service.pending).length > 0
        interval: 250
        repeat: true
        onTriggered: service.reconcile()
    }
}
