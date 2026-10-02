import QtQuick
import QtTest
import "../.." as Settings

TestCase {
    name: "SpatialServices"
    when: windowShown
    QtObject {
        id: bridge
        property string lastError: ""
        property int starts: 0
        property int stops: 0
        property int cancels: 0
        signal wallpaperSnapshotChanged(var state)
        function wallpaperSnapshot() {}
        function inspectSpatialService() {}
        function initializeSpatialService() { starts++ }
        function disableSpatialService() { stops++ }
        function cancelWallpaperSpatial() { cancels++ }
        function clearSpatialCache(kind) {}
    }
    Component {
        id: factory
        Settings.ServicesSettingsPage {
            width: 760
            colors: ({card: "#222222", primaryText: "#ffffff", secondaryText: "#aaaaaa"})
        }
    }
    function test_service_switch_waits_for_completion() {
        const page = createTemporaryObject(factory, this, {bridge: bridge})
        verify(page)
        bridge.wallpaperSnapshotChanged({spatialResources: {available: true, enabled: false, ready: false}})
        const toggle = findChild(page, "spatialServiceSwitch")
        verify(toggle)
        compare(toggle.checked, false)
        toggle.clicked()
        compare(bridge.starts, 1)
        compare(toggle.checked, false)
        bridge.wallpaperSnapshotChanged({spatialResources: {available: true, enabled: false, busy: true, progress: 0.5}})
        compare(toggle.enabled, false)
        compare(toggle.checked, false)
        bridge.wallpaperSnapshotChanged({spatialResources: {available: true, enabled: true, ready: true}})
        compare(toggle.checked, true)
        toggle.clicked()
        compare(bridge.stops, 1)
    }
}
