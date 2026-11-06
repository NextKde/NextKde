import QtQuick
import QtTest
import "../.." as Settings
import "../../../../shared/qml/i18n"

TestCase {
    name: "SpatialServices"
    when: windowShown
    visible: true
    width: 760
    height: 640
    QtObject {
        id: bridge
        property int starts: 0
        property int stops: 0
        signal wallpaperSnapshotChanged(var state)
        function wallpaperSnapshot() {}
        function inspectSpatialService() {}
        function initializeSpatialService() { starts++ }
        function disableSpatialService() { stops++ }
    }
    QtObject {
        id: fakeStore
        property var music: ({available: true, installed: false, busy: false})
        property var apps: []
        property bool anyBusy: false
        property bool hasActiveMutation: false
        property int refreshes: 0
        property string lastId: ""
        property int checks: 0
        property int updates: 0
        property int installs: 0
        property int opens: 0
        property int removals: 0
        property int cancellations: 0
        property int confirmations: 0
        property string confirmedPlan: ""
        signal changed()
        function confirmPlan(id, planId) { confirmations++; lastId = id; confirmedPlan = planId }
        function refresh() { refreshes++ }
        function install(id) { installs++; lastId = id || "kmusic" }
        function open(id) { opens++; lastId = id || "kmusic" }
        function uninstall(id) { removals++; lastId = id || "kmusic" }
        function cancel(id) { cancellations++; lastId = id || "kmusic" }
        function checkUpdates(id) { checks++; lastId = id }
        function update(id) { updates++; lastId = id }
        function openRepository() {}
        function openLog() {}
    }
    Component {
        id: factory
        Settings.ServicesSettingsPage {
            width: 700
            height: implicitHeight
            selectedCategory: store ? 0 : 1
            colors: ({card: "#222222", primaryText: "#ffffff", secondaryText: "#aaaaaa", accent: Qt.rgba(10/255, 132/255, 1, 1)})
        }
    }
    function init() {
        bridge.starts = 0
        bridge.stops = 0
        I18n.language = "en"
        fakeStore.music = {available: true, installed: false, busy: false}
        fakeStore.installs = fakeStore.opens = fakeStore.removals = fakeStore.cancellations = 0
        fakeStore.confirmations = 0; fakeStore.confirmedPlan = ""
        fakeStore.apps = []; fakeStore.anyBusy = false; fakeStore.lastId = ""; fakeStore.checks = fakeStore.updates = 0
    }
    function snapshot(state) { bridge.wallpaperSnapshotChanged({spatialResources: state}) }

    function test_action_waits_for_backend() {
        const page = createTemporaryObject(factory, this, {bridge: bridge})
        verify(page)
        const action = findChild(page, "spatialServiceAction")
        verify(action)
        compare(action.enabled, false) // no snapshot yet
        snapshot({available: true, enabled: false, ready: false})
        compare(action.text, "Get")
        verify(action.enabled)
        verify(waitForRendering(page))
        mouseClick(action, action.width / 2, action.height / 2)
        compare(bridge.starts, 1)
        compare(action.text, "Get") // no optimistic completion
        snapshot({available: true, enabled: false, busy: true, progress: 0.5})
        compare(action.enabled, false)
        compare(findChild(page, "spatialServiceProgress").value, 0.5)
        verify(waitForRendering(page))
        mouseClick(action, action.width / 2, action.height / 2)
        compare(bridge.starts, 1)
        snapshot({available: true, enabled: true, ready: true})
        compare(action.text, "Disable")
        action.forceActiveFocus()
        keyClick(Qt.Key_Space)
        compare(bridge.stops, 1)
        snapshot({available: true, enabled: false, ready: true})
        compare(action.text, "Enable")
        verify(waitForRendering(page))
        mouseClick(action, action.width / 2, action.height / 2)
        compare(bridge.starts, 2)
    }
    function test_unavailable_and_retry() {
        const page = createTemporaryObject(factory, this, {bridge: bridge})
        const action = findChild(page, "spatialServiceAction")
        snapshot({available: false})
        compare(action.enabled, false)
        compare(action.text, "Unavailable")
        snapshot({available: true, checking: true})
        compare(action.enabled, false)
        snapshot({available: true, enabled: false, error: "Download failed"})
        compare(findChild(page, "spatialServiceError").text, "Download failed")
        verify(action.enabled)
        verify(waitForRendering(page))
        mouseClick(action, action.width / 2, action.height / 2)
        compare(bridge.starts, 1)
        snapshot({available: true, busy: true, progress: -1})
        verify(findChild(page, "spatialServiceProgress").indeterminate)
        compare(findChild(page, "spatialServiceError").visible, false)
    }
    function test_no_bridge() {
        const page = createTemporaryObject(factory, this)
        compare(findChild(page, "spatialServiceAction").enabled, false)
        compare(findChild(page, "spatialServiceAction").text, "Unavailable")
    }
    function test_appearance_data() {
        return [
            {tag: "light", language: "en", width: 700, colors: {card: "#ffffff", primaryText: "#1c1c1e", secondaryText: "#6d6d72", accent: Qt.rgba(0, 122/255, 1, 1)}},
            {tag: "dark", language: "zh-CN", width: 700, colors: {card: "#222222", primaryText: "#ffffff", secondaryText: "#aaaaaa", accent: Qt.rgba(10/255, 132/255, 1, 1)}},
            {tag: "narrow", language: "en", width: 420, colors: {card: "#ffffff", primaryText: "#1c1c1e", secondaryText: "#6d6d72", accent: Qt.rgba(0, 122/255, 1, 1)}}
        ]
    }
    function test_appearance(data) {
        I18n.language = data.language
        const page = createTemporaryObject(factory, this, {bridge: bridge, colors: data.colors, width: data.width})
        snapshot({available: true, enabled: false, ready: false})
        verify(waitForRendering(page))
        const action = findChild(page, "spatialServiceAction")
        const corner = action.mapToItem(page, action.width, action.height)
        verify(corner.x <= page.width)
        verify(corner.y <= page.height)
        grabImage(page).save("extensions-" + data.tag + ".png")
    }
    function appState(id, extra) {
        return Object.assign({id: id, name: id, description: "", available: true, statusKnown: true, managed: true, installed: true, busy: false, version: "1.0", latestVersion: "2.0", updateAvailable: true}, extra || {});
    }
    function test_multi_app_actions_and_busy() {
        fakeStore.apps = [appState("calendar", {installed: false}), appState("calculator"), appState("weather"), appState("listenfree")];
        const page = createTemporaryObject(factory, this, {store: fakeStore});
        tryVerify(function() { return !!findChild(page, "calendarAction") });
        findChild(page, "calendarAction").clicked();
        compare(fakeStore.lastId, "calendar"); compare(fakeStore.installs, 1);
        // Install first prepares a plan. Dismissing it must not confirm deployment.
        fakeStore.apps = [appState("calendar", {installed: false, flatpak: {plan: {planId: "first", operation: "install"}}}), appState("calculator"), appState("weather"), appState("listenfree")];
        fakeStore.changed();
        const installation = findChild(page, "flatpakPlanDialog");
        tryCompare(installation, "visible", true);
        compare(fakeStore.confirmations, 0);
        installation.reject();
        tryCompare(installation, "visible", false);
        tryCompare(page, "planId", "");
        compare(fakeStore.confirmations, 0);
        fakeStore.changed();
        compare(installation.visible, false); // a dismissed plan stays dismissed
        findChild(page, "calendarAction").clicked();
        fakeStore.apps = [appState("calendar", {installed: false, flatpak: {plan: {planId: "second", operation: "install"}}}), appState("calculator"), appState("weather"), appState("listenfree")];
        fakeStore.changed();
        tryCompare(installation, "visible", true);
        findChild(installation, "flatpakPlanConfirm").clicked();
        compare(fakeStore.lastId, "calendar"); compare(fakeStore.confirmations, 1);
        compare(fakeStore.confirmedPlan, "second");
        tryCompare(page, "planId", "");
        findChild(page, "weatherAction").clicked(); compare(fakeStore.lastId, "weather"); compare(fakeStore.opens, 1);
        findChild(page, "calculatorCheckUpdates").clicked(); compare(fakeStore.lastId, "calculator"); compare(fakeStore.checks, 1);
        findChild(page, "listenfreeUpdate").clicked(); compare(fakeStore.lastId, "listenfree"); compare(fakeStore.updates, 1);
        findChild(page, "weatherActionSecondary").clicked();
        const dialog = findChild(page, "appUninstallDialog"); verify(dialog.visible); compare(fakeStore.removals, 0);
        dialog.accept(); compare(fakeStore.lastId, "weather"); compare(fakeStore.removals, 1);
        fakeStore.anyBusy = true;
        compare(findChild(page, "calendarAction").enabled, false);
        compare(findChild(page, "calculatorCheckUpdates").enabled, false);
        fakeStore.apps = [appState("calendar", {busy: true, stage: "build"}), appState("calculator")];
        tryCompare(findChild(page, "calendarStatus"), "text", "Building from source…");
        findChild(page, "calendarActionSecondary").clicked(); compare(fakeStore.lastId, "calendar"); compare(fakeStore.cancellations, 1);
    }
    function test_multi_app_offline_and_external() {
        fakeStore.apps = [appState("weather", {code: "RATE_LIMITED"}), appState("calculator", {managed: false, code: "EXTERNALLY_MANAGED", message: "Executable already supplied by another installation"})];
        const page = createTemporaryObject(factory, this, {store: fakeStore, width: 420});
        tryVerify(function() { return !!findChild(page, "weatherError") });
        compare(findChild(page, "weatherError").text, "GitHub request limit reached. Try again later.");
        compare(findChild(page, "weatherAction").text, "Open"); verify(findChild(page, "weatherAction").enabled);
        compare(findChild(page, "calculatorError").visible, false);
        compare(findChild(page, "calculatorActionSecondary").visible, false);
        compare(findChild(page, "calculatorUpdate").visible, false);
        verify(findChild(page, "calculatorStatus").text.indexOf("Installed outside Settings") === 0);
        compare(findChild(page, "weatherVersion").text, "Installed: 1.0 · Latest: 2.0");
    }

    function planState(planId, busy) {
        return appState("calculator", {name: "Calculator", installed: false, busy: !!busy,
            flatpak: {known: true, busy: !!busy, plan: {planId: planId, operation: "install", version: "0.2.2",
                operationSet: [{role: "application", downloadBytes: 1024}, {role: "runtime", downloadBytes: 2048}]}}});
    }
    function test_cached_plan_does_not_open_on_navigation_or_refresh() {
        fakeStore.apps = [planState("cached")];
        let page = factory.createObject(this, {store: fakeStore});
        verify(page);
        fakeStore.changed();
        const dialog = findChild(page, "flatpakPlanDialog");
        compare(dialog.visible, false);
        page.destroy();
        wait(0);
        page = createTemporaryObject(factory, this, {store: fakeStore});
        fakeStore.changed();
        compare(findChild(page, "flatpakPlanDialog").visible, false);
    }
    function test_escape_then_reenter_requires_another_install_click() {
        fakeStore.apps = [planState("")];
        let page = factory.createObject(this, {store: fakeStore});
        verify(page);
        findChild(page, "calculatorAction").clicked();
        fakeStore.apps = [planState("first")];
        fakeStore.changed();
        let dialog = findChild(page, "flatpakPlanDialog");
        tryCompare(dialog, "visible", true);
        verify(dialog.height < 440, "confirmation follows content height");
        grabImage(dialog.contentItem.parent).save("flatpak-plan-confirmation.png");
        dialog.forceActiveFocus();
        keyClick(Qt.Key_Escape);
        tryCompare(dialog, "visible", false);
        compare(fakeStore.confirmations, 0);
        page.destroy();
        wait(0);
        page = createTemporaryObject(factory, this, {store: fakeStore});
        fakeStore.changed();
        dialog = findChild(page, "flatpakPlanDialog");
        compare(dialog.visible, false);
        findChild(page, "calculatorAction").clicked();
        fakeStore.changed();
        compare(dialog.visible, false); // cached first plan cannot satisfy a new click
        fakeStore.apps = [planState("second")];
        fakeStore.changed();
        tryCompare(dialog, "visible", true);
        findChild(dialog, "flatpakPlanConfirm").clicked();
        compare(fakeStore.confirmations, 1);
        compare(fakeStore.confirmedPlan, "second");
    }
    function test_leaving_during_preparation_does_not_open_on_return() {
        fakeStore.apps = [planState("")];
        let page = factory.createObject(this, {store: fakeStore});
        findChild(page, "calculatorAction").clicked();
        fakeStore.apps = [planState("", true)];
        fakeStore.changed();
        page.destroy();
        wait(0);
        page = createTemporaryObject(factory, this, {store: fakeStore});
        fakeStore.apps = [planState("late")];
        fakeStore.changed();
        compare(findChild(page, "flatpakPlanDialog").visible, false);
    }
    function test_missing_flatpak_shows_actionable_error_and_retry() {
        I18n.language = "zh-CN";
        fakeStore.apps = [appState("calculator", {installed: false, available: false, statusKnown: false,
            flatpak: {known: false, error: "missing", errorCode: "FLATPAK_NOT_INSTALLED"}})];
        const page = createTemporaryObject(factory, this, {store: fakeStore});
        verify(findChild(page, "calculatorStatus").text.indexOf("未安装 Flatpak") === 0);
        verify(!findChild(page, "calculatorAction").enabled);
        const before = fakeStore.refreshes;
        findChild(page, "calculatorRecheckEnvironment").clicked();
        compare(fakeStore.refreshes, before + 1);
    }
}
