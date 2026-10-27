import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const binary = process.argv[2];
const quickshell = process.argv[3] || "quickshell";
assert(binary, "usage: bridge.mjs <kos-settings binary> [quickshell binary]");
const directory = mkdtempSync(join(tmpdir(), "kos-notification-bridge-"));
const shellDir = join(directory, "shell");
mkdirSync(shellDir);
mkdirSync(join(directory, "apps/settings"), { recursive: true });
writeFileSync(join(shellDir, "shell.qml"), `import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: fixture
    property bool badges: true
    property bool sound: false
    property bool blocked: false
    IpcHandler {
        id: handler
        target: "notification-settings"
        function snapshot(): string { return JSON.stringify({ready:true,
            sources:[{key:"desktop:mail", appName:"邮件"}], blockedKeys:fixture.blocked ? ["desktop:mail"] : [],
            showNotificationBadges:fixture.badges, soundEnabled:fixture.sound, bannersEnabled:true, showPreview:true, saveError:""}) }
        function setPreference(key: string, value: bool): string {
            if (key === "invalid") return "invalid JSON"
            if (key === "soundEnabled") fixture.sound = value
            else fixture.badges = value
            return snapshot()
        }
        function setBlocked(key: string, value: bool): string { fixture.blocked=value; return snapshot() }
    }
}
`);
writeFileSync(join(directory, "apps/settings/main.qml"), `import QtQuick
import QtQuick.Controls
ApplicationWindow {
    visible:true; width:320; height:200
    property int step:0
    function assert(value, message) { if (!value) throw new Error(message) }
    Connections {
        target: settingsBridge
        function onNotificationSnapshotChanged(state) {
            if (step === 0) {
                assert(state.ready && state.sources[0].appName === "邮件", "snapshot preserves policy and app list: " + JSON.stringify(state) + " / " + settingsBridge.lastError)
                assert(state.showNotificationBadges, "initial badge state")
                step++
                settingsBridge.setNotificationPreference("showNotificationBadges", false)
            } else if (step === 1) {
                assert(!state.showNotificationBadges, "preference round trip")
                assert(!state.soundEnabled, "sound defaults off")
                step++
                settingsBridge.setNotificationPreference("soundEnabled", true)
            } else if (step === 2) {
                assert(state.soundEnabled, "sound preference round trip")
                step++
                settingsBridge.setNotificationBlocked("desktop:mail", true)
            } else if (step === 3) {
                assert(state.blockedKeys[0] === "desktop:mail", "application policy round trip")
                step++
                settingsBridge.setNotificationPreference("invalid", false)
            } else {
                assert(state.ready === undefined && settingsBridge.lastError.length > 0, "invalid reply releases page with error")
                console.log("NOTIFICATION_BRIDGE_PASS")
                Qt.quit()
            }
        }
    }
    Component.onCompleted: settingsBridge.notificationSnapshot()
    Timer { running:true; interval:10000; onTriggered: { throw new Error("bridge timeout"); Qt.quit() } }
}
`);
const env = {...process.env, QT_QPA_PLATFORM:"offscreen", QT_QUICK_BACKEND:"software", QT_FORCE_STDERR_LOGGING:"1", KOS_SHELL_DIR:shellDir};
let child, launchError, log = "";
try {
    child = spawn(quickshell, ["-p", shellDir, "--no-color"], { env });
    child.on("error", error => { launchError = error; });
    child.stdout.on("data", data => { log += data; });
    child.stderr.on("data", data => { log += data; });
    const deadline = Date.now() + 5000;
    while (!launchError && !log.includes("Configuration Loaded") && Date.now() < deadline)
        await new Promise(resolve => setTimeout(resolve, 25));
    assert(!launchError, "Quickshell fixture failed to start: " + launchError + "\n" + log);
    assert(log.includes("Configuration Loaded"), log);
    const result = spawnSync(binary, [], {env, encoding:"utf8", timeout:12000});
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.status, 0, output + "\n" + log);
    assert.match(output, /NOTIFICATION_BRIDGE_PASS/);
    assert.doesNotMatch(output, /ReferenceError|TypeError|Failed to load/);
    console.log("Notification settings bridge: snapshot, badges, app policy and invalid reply passed");
} finally {
    child?.kill("SIGTERM");
    rmSync(directory, { recursive:true, force:true });
}
