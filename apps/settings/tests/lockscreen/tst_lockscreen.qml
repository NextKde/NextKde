import QtQuick
import QtTest

Item {
    property var lockScreenSettings: backend
    QtObject {
        id: backend
        property var state: ({available: true, installed: true, active: true, canChangeTheme: true,
            wallpaper: "", showMediaControls: true, kosShowNotifications: false, error: ""})
        property var calls: []
        signal thumbnailReady()
        function refresh() {}
        function wallpaperImages() { return [] }
        function wallpaperThumbnail(path, width, height) { return "" }
        function setWallpaper(path) { calls = calls.concat(["wallpaper:" + path]); return true }
        function lockNow() { calls = calls.concat(["lock"]); }
        function setTheme(value) {
            calls = calls.concat(["theme:" + value]);
            state = Object.assign({}, state, {active: value === "kos"});
            return true;
        }
        function setShowMediaControls(value) {
            calls = calls.concat(["media:" + value]);
            state = Object.assign({}, state, {showMediaControls: value});
            return true;
        }
        function setShowNotifications(value) {
            calls = calls.concat(["notifications:" + value]);
            state = Object.assign({}, state, {kosShowNotifications: value});
            return true;
        }
    }
    TestCase {
        name: "LockScreenSettingsInteractions"
        when: windowShown
        property var app: null
        function init() {
            failOnWarning(/ReferenceError|TypeError|Unable to assign|Binding loop|Cannot assign/);
            backend.calls = [];
            backend.state = {available: true, installed: true, active: true, canChangeTheme: true,
                wallpaper: "", showMediaControls: true, kosShowNotifications: false, error: ""};
            const component = Qt.createComponent("../../main.qml");
            compare(component.status, Component.Ready, component.errorString());
            app = component.createObject(null, {currentPage: 16});
            verify(app !== null, component.errorString());
            tryVerify(() => findChild(app.contentItem, "lockScreenSettingsPage") !== null);
            verify(waitForRendering(app.contentItem));
        }
        function cleanup() { if (app) app.destroy(); app = null; }
        function control(name) {
            const item = findChild(app.contentItem, name);
            verify(item !== null, name);
            return item;
        }
        function click(name) {
            const item = control(name);
            const scroll = control("settings-page-scroll");
            scroll.cancelFlick();
            scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height,
                item.mapToItem(scroll.contentItem, 0, 0).y - scroll.height / 2));
            verify(waitForRendering(app.contentItem));
            mouseClick(item, item.width / 2, item.height / 2);
        }
        function test_openAndPreviewDoNotLock() {
            compare(app.currentPage, 16);
            verify(control("lockScreenStaticPreview").visible);
            compare(backend.calls.length, 0);
            mouseClick(control("lockScreenStaticPreview"), 40, 40);
            compare(backend.calls.length, 0);
            verify(findChild(app.contentItem, "lockScreenNotificationBodySwitch") === null);
            app.currentPage = 13;
            tryVerify(() => findChild(app.contentItem, "lockScreenSettingsPage") === null);
            app.currentPage = 16;
            tryVerify(() => findChild(app.contentItem, "lockScreenSettingsPage") !== null);
            compare(backend.calls.length, 0);
        }
        function test_preferencesAndExplicitLock() {
            compare(control("lockScreenMediaSwitch").checked, true);
            compare(control("lockScreenNotificationsSwitch").checked, false);
            click("lockScreenMediaSwitch");
            click("lockScreenNotificationsSwitch");
            compare(backend.calls.join(","), "media:false,notifications:true");
            click("lockScreenLockNow");
            compare(backend.calls.join(","), "media:false,notifications:true,lock");
        }
        function test_themeSelectionAndGuards() {
            const theme = control("lockScreenThemeSelect");
            compare(theme.currentIndex, 1);
            theme.activated(0);
            compare(backend.calls[0], "theme:system");
            compare(theme.currentIndex, 0);
            compare(control("lockScreenNotificationsSwitch").enabled, false);
            backend.state = Object.assign({}, backend.state, {canChangeTheme: false, error: "Other desktop"});
            compare(theme.enabled, false);
            compare(control("lockScreenError").text, "Other desktop");
        }
    }
}
