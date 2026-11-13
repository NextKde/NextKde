import assert from "node:assert/strict";
import {copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {spawnSync} from "node:child_process";

// CTest invokes this under dbus-run-session. This fixture creates no notification
// server and uses a fake platform transport; all QML/state paths are temporary.
const directory = mkdtempSync(join(tmpdir(), "kos-lockscreen-qml-"));
try {
    const notifications = join(directory, "desktop/modules/notifications");
    const platform = join(directory, "desktop/modules/platform");
    const i18n = join(directory, "shared/qml/i18n");
    for (const path of [notifications, platform, i18n]) mkdirSync(path, {recursive: true});
    for (const file of ["NotificationLockScreenBridge.qml", "LockScreenNotificationSnapshot.mjs", "NotificationHistoryService.qml", "NotificationIdentity.mjs"])
        copyFileSync(new URL(`../../shell/desktop/modules/notifications/${file}`, import.meta.url), join(notifications, file));
    copyFileSync(new URL("publisher.qml", import.meta.url), join(directory, "shell.qml"));
    writeFileSync(join(notifications, "qmldir"), "module qs.desktop.modules.notifications\nNotificationLockScreenBridge 1.0 NotificationLockScreenBridge.qml\nsingleton NotificationHistoryService 1.0 NotificationHistoryService.qml\n");
    writeFileSync(join(platform, "qmldir"), "module qs.desktop.modules.platform\nsingleton PlatformClient 1.0 PlatformClient.qml\n");
    writeFileSync(join(platform, "PlatformClient.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool connected: true
    property var writes: []
    function supports(operation) { return operation === "lockscreen.notifications-publish" }
    function request(operation, payload, callback) {
        writes = writes.concat([payload.notifications])
        callback({ok: true})
    }
}
`);
    writeFileSync(join(i18n, "qmldir"), "singleton I18n 1.0 I18n.qml\n");
    writeFileSync(join(i18n, "I18n.qml"), "pragma Singleton\nimport QtQuick\nQtObject { function tr(text) { return text } }\n");
    const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {
        encoding: "utf8", timeout: 10000,
        env: {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            XDG_CONFIG_HOME: join(directory, "config"), XDG_CACHE_HOME: join(directory, "cache"),
            XDG_STATE_HOME: join(directory, "state"), XDG_RUNTIME_DIR: directory},
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error) + "\n" + output);
    assert.equal(result.status, 0, output);
    assert.match(output, /LOCKSCREEN_PUBLISHER_PASS/);
    assert.doesNotMatch(output, /LOCKSCREEN_PUBLISHER_FAIL|TypeError|ReferenceError|Failed to load/);
    console.log("Production QML publisher: arrival, replacement, removal, policies and reconnect passed");
} finally {
    rmSync(directory, {recursive: true, force: true});
}
