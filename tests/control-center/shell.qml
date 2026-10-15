import QtQuick
import Quickshell
import qs.desktop.modules.bar
import "desktop/modules/bar/controlcenter" as Parts

ShellRoot {
    id: test
    property var events: []
    property real preview: 35
    property bool dragging: false
    property var selectedNetwork: null
    property int step: 0
    property int checks: 0
    property int navigation: 0
    property int ticks: 0
    readonly property var pages: ["wifi", "bluetooth", "sound", "brightness"]
    function record(value) { events = events.concat([value]) }
    function check(condition, message) {
        if (!condition) throw new Error(message)
        checks++
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const match = find(child, name)
            if (match) return match
        }
        return null
    }
    function eventAt(item, name) {
        const control = find(item, name)
        check(control !== null, "missing control " + name)
        return control
    }

    QtObject {
        id: networkBackend
        property bool available: true
        property bool wifiEnabled: false
        property bool wifiToggleInProgress: false
        property bool wifiScanInProgress: false
        property string connectionType: "wifi"
        property string deviceState: "connected"
        property string ssid: "Fixture"
        property int signalStrength: 80
        property var nearbyWifi: []
        function setWifiEnabled(value) { wifiEnabled = value; test.record("wifi:" + value) }
        function connectWifi(ssid, password, uuid) { test.record("connect:" + ssid + ":" + uuid) }
        function disconnectActiveWifi() { test.record("disconnect") }
    }
    QtObject {
        id: serviceBackend
        property bool bluetoothAvailable: true
        property bool bluetoothPowered: false
        property bool bluetoothChangeInProgress: false
        property bool bluetoothDeviceChangeInProgress: false
        property bool bluetoothDevicesRefreshInProgress: false
        property var bluetoothDevices: []
        property bool brightnessAvailable: true
        property bool brightnessChangeInProgress: false
        property int brightnessPercent: 50
        property var brightnessDisplays: []
        property bool audioMuted: false
        property int volumePercent: 35
        property var audioApplications: []
        property var audioOutputs: []
        property bool audioApplicationsRefreshInProgress: false
        property bool audioOutputsRefreshInProgress: false
        property bool audioOutputChangeInProgress: false
        property string audioOutputError: ""
        property bool keepAwakeEnabled: false
        property bool keepAwakeAvailable: true
        property bool keepAwakeChangeInProgress: false
        property string keepAwakeError: ""
        property string currentUserName: "Fixture"
        property string lastSessionError: ""
        function setBluetoothEnabled(value) { bluetoothPowered = value; test.record("bluetooth:" + value) }
        function setVolume(value) { test.record("volume:" + value) }
        function setMuted(value) { audioMuted = value; test.record("muted:" + value) }
        function setBrightness(value) { test.record("brightness:" + value) }
        function toggleKeepAwake() { keepAwakeEnabled = !keepAwakeEnabled; test.record("awake") }
    }
    QtObject {
        id: mediaBackend
        property bool loading: false
        property string playbackStatus: "Stopped"
        function previous() { test.record("previous") }
        function togglePlayPause() { test.record("play") }
        function next() { test.record("next") }
    }
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 1000
        implicitHeight: 800
        Item { id: anchorItem; x: 120; y: 20; width: 40; height: 30 }
        Parts.WifiCard {
            id: wifi; network: networkBackend; cardWidth: 150; cardHeight: 59
            onPageRequested: test.record("wifi-page")
        }
        Parts.BluetoothCard {
            id: bluetooth; service: serviceBackend; x: 160; cardWidth: 150; cardHeight: 59
            onPageRequested: test.record("bluetooth-page")
        }
        Parts.SoundCard {
            id: sound; y: 70; service: serviceBackend; cardWidth: 296; cardHeight: 57
            volumePreview: test.preview
            onVolumePreviewRequested: value => test.preview = value
            onDraggingVolumeRequested: value => test.dragging = value
        }
        Parts.SoundPage {
            id: soundPage; service: serviceBackend; x: 320; width: 296; height: 360
            volumePreview: test.preview
            onVolumePreviewRequested: value => test.preview = value
            onDraggingVolumeRequested: value => test.dragging = value
        }
        Parts.WifiPage {
            id: wifiPage; network: networkBackend; y: 140; width: 296; height: 310
            onWifiNetworkSelected: value => {
                test.record("close")
                networkBackend.nearbyWifi = []
                test.record("credentials")
                test.selectedNetwork = value
            }
        }
        Parts.MediaCard {
            id: mediaCard; media: mediaBackend; x: 650; cardWidth: 160; cardHeight: 127
            player: ({canGoPrevious: true, canGoNext: true, canTogglePlaying: true,
                      isPlaying: false, trackTitle: "Fixture", trackArtist: "Artist", trackArtUrl: ""})
        }
    }
    ControlCenterPanel { id: center; anchorItem: anchorItem }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            try {
                if (++test.ticks > 200) throw new Error("timeout at step " + test.step)
                switch (test.step) {
                case 0:
                    eventAt(wifi, "wifiTogglePointer").clicked(null)
                    eventAt(wifi, "wifiPagePointer").clicked(null)
                    eventAt(bluetooth, "bluetoothTogglePointer").clicked(null)
                    eventAt(bluetooth, "bluetoothPagePointer").clicked(null)
                    check(networkBackend.wifiEnabled && serviceBackend.bluetoothPowered, "injected toggles receive clicks")
                    check(events.indexOf("wifi-page") >= 0 && events.indexOf("bluetooth-page") >= 0,
                          "navigation is emitted independently from toggle")
                    const slider = eventAt(sound, "volumeSlider")
                    slider.previewChanged(0.64)
                    check(test.dragging && test.preview === 64 && soundPage.volumePreview === 64,
                          "quick slider shares preview with sound page")
                    check(events.indexOf("volume:64") < 0, "preview does not commit")
                    slider.canceled()
                    check(!test.dragging && test.preview === 35, "cancel restores confirmed service state")
                    const expanded = eventAt(soundPage, "submenuVolumeSlider")
                    expanded.previewChanged(0.72)
                    check(test.preview === 72 && sound.volumePreview === 72, "expanded slider shares preview")
                    expanded.commitRequested(0.72)
                    check(!test.dragging && events.filter(x => x === "volume:72").length === 1,
                          "commit reaches the injected service once")
                    eventAt(mediaCard, "media-previous").clicked()
                    eventAt(mediaCard, "media-toggle").clicked()
                    eventAt(mediaCard, "media-next").clicked()
                    check(events.slice(-3).join(",") === "previous,play,next", "media actions use injected player service")
                    networkBackend.nearbyWifi = [{ssid: "Private", security: "wpa2", secured: true, active: false}]
                    test.step++
                    break
                case 1:
                    eventAt(wifiPage, "wifiRowMouse").clicked(null)
                    check(events.slice(-2).join(",") === "close,credentials", "credential route closes before delivery")
                    check(selectedNetwork.ssid === "Private" && selectedNetwork.secured,
                          "selected network survives delegate removal")
                    networkBackend.nearbyWifi = [{ssid: "Saved", savedProfileUuid: "profile-1", security: "wpa2", active: false}]
                    test.step++
                    break
                case 2:
                    eventAt(wifiPage, "wifiRowMouse").clicked(null)
                    check(events[events.length - 1] === "connect:Saved:profile-1", "saved network bypasses credential dialog")
                    center.toggle(anchorItem)
                    test.step++
                    break
                case 3:
                    if (center.revealProgress < 1) break
                    check(center.isOpen && center.visible, "production panel opens")
                    center.openSubmenu(test.pages[0])
                    test.step++
                    break
                case 4:
                    if (center.pageProgress < 1) break
                    check(center.displayedSubmenu === test.pages[test.navigation], "production submenu settles")
                    const page = eventAt(center.contentItem, "control-center-" + test.pages[test.navigation] + "page")
                    check(page.visible && page.width > 0 && page.height > 0, "extracted page has real geometry")
                    if (++test.navigation < test.pages.length) center.openSubmenu(test.pages[test.navigation])
                    else { center.openSessionPanel(); test.step++ }
                    break
                case 5:
                    if (center.pageProgress < 1) break
                    check(center.displayedSubmenu === "session", "session sheet remains a navigation page")
                    center.runSessionAction("poweroff")
                    test.step++
                    break
                case 6:
                    if (center.pageProgress < 1) break
                    check(center.pendingConfirmAction === "poweroff", "session action waits for confirmation")
                    let dialog = null
                    for (let i = 0; i < center.data.length; ++i) {
                        if (center.data[i].objectName === "control-center-session-confirmation")
                            dialog = center.data[i]
                    }
                    check(dialog !== null, "confirmation scope stays owned by the panel")
                    dialog.cancelRequested()
                    check(center.pendingConfirmAction === "" && center.isOpen, "cancel keeps panel open without executing action")
                    center.close()
                    center.toggle(anchorItem)
                    test.step++
                    break
                case 7:
                    if (center.revealProgress < 1) break
                    check(center.displayedSubmenu === "" && center.isOpen, "reopening clears prior page identity")
                    center.close()
                    center.dockHosted = true
                    center.dockEdge = "left"
                    center.toggle(anchorItem)
                    center.openSubmenu("sound")
                    test.step++
                    break
                case 8:
                    if (center.pageProgress < 1 || center.revealProgress < 1) break
                    check(center.displayedSubmenu === "sound" && center.dockFacingLayout,
                          "Dock-hosted panel retains submenu layout")
                    console.log("CONTROL_CENTER_MODULES_PASS " + test.checks + " checks")
                    Qt.quit()
                    break
                }
            } catch (error) {
                console.error("CONTROL_CENTER_MODULES_FAIL step=" + test.step + " " + error + "\n" + error.stack)
                Qt.quit()
            }
        }
    }
}
