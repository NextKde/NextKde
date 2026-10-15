pragma Singleton
import QtQuick
import Quickshell.Services.UPower
import qs.desktop.modules.platform
import "../../../shared/qml/i18n"

QtObject {
    id: service
    property var platform: PlatformClient
    property var systemProfiles: PowerProfiles
    property var profiles: []
    property string activeProfile: ""
    property string degraded: ""
    property bool loading: false
    property bool changing: false
    property string pendingProfile: ""
    property string error: ""
    property int revision: 0
    function profileId(profile) {
        return profile === PowerProfile.PowerSaver ? "power-saver"
            : profile === PowerProfile.Performance ? "performance" : "balanced"
    }

    // Observe D-Bus updates rather than launching a helper every five seconds.
    // Invalidate reads already in flight so an old snapshot cannot undo a signal.
    property Connections systemChanges: Connections {
        target: service.systemProfiles
        function onProfileChanged() {
            service.revision++
            service.activeProfile = service.profileId(service.systemProfiles.profile)
        }
        function onHasPerformanceProfileChanged() {
            if (service.profiles.length > 0) service.refresh()
        }
        function onDegradationReasonChanged() {
            service.degraded = service.systemProfiles.degradationReason === PerformanceDegradationReason.None
                ? "" : PerformanceDegradationReason.toString(service.systemProfiles.degradationReason)
        }
    }
    function refresh() {
        if (loading || changing) return
        loading = true
        const observedRevision = revision
        platform.request("power.profiles", {}, function(response) {
            service.loading = false
            if (response?.ok) {
                const available = response.result.profiles || []
                if (JSON.stringify(service.profiles) !== JSON.stringify(available)) service.profiles = available
                if (observedRevision === service.revision)
                    service.activeProfile = response.result.activeProfile || ""
                service.degraded = response.result.degraded || ""
                if (!available.length)
                    service.error = I18n.tr("Power modes are not available on this system")
                else if (service.pendingProfile && service.activeProfile !== service.pendingProfile)
                    service.error = I18n.tr("The system did not keep the requested power mode.")
                else service.error = ""
                service.pendingProfile = ""
            } else {
                service.profiles = []
                service.error = I18n.tr("Power modes are not available on this system")
                service.pendingProfile = ""
            }
        })
    }
    function setProfile(profile) {
        if (changing || loading || !profiles.includes(profile) || profile === activeProfile) return
        revision++
        changing = true
        pendingProfile = profile
        error = ""
        platform.request("power.profile.set", {profile: profile}, function(response) {
            service.changing = false
            if (!response?.ok) {
                service.pendingProfile = ""
                service.error = I18n.tr("Could not change power mode. Check system permissions and try again.")
                return
            }
            // Exit status alone does not prove the system retained the mode.
            // Native signals update the checkmark immediately; confirm the write
            // and surface policy/hardware rejections through one readback.
            service.refresh()
        })
    }
}
