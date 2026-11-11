import QtQuick
import Quickshell
import "shared/Icons" as Symbols
import qs.desktop.modules.common
import qs.desktop.modules.bar

Scope {
    FloatingWindow {
        visible: true
        implicitWidth: 720; implicitHeight: 230
        color: "#f5f5f7"
        Rectangle {
            color: "#f5f5f7"
            id: scene
            anchors.fill: parent
            Text { x: 24; y: 16; text: "NextKde · unified system icons"; color: "#222"; font.pixelSize: 20 }
            Row {
                x: 24; y: 60; spacing: 16
                Repeater {
                    model: ["bluetooth.control", "system.cpu", "system.memory", "system.disk", "system.cpuTemperature", "bar.controlCenter", "controlCenter.keepAwake", "controlCenter.screenshot", "controlCenter.appearance", "bar.notifications", "controlCenter.stageMode", "session.lock"]
                    BundledIcon { required property string modelData; name: modelData; size: 32; color: "#29292b" }
                }
            }
            Row {
                x: 24; y: 120; spacing: 20
                WifiSignalIcon { id: signal; size: 32; wifiEnabled: true; connected: true; signalStrength: 20; glyphColor: "#29292b" }
                WifiSignalIcon { size: 32; connected: true; signalStrength: 45; glyphColor: "#29292b" }
                WifiSignalIcon { size: 32; connected: true; signalStrength: 85; glyphColor: "#29292b" }
                ShellVolumeIcon { size: 32; level: 0.5; color: "#29292b" }
                ShellVolumeIcon { size: 32; muted: true; color: "#29292b" }
                ShellBatteryIcon { size: 32; level: 0.15; color: "#29292b"; fillColor: "#ff453a" }
                ShellBatteryIcon { size: 32; level: 0.63; color: "#29292b"; fillColor: "#30b05a" }
                ShellBatteryIcon { size: 32; charging: true; color: "#29292b" }
                AppIcon { id: fontAdapter; width: 32; height: 32; source: BundledIcons.source("desktop.file.folder"); recolorEnabled: true; recolorColor: "#29292b" }
                BundledIcon { id: brand; size: 32; name: "application.calendar"; colorized: false }
                BundledIcon { id: blank; size: 32; name: "desktop.menu.rename" }
            }
            Text { x: 24; y: 184; text: "Same font · continuous battery fill · native artwork preserved"; font.pixelSize: 13; color: "#666" }
        }
    }
    Timer {
        running: true; interval: 600
        onTriggered: {
            if (!Symbols.IconRegistry.ready || !fontAdapter.fontGlyph || fontAdapter.imageStatus !== Image.Ready)
                throw new Error("Font adapter did not load")
            for (const role of Object.keys(BundledIcons.roles)) {
                const name = BundledIcons.roles[role]
                if (name && !BundledIcons.has(role)) throw new Error("Unresolved icon role: " + role)
            }
            if (blank.fontGlyph || blank.source !== "" || BundledIcons.has(blank.name))
                throw new Error("Intentionally blank menu icon rendered artwork")
            if (BundledIcons.resolveName("controlCenter.nightLight") === BundledIcons.resolveName("controlCenter.doNotDisturb"))
                throw new Error("Night Light and Do Not Disturb must stay distinguishable")
            if (BundledIcons.resolveName("bar.collection.expand") !== "chevron_left_2"
                    || BundledIcons.resolveName("bar.collection.collapse") !== "chevron_right_2")
                throw new Error("Tray collection directions changed")
            if (brand.fontGlyph || !brand.source.startsWith("data:image/svg")) throw new Error("Branded artwork regressed")
            if (signal.signalLevel !== 1) throw new Error("Weak Wi-Fi state lost")
            signal.signalStrength = 80
            if (signal.signalLevel !== 3) throw new Error("Strong Wi-Fi state lost")
            signal.signalStrength = 20
            if (BundledIcons.has("unknown-font-glyph")) throw new Error("Unknown glyph accepted")
            scene.grabToImage(function(result) {
                if (!result.saveToFile(Quickshell.env("KOS_ICON_CAPTURE"))) throw new Error("Capture failed")
                console.log("FONT_ICONS_PASS")
                Qt.quit()
            })
        }
    }
}
