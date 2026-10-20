import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.platform
import qs.desktop.modules.bar
import qs.desktop.modules.dock

ShellRoot {
    id: test
    property int stage: 0
    property string saved: ""
    Component.onCompleted: {
        test.check(IconAppearanceService.trayFollowsBarColor, "tray defaults to a monochrome template")
        IconAppearanceService.trayFollowsBarColor = false
        AppearanceConfigService.themeMode = "dark"
        AppearanceConfigService.glassFollowsAppearanceMode = true
        AppearanceConfigService.barMacStyle = false
        IconAppearanceService.opacity = 0.2
    }
    property var settingsSection: null
    property var settingsSwitch: null
    QtObject {
        id: palette
        property bool dark: false
        property color primaryText: "#111111"
        property color secondaryText: "#666666"
        property color card: "#ffffff"
        property color separator: "#dddddd"
        property color accent: "#0066cc"
        property color divider: "#dddddd"
        property color iconForeground: "#ffffff"
        property color iconMuted: "#666666"
        property color selectedForeground: "#ffffff"
        function role(name, fallback) { return fallback }
    }
    QtObject {
        id: bridge
        signal appearanceSnapshotChanged(var state)
        function appearanceSnapshot() {
            appearanceSnapshotChanged({trayFollowsBarColor: IconAppearanceService.trayFollowsBarColor})
        }
        function updateTrayFollowsBarColor(enabled) {
            test.check(IconAppearanceService.updateTrayFollowsBarColor(enabled),
                "preference update changes state: " + enabled)
            appearanceSnapshot()
        }
    }
    function check(ok, message) { if (!ok) throw new Error(message) }
    function findSwitch(item) {
        if (item.objectName === "tray-follows-bar-color-switch") return item
        for (const child of item.children || []) {
            const found = findSwitch(child)
            if (found) return found
        }
        return null
    }
    function capture(name) {
        scene.grabToImage(result => {
            check(result.saveToFile(Quickshell.env("CAPTURE_DIR") + "/" + name + ".png"), "capture " + name)
            if (name === "white" || name === "black") {
                applicationGallery.grabToImage(gallery => {
                    check(gallery.saveToFile(Quickshell.env("CAPTURE_DIR") + "/applications-" + name + ".png"), "application capture")
                    test.stage++
                })
            } else test.stage++
        })
    }
    FloatingWindow {
        visible: true
        implicitWidth: 320
        implicitHeight: 80
        Rectangle {
            id: scene
            anchors.fill: parent
            color: "#204060"
            AppIcon {
                id: trayIcon
                x: 0; y: 4; width: 40; height: 24
                source: Quickshell.env("TRAY_TEST_ICON")
                recolorEnabled: IconAppearanceService.trayFollowsBarColor
                recolorColor: ThemeService.barInk
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
                y: 40; width: 320; height: 32
                color: ThemeService.isDark ? "#163671" : "#f0f0f0"
                TrayIcon {
                    id: codexTemplate
                    x: 4; y: 4; width: 24; height: 24
                    applicationId: "com.openai.codex"
                    applicationName: "Codex"
                    originalSource: Quickshell.env("TRAY_TEST_ICON")
                }
                TrayIcon {
                    id: qqTemplate
                    x: 36; y: 4; width: 24; height: 24
                    applicationId: "chrome_status_icon_1"
                    applicationName: "QQ"
                    originalSource: Quickshell.env("TRAY_TEST_ICON")
                }
                TrayIcon {
                    id: clashTemplate
                    x: 68; y: 4; width: 24; height: 24
                    applicationId: "tray-icon tray app clash-verge-rev-tray"
                    applicationName: "clash-verge"
                    originalSource: Quickshell.env("TRAY_TEST_ICON")
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
            try {
                switch (test.stage) {
                case 0:
                    test.check(IconAppearanceService.ready, "config loads")
                    test.check(trayIcon.imageStatus === Image.Ready, "test icon loads")
                    test.check(!IconAppearanceService.trayFollowsBarColor, "original mode preserves artwork")
                    test.capture("original")
                    break
                case 1:
                    test.check(!IconAppearanceService.trayFollowsBarColor, "original remains selected before toggle")
                    IconAppearanceService.mode = "grayscale"
                    const component = Qt.createComponent(Quickshell.env("TRAY_SETTINGS_SECTION"))
                    test.check(component.status === Component.Ready, component.errorString())
                    test.settingsSection = component.createObject(scene,
                        {colors: palette, bridge: bridge, width: 620, visible: false})
                    test.check(test.settingsSection !== null, component.errorString())
                    test.settingsSwitch = test.findSwitch(test.settingsSection)
                    test.check(test.settingsSwitch && !test.settingsSwitch.checked, "settings defaults off")
                    test.settingsSwitch.toggle()
                    test.check(test.settingsSwitch.checked, "settings confirms enabled toggle")
                    test.stage++
                    break
                case 2:
                    test.check(monochromeBattery.fillColor === ThemeService.barInk
                        && monochromeBattery.boltColor === ThemeService.barInk
                        && monochromeBattery.opacity === 1, "battery shares full appearance ink")
                    for (const icon of [codexTemplate, qqTemplate, clashTemplate]) {
                        test.check(icon.source !== icon.originalSource && icon.imageStatus === Image.Ready,
                            "real application template loads: " + icon.applicationName)
                    }
                    if (JsonConfigStore.texts[IconAppearanceService.configPath] === undefined) {
                        test.check(IconAppearanceService.saveTimer.running, "save is scheduled")
                        break
                    }
                    test.saved = JsonConfigStore.texts[IconAppearanceService.configPath]
                    test.check(JSON.parse(test.saved).trayFollowsBarColor === true, "toggle is saved")
                    test.capture("white")
                    break
                case 3:
                    AppearanceConfigService.themeMode = "light"
                    test.stage++
                    break
                case 4: test.capture("black"); break
                case 5:
                    IconAppearanceService.applyText('{"mode":"tint","tintColor":"#ff0000"}')
                    test.check(IconAppearanceService.trayFollowsBarColor, "legacy config defaults to uniform templates")
                    IconAppearanceService.applyText('{"mode":"tint","tintColor":"#ff0000","trayFollowsBarColor":false}')
                    test.check(codexTemplate.source === codexTemplate.originalSource, "original mode restores application artwork")
                    test.stage++
                    break
                case 6: test.capture("restored"); break
                case 7:
                    IconAppearanceService.applyText(test.saved)
                    test.check(IconAppearanceService.trayFollowsBarColor, "saved toggle reloads")
                    AppearanceConfigService.themeMode = "dark"
                    test.stage++
                    break
                case 8: test.capture("reloaded"); break
                case 9:
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
                    test.settingsSwitch.toggle()
                    test.check(!test.settingsSwitch.checked, "settings confirms disabled toggle")
                    test.stage++
                    break
                case 14:
                    test.check(JSON.parse(JsonConfigStore.texts[IconAppearanceService.configPath]).trayFollowsBarColor === false, "off is saved")
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
