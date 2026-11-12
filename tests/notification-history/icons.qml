import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.notifications
import "."
Scope {
    id: test
    property int stage: 0
    property int themeReadyCount: 0
    property int previousReadyCount: 0
    property string previousSource: ""
    property int previousRevision: 0
    readonly property string customPath: Quickshell.env("KOS_ICON_TEST_PATH")
    readonly property string contentUrl: "data:image/svg+xml;utf8," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="#ffaa00"/></svg>')

    FloatingWindow {
        visible: true
        implicitWidth: 620
        implicitHeight: 490
        color: "#333c42"
        Item {
            id: gallery
            anchors.fill: parent
            Row {
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
                                appIcon: test.customPath
                                desktopEntry: "org.test.icon"
                                expanded: false
                                itemCount: modelData ? 2 : 3
                                ink: modelData ? "white" : "#222222"
                                dark: modelData
                                itemsJson: JSON.stringify(Array.from({length: itemCount}, (_, index) => ({historyKey: index + 1, summary: "Latest notification", body: "Clear stacked edges", timestamp: 0})))
                            }
                            Row {
                                spacing: 18
                                NotificationSourceIcon {
                                    width: 28; height: 28; appIcon: "nextkde-test-themed"; objectName: "theme"
                                    onImageStatusChanged: { if (imageStatus === Image.Ready) test.themeReadyCount++ }
                                }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: test.customPath; objectName: "path" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "file://" + test.customPath; objectName: "url" }
                                NotificationSourceIcon { width: 28; height: 28; desktopEntry: "org.test.icon.desktop"; objectName: "desktop" }
                                NotificationSourceIcon { width: 28; height: 28; objectName: "fallback"; ink: modelData ? "white" : "#222222" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "file:///missing-notification-test-icon.svg"; desktopEntry: "org.test.icon"; objectName: "invalid-primary" }
                            }
                            Row {
                                spacing: 18
                                NotificationSourceIcon { width: 28; height: 28; appIcon: test.customPath; desktopEntry: "org.test.icon"; objectName: "desktop-priority" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: Quickshell.env("KOS_ICON_THEMED_PATH"); objectName: "themed-path" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "file://" + Quickshell.env("KOS_ICON_THEMED_PATH"); objectName: "themed-url" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "kos-calendar"; objectName: "themed-brand" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: test.customPath; desktopEntry: "org.test.broken"; objectName: "broken-theme" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: "file:///missing-notification-test-icon.svg"; objectName: "broken-all"; ink: modelData ? "white" : "#222222" }
                            }
                            Row {
                                spacing: 18
                                // The production popup uses this same component; content
                                // images must win even when the source has a themed icon.
                                NotificationIcon { width: 28; height: 28; image: test.contentUrl; appIcon: test.customPath; desktopEntry: "org.test.icon"; objectName: "content" }
                                NotificationIcon { width: 28; height: 28; image: "file:///missing-notification-test-image.png"; desktopEntry: "org.test.icon"; objectName: "broken-content" }
                                NotificationIcon { width: 28; height: 28; image: Quickshell.env("KOS_ICON_THEMED_PATH"); desktopEntry: "org.test.icon"; objectName: "content-path" }
                                NotificationSourceIcon { width: 28; height: 28; desktopEntry: "org.test.custom"; objectName: "custom-desktop" }
                                NotificationSourceIcon { width: 28; height: 28; desktopEntry: "org.test.path"; objectName: "themed-desktop-path" }
                                NotificationSourceIcon { width: 28; height: 28; appIcon: test.contentUrl; objectName: "custom-data" }
                            }
                            Text { width: 278; wrapMode: Text.Wrap; text: "Theme / custom / desktop priority / decode fallback / content image / hot reload"; color: modelData ? "white" : "#222222"; font.pixelSize: 12 }
                        }
                    }
                }
            }
        }
    }
    function assert(value, message) { if (!value) throw new Error(message) }
    function themed(name) {
        const source = SystemIconResolver.sourceFromCandidates([name], name)
        assert(source.length > 0, "Fixture theme icon unavailable: " + name)
        return source
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) { const result = find(child, name); if (result) return result }
        return null
    }
    function check(item) {
        const name = item.objectName
        if (item.candidates !== undefined) {
            if (name === "fallback" || name === "broken-all") {
                assert(item.usesFallback, "Fallback missing: " + name)
            } else {
                assert(!item.usesFallback && item.imageStatus === Image.Ready, "Icon did not decode: " + name + " " + JSON.stringify(item.candidates))
                if (["theme", "desktop", "invalid-primary", "desktop-priority", "themed-path", "themed-url", "broken-content", "themed-desktop-path"].includes(name))
                    assert(item.source === themed("nextkde-test-themed"), "Expected theme source: " + name + " " + item.source)
                if (name === "themed-brand") assert(item.source === themed("kos-calendar"), "Bundled brand masked theme")
                if (name === "path" || name === "broken-theme" || name === "custom-desktop")
                    assert(item.source === AppPresentationService.iconSource(test.customPath), "Custom fallback lost: " + name)
                if (name === "url") assert(item.source === AppPresentationService.iconSource("file://" + test.customPath), "File URL fallback lost")
                if (name === "content" || name === "custom-data") assert(item.source === AppPresentationService.iconSource(test.contentUrl), "Content image replaced by app identity")
                if (name === "content-path") assert(item.source === "file://" + Quickshell.env("KOS_ICON_THEMED_PATH"), "Content basename must not be themed")
                // Some providers reject corrupt theme files during lookup;
                // the explicit content URL always reaches image decoding.
                if (name === "broken-content") assert(item.candidateIndex > 0, "Decode error did not advance candidates")
            }
        }
        for (const child of item.children || []) check(child)
    }
    Timer {
        running: true; repeat: true; interval: 850
        onTriggered: {
            check(gallery)
            const icon = test.find(gallery, "theme")
            if (test.stage === 0) {
                // Exercise the production config parser/debounce/revision path,
                // not an unrelated app descriptor override. This does not claim
                // to apply a real KDE theme (that needs a graphical VM session).
                IconThemeReloadService.applyConfig("[Icons]\nTheme=nextkde-fixture-a\n")
                test.previousRevision = IconThemeReloadService.revision
                test.previousSource = icon.source
                test.previousReadyCount = test.themeReadyCount
                IconThemeReloadService.applyConfig("[Icons]\nTheme=nextkde-fixture-b\n")
            } else if (test.stage === 1 || test.stage === 2) {
                assert(IconThemeReloadService.revision === test.previousRevision + 1, "Theme revision missing")
                assert(!IconThemeReloadService.pixmapCacheAllowed, "Old-theme pixmap cache remains enabled")
                assert(icon.source === test.previousSource, "Stable-URL fixture changed its URL")
                assert(test.themeReadyCount > test.previousReadyCount, "Stable URL did not reload artwork")
                if (test.stage === 1) {
                    // On the second switch cache is already false; a cache flag
                    // change alone cannot pass this regression.
                    test.previousRevision = IconThemeReloadService.revision
                    test.previousReadyCount = test.themeReadyCount
                    IconThemeReloadService.applyConfig("[Icons]\nTheme=nextkde-fixture-a\n")
                } else {
                    running = false
                    gallery.grabToImage(function(result) {
                        assert(result.saveToFile(Quickshell.env("KOS_ICON_QA_IMAGE")), "QA save failed")
                        console.log("NOTIFICATION_ICONS_TEST_PASS")
                        Qt.quit()
                    })
                }
            }
            test.stage++
        }
    }
}
