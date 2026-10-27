import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

if (!process.argv.includes("--session")) {
    const result = spawnSync("dbus-run-session", [process.execPath, fileURLToPath(import.meta.url), "--session", process.argv[2] || "quickshell"], {encoding: "utf8", timeout: 20000});
    assert.equal(result.status, 0, (result.stdout || "") + (result.stderr || ""));
    console.log(result.stdout.trim());
} else {
    const directory = mkdtempSync(join(tmpdir(), "nextkde-notification-dbus-"));
    let shell;
    try {
        copyFileSync(new URL("dbus.qml", import.meta.url), join(directory, "shell.qml"));
        // Load the production entry point unchanged; each QML file resolves its
        // own imports, so fixture imports cannot hide missing production types.
        const notifications = join(directory, "desktop/modules/notifications");
        const common = join(directory, "desktop/modules/common");
        const bar = join(directory, "desktop/modules/bar");
        const dock = join(directory, "desktop/modules/dock");
        const platform = join(directory, "desktop/modules/platform");
        for (const path of [notifications, common, bar, dock, platform]) mkdirSync(path, {recursive: true});
        writeFileSync(join(dock, "qmldir"), "module qs.desktop.modules.dock\nsingleton WindowService 1.0 WindowService.qml\n");
        writeFileSync(join(dock, "WindowService.qml"), 'pragma Singleton\nimport QtQuick\nQtObject { property var records: []; function lastActivatedAtOf(id) { return 0 } }');
        writeFileSync(join(platform, "qmldir"), "module qs.desktop.modules.platform\nsingleton PlatformClient 1.0 PlatformClient.qml\n");
        writeFileSync(join(platform, "PlatformClient.qml"), 'pragma Singleton\nimport QtQuick\nQtObject { function supports(operation) { return false } }');
        copyFileSync(new URL("../../shell/desktop/modules/common/NotificationCountMatch.mjs", import.meta.url), join(common, "NotificationCountMatch.mjs"));
        for (const file of ["NotificationCenter.qml", "NotificationHistoryService.qml", "NotificationHistoryObserver.qml"])
            copyFileSync(new URL(`../../shell/desktop/modules/notifications/${file}`, import.meta.url), join(notifications, file));
        copyFileSync(new URL("../../shell/desktop/modules/notifications/NotificationIdentity.mjs", import.meta.url),
            join(notifications, "NotificationIdentity.mjs"));
        writeFileSync(join(notifications, "qmldir"), "module qs.desktop.modules.notifications\nNotificationCenter 1.0 NotificationCenter.qml\nsingleton NotificationHistoryService 1.0 NotificationHistoryService.qml\nNotificationHistoryObserver 1.0 NotificationHistoryObserver.qml\nNotificationGroupService 1.0 NotificationGroupService.qml\nNotificationWindow 1.0 NotificationWindow.qml\nsingleton NotificationPolicyService 1.0 NotificationPolicyService.qml\n");
        writeFileSync(join(common, "qmldir"), "module qs.desktop.modules.common\nsingleton ScreenLifecycle 1.0 ScreenLifecycle.qml\nsingleton AppNotificationService 1.0 AppNotificationService.qml\nsingleton AppPresentationService 1.0 AppPresentationService.qml\n");
        writeFileSync(join(common, "AppPresentationService.qml"), 'pragma Singleton\nimport QtQuick\nQtObject { function normalize(value) { return String(value || "").toLowerCase() } }');
        writeFileSync(join(common, "ScreenLifecycle.qml"), `pragma Singleton
import QtQuick
QtObject { property var activeScreen: null; property bool outputAvailable: false }
`);
        writeFileSync(join(common, "AppNotificationService.qml"), `pragma Singleton
import QtQuick
import qs.desktop.modules.bar
QtObject { function recordNotification(n) { ControlCenterService.doNotDisturbEnabled = n.appName === "DND" } }
`);
        writeFileSync(join(bar, "qmldir"), "module qs.desktop.modules.bar\nsingleton ControlCenterService 1.0 ControlCenterService.qml\n");
        writeFileSync(join(bar, "ControlCenterService.qml"), `pragma Singleton
import QtQuick
QtObject { property bool doNotDisturbEnabled: false }
`);
        writeFileSync(join(notifications, "NotificationPolicyService.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property bool bannersEnabled: true
    property bool historyEnabled: true
    property var blockedKeys: []
    function remember(notification) {}
    function isBlocked(notification) { return false }
}
`);
        writeFileSync(join(notifications, "NotificationWindow.qml"), `import QtQuick
QtObject { property var screen; property bool visible: false; property var groupService }
`);
        writeFileSync(join(notifications, "NotificationGroupService.qml"), `import QtQuick
import qs.desktop.modules.notifications
QtObject {
    property var sourceModel
    property int records: 0
    function _collectNotifications() { return [] }
    function pushHistory(n) {
        records++
        NotificationHistoryService.push({notifId: n.id, appName: n.appName,
            appIcon: n.appIcon, summary: n.summary, body: n.body,
            urgency: n.urgency, timestamp: Date.now()})
        const row = NotificationHistoryService.history.get(0)
        console.log("RECORD " + JSON.stringify({records: records, count: NotificationHistoryService.count,
            key: row.historyKey, summary: row.summary, body: row.body}))
        if (n.summary === "clear") NotificationHistoryService.clear()
    }
}
`);
        let output = "";
        shell = spawn(process.argv.at(-1), ["-p", directory], {env: {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software"}, stdio: ["ignore", "pipe", "pipe"]});
        shell.stdout.on("data", chunk => { output += chunk; });
        shell.stderr.on("data", chunk => { output += chunk; });
        const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
        async function waitFor(test) {
            const deadline = Date.now() + 5000;
            while (!test() && Date.now() < deadline) await sleep(20);
            assert(test(), output);
        }
        function records() { return [...output.matchAll(/RECORD (\{[^\n]+\})/g)].map(match => JSON.parse(match[1])); }
        function call(method, args) {
            const result = spawnSync("gdbus", ["call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", `org.freedesktop.Notifications.${method}`, "--", ...args], {encoding: "utf8"});
            assert.equal(result.status, 0, result.stderr + output);
            return result.stdout;
        }
        function notify(app, id, summary, body) {
            return Number(call("Notify", [app, String(id), "", summary, body, "[]", "{}", "-1"]).match(/uint32 (\d+)/)[1]);
        }
        await waitFor(() => output.includes("Configuration Loaded"));
        const id = notify("Test", 0, "first", "old");
        await waitFor(() => records().length === 1);
        notify("Test", id, "updated", "new");
        await waitFor(() => records().length === 2);
        assert.equal(records()[1].count, 1);
        assert.equal(records()[1].body, "new");
        assert.equal(records()[1].summary, "updated");
        assert.equal(records()[1].key, records()[0].key);
        notify("Test", id, "clear", "cleared");
        await waitFor(() => records().length === 3);
        notify("Test", id, "after clear", "restored");
        await waitFor(() => records().length === 4);
        assert.equal(records()[3].count, 1);
        assert.equal(records()[3].body, "restored");
        assert.notEqual(records()[3].key, records()[2].key);
        notify("Test", id, "clear", "last");
        await waitFor(() => records().length === 5);
        call("CloseNotification", [String(id)]);
        await sleep(150);
        assert.equal(records().length, 5, "close must not reinsert cleared history");
        notify("DND", 0, "silent", "dnd");
        await waitFor(() => records().length === 6);
        assert.equal(records()[5].body, "dnd");
        assert.equal(records()[5].count, 1);
        assert.doesNotMatch(output, /TypeError|ReferenceError|Failed to load/);
        console.log("Production NotificationCenter loading and real D-Bus notification arrival, replacement coalescing, clear/replacement, close and DND passed");
    } finally {
        shell?.kill("SIGTERM");
        rmSync(directory, {recursive: true, force: true});
    }
}
