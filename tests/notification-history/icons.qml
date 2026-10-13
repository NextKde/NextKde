import QtQuick
import Quickshell
import "."
Scope {
    FloatingWindow {
        visible: true
        implicitWidth: 620
        implicitHeight: 490
        color: "#333c42"
        Item {
            id: gallery
            anchors.fill: parent
            Row {
                spacing: 0
                Repeater {
                    model: [true, false]
                    delegate: Rectangle {
                        required property bool modelData
                        width: 310; height: 490
                        color: modelData ? "#26352f" : "#e5e1d6"
                        Column {
                            x: 16; y: 16
                            spacing: 18
                            Text { text: modelData ? "Dark / 2 notifications" : "Light / 3 notifications"; color: modelData ? "white" : "#222222" }
                            NotificationHistoryGroup {
                                width: 278
                                sourceKey: "desktop:org.test.icon"
                                appName: "Desktop application icon"
                                appIcon: ""
                                desktopEntry: "org.test.icon"
                                expanded: false
                                itemCount: modelData ? 2 : 3
                                ink: modelData ? "white" : "#222222"
                                dark: modelData
                                itemsJson: JSON.stringify(Array.from({length: itemCount}, (_, index) => ({historyKey: index + 1, summary: "Latest notification", body: "Clear stacked edges", timestamp: 0})))
                            }
                            Row {
                                spacing: 18
                                NotificationSourceIcon { id: themeIcon; width: 28; height: 28; appIcon: "folder"; ink: modelData ? "white" : "#222222"; objectName: "theme" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: Quickshell.env("KOS_ICON_TEST_PATH"); ink: modelData ? "white" : "#222222"; objectName: "path" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "file://" + Quickshell.env("KOS_ICON_TEST_PATH"); ink: modelData ? "white" : "#222222"; objectName: "url" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: ""; desktopEntry: "org.test.icon"; ink: modelData ? "white" : "#222222"; objectName: "desktop" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: ""; ink: modelData ? "white" : "#222222"; objectName: "fallback" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "file:///missing-notification-test-icon.svg"; desktopEntry: "org.test.icon"; ink: modelData ? "white" : "#222222"; objectName: "invalid-primary" }
                            }
                            Text { width: 278; wrapMode: Text.Wrap; text: "Theme / path / URL / desktop / fallback / invalid primary → desktop"; color: modelData ? "white" : "#222222"; font.pixelSize: 12 }
                        }
                    }
                }
            }
        }
    }
    function check(item) {
        if (item.objectName === "theme" || item.objectName === "path" || item.objectName === "url" || item.objectName === "desktop" || item.objectName === "invalid-primary") {
            if (item.usesFallback || item.candidates.length === 0) throw new Error("Icon source failed: " + item.objectName + " " + JSON.stringify(item.candidates))
        }
        if (item.objectName === "fallback" && !item.usesFallback) throw new Error("Fallback missing")
        for (const child of item.children || []) check(child)
    }
    Timer {
        running: true; interval: 700
        onTriggered: {
            check(gallery)
            gallery.grabToImage(function(result) {
                if (!result.saveToFile(Quickshell.env("KOS_ICON_QA_IMAGE"))) throw new Error("QA save failed")
                console.log("NOTIFICATION_ICONS_TEST_PASS")
                Qt.quit()
            })
        }
    }
}
