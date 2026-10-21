import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.bar
import qs.desktop.modules.dock
import qs.desktop.modules.platform

ShellRoot {
    id: test
    property int stage: 0
    property string saved: ""
    property bool capturePending: false
    QtObject {
        id: mockTrayItem
        property string icon: Quickshell.env("TRAY_TEST_ICON")
    }
    Component.onCompleted: {
        test.check(!IconAppearanceService.monochrome, "tray defaults to the dock's color mode")
        IconAppearanceService.mode = "color"
        AppearanceConfigService.themeMode = "dark"
        AppearanceConfigService.glassFollowsAppearanceMode = true
        AppearanceConfigService.barMacStyle = false
        IconAppearanceService.opacity = 1.0
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function capture(name) {
        if (capturePending) return
        capturePending = true
        scene.grabToImage(result => {
            check(result.saveToFile(Quickshell.env("CAPTURE_DIR") + "/" + name + ".png"), "capture " + name)
            if (name === "white" || name === "black") {
                applicationGallery.grabToImage(gallery => {
                    check(gallery.saveToFile(Quickshell.env("CAPTURE_DIR") + "/applications-" + name + ".png"), "application capture")
                    test.capturePending = false
                    test.stage++
                })
            } else {
                test.capturePending = false
                test.stage++
            }
        })
    }
    FloatingWindow {
        visible: true
        implicitWidth: 320
        implicitHeight: 112
        Rectangle {
            id: scene
            anchors.fill: parent
            color: "#204060"
            AppIcon {
                id: trayIcon
                x: 0; y: 4; width: 40; height: 24
                source: Quickshell.env("TRAY_TEST_ICON")
                opacityMultiplier: IconAppearanceService.mode === "color"
                    ? 1.0 : IconAppearanceService.opacity
                saturation: IconAppearanceService.saturation
                tintEnabled: IconAppearanceService.tintEnabled
                tintColor: IconAppearanceService.tintColor
            }
            // A normal consumer of the shared shader must retain its grayscale.
            AppIcon {
                x: 40; y: 4; width: 40; height: 24
                source: Quickshell.env("TRAY_TEST_ICON")
                saturation: 0
            }
            Text {
                x: 104; y: 4; width: 42; height: 24
                text: "101°"
                font.pixelSize: 16
                color: ThemeService.barInk
            }
            SettingsButton { x: 160; y: 4; iconSize: 24 }
            ControlCenterToggle { x: 200; y: 4; iconSize: 24 }
            NetworkStatus { x: 240; y: 4; iconSize: 24 }
            NotificationHistoryToggle { x: 280; y: 4; iconSize: 24 }
            Rectangle {
                id: applicationGallery
                y: 40; width: 320; height: 64
                color: ThemeService.isDark ? "#163671" : "#f0f0f0"
                TrayIcon {
                    id: trayEntry
                    x: 4; y: 4; width: 24; height: 24
                    entry: mockTrayItem
                }
                Text {
                    x: 104; y: 4; width: 42; height: 24
                    text: "101°"; font.pixelSize: 16
                    color: ThemeService.barInk
                }
                SettingsButton { x: 160; y: 4; iconSize: 24 }
                ControlCenterToggle { x: 200; y: 4; iconSize: 24 }
                NetworkStatus { x: 240; y: 4; iconSize: 24 }
                Battery { id: monochromeBattery; x: 280; y: 4; iconSize: 24 }
            }
        }
    }
    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            if (test.capturePending) return
            try {
                switch (test.stage) {
                case 0:
                    test.check(IconAppearanceService.ready, "config loads")
                    test.check(trayIcon.imageStatus === Image.Ready, "test icon loads")
                    test.check(!IconAppearanceService.monochrome, "color mode preserves artwork")
                    test.capture("original")
                    break
                case 1:
                    IconAppearanceService.mode = "grayscale"
                    test.stage++
                    break
                case 2:
                    if (IconAppearanceService.saveTimer.running) break
                    test.saved = JsonConfigStore.texts[IconAppearanceService.configPath]
                    test.check(JSON.parse(test.saved).mode === "grayscale", "mode is saved")
                    test.check(trayEntry.source === trayEntry.originalSource,
                        "tray keeps the application artwork")
                    test.capture("white")
                    break
                case 3:
                    AppearanceConfigService.themeMode = "light"
                    test.stage++
                    break
                case 4: test.capture("black"); break
                case 5:
                    IconAppearanceService.applyText('{"mode":"color","tintColor":"#ff0000"}')
                    test.check(!IconAppearanceService.monochrome, "color mode restores original artwork")
                    test.stage++
                    break
                case 6: test.capture("restored"); break
                case 7:
                    IconAppearanceService.applyText(test.saved)
                    test.check(IconAppearanceService.mode === "grayscale", "saved mode reloads")
                    AppearanceConfigService.themeMode = "dark"
                    test.stage++
                    break
                case 8: test.capture("reloaded"); break
                case 9:
                    IconAppearanceService.updateTintColor("#ff0000")
                    IconAppearanceService.mode = "tint"
                    test.stage++
                    break
                case 10: test.capture("tinted"); break
                case 11:
                    IconAppearanceService.mode = "color"
                    test.stage++
                    break
                case 12: test.capture("color"); break
                case 13:
                    test.check(monochromeBattery.fillColor === ThemeService.barInk
                        && monochromeBattery.boltColor === ThemeService.barInk
                        && monochromeBattery.opacity === 1, "battery shares full appearance ink")
                    test.stage++
                    break
                case 14:
                    if (IconAppearanceService.saveTimer.running) break
                    test.check(JSON.parse(JsonConfigStore.texts[IconAppearanceService.configPath]).mode === "color", "color mode is saved")
                    console.log("TRAY_COLOR_PASS")
                    Qt.quit()
                }
            } catch (error) {
                console.error("TRAY_COLOR_FAIL stage=" + test.stage, error,
                    "saved paths=" + Object.keys(JsonConfigStore.texts).join(","))
                Qt.exit(1)
            }
        }
    }
}
