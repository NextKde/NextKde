import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync, writeFileSync, mkdirSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
if (!process.argv.includes("--session")) {
    const result = spawnSync("dbus-run-session", [process.execPath, fileURLToPath(import.meta.url), "--session", process.argv[2] || "quickshell"], {encoding: "utf8", timeout: 55000});
    assert.equal(result.status, 0, (result.stdout || "") + (result.stderr || ""));
    console.log(result.stdout.trim());
} else {
    const directory = mkdtempSync(join(tmpdir(), "nextkde-notification-production-"));
    let shell, output = "";
    const quickshell = process.argv.at(-1);
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    function fixture(module, entries) {
        const dir = join(directory, "desktop/modules", module);
        mkdirSync(dir, {recursive: true});
        const declarations = [];
        for (const [name, source, singleton] of entries) {
            if (source.startsWith("@")) copyFileSync(new URL(source.slice(1), import.meta.url), join(dir, name + ".qml"));
            else writeFileSync(join(dir, name + ".qml"), source);
            declarations.push(`${singleton ? "singleton " : ""}${name} 1.0 ${name}.qml`);
        }
        writeFileSync(join(dir, "qmldir"), `module qs.desktop.modules.${module}\n${declarations.join("\n")}\n`);
        return dir;
    }
    async function waitFor(test) {
        const deadline = Date.now() + 6000;
        while (!test() && Date.now() < deadline) await sleep(25);
        assert(test(), output);
    }
    function ipc(method, ...args) {
        const result = spawnSync(quickshell, ["-p", directory, "ipc", "call", "notifications", method, ...args.map(String)], {encoding: "utf8"});
        assert.equal(result.status, 0, result.stderr + output);
        return result.stdout.trim();
    }
    function stats() { return JSON.parse(ipc("stats")); }
    function notify(app, id, summary, body, desktop = "", extraHints = "") {
        const hints = [desktop ? `'desktop-entry': <'${desktop}'>` : "", extraHints].filter(Boolean).join(", ");
        const result = spawnSync("gdbus", ["call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path", "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.Notify", "--", app, String(id), "", summary, body, "[]", `{${hints}}`, "-1"], {encoding: "utf8"});
        assert.equal(result.status, 0, result.stderr + output);
        return Number(result.stdout.match(/uint32 (\d+)/)[1]);
    }
    async function start() {
        output = "";
        shell = spawn(quickshell, ["-p", directory], {env: {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software", KOS_NOTIFICATION_TEST_STATE_ROOT: join(directory, "state")}, stdio: ["ignore", "pipe", "pipe"]});
        shell.stdout.on("data", chunk => { output += chunk; });
        shell.stderr.on("data", chunk => { output += chunk; });
        await waitFor(() => output.includes("Configuration Loaded"));
        await waitFor(() => stats().ready);
    }
    async function stop() {
        shell.kill("SIGTERM");
        await new Promise(resolve => shell.once("exit", resolve));
    }
    try {
        copyFileSync(new URL("production.qml", import.meta.url), join(directory, "shell.qml"));
        fixture("platform", [
            ["PlatformClient", "@PlatformClientFixture.qml", true],
            ["JsonConfigStore", "@../../shell/desktop/modules/platform/JsonConfigStore.qml", true]]);
        const common = fixture("common", [
            ["AppNotificationService", "@../../shell/desktop/modules/common/AppNotificationService.qml", true],
            ["AppPresentationService", 'pragma Singleton\nimport QtQuick\nQtObject { function normalize(value) { return String(value || "").toLowerCase() } }', true],
            ["ScreenLifecycle", 'pragma Singleton\nimport QtQuick\nQtObject { property var activeScreen: null; property bool outputAvailable: false; property int testBannerCount: 0; property int testSoundCount: 0 }', true]]);
        copyFileSync(new URL("../../shell/desktop/modules/common/NotificationCountMatch.mjs", import.meta.url), join(common, "NotificationCountMatch.mjs"));
        fixture("bar", [["ControlCenterService", 'pragma Singleton\nimport QtQuick\nQtObject { property bool doNotDisturbEnabled: false }', true]]);
        const notificationDir = fixture("notifications", [
            ...["NotificationCenter", "NotificationGroupService", "NotificationHistoryObserver", "NotificationHistoryService", "NotificationPolicyService", "NotificationSoundService"].map(name => [name, `@../../shell/desktop/modules/notifications/${name}.qml`, name.endsWith("Service") && name !== "NotificationGroupService"]),
            ["NotificationAudioPlayer", `import QtQuick
import qs.desktop.modules.common
QtObject {
    id: audio
    property bool busy: false
    property Timer end: Timer { interval: 1500; onTriggered: audio.cancel() }
    function play() {
        if (busy) return false
        busy = true
        ScreenLifecycle.testSoundCount++
        end.restart()
        return true
    }
    function cancel() { busy = false; end.stop() }
}`, false],
            ["NotificationWindow", 'import QtQuick\nimport qs.desktop.modules.common\nQtObject { property var screen; property bool visible; property var groupService; property Timer timer: Timer { running: true; repeat: true; interval: 30; onTriggered: ScreenLifecycle.testBannerCount = groupService.groupsModel.count } }', false]]);
        copyFileSync(new URL("../../shell/desktop/modules/notifications/NotificationIdentity.mjs", import.meta.url),
            join(notificationDir, "NotificationIdentity.mjs"));
        await start();
        assert.equal(stats().soundEnabled, false, "new profiles default to silent");
        assert.equal(stats().soundBackendLoaded, false, "disabled profiles do not load multimedia");
        const id = notify("Same Name", 0, "first", "old", "org.test.one");
        await waitFor(() => stats().rows.length === 1 && stats().banners === 1);
        const key = stats().rows[0].key;
        notify("Same Name", id, "update", "new", "org.test.one");
        await waitFor(() => stats().rows[0].body === "new");
        assert.equal(stats().rows.length, 1);
        assert.equal(stats().rows[0].key, key);
        assert.equal(stats().soundPlays, 0);
        ipc("dnd", true);
        const silentId = notify("DND", 0, "silent", "history", "org.test.dnd");
        await waitFor(() => stats().rows.length === 2 && stats().banners === 0);
        assert(stats().dnd);
        ipc("dnd", false);
        const blockedKey = "desktop:org.test.one";
        ipc("block", blockedKey, true);
        const beforeBlocked = stats();
        notify("Same Name", 0, "blocked", "hidden", "org.test.one");
        await sleep(150);
        assert.equal(stats().rows.length, beforeBlocked.rows.length);
        assert.deepEqual(stats().unread, beforeBlocked.unread);
        assert.equal(stats().banners, 0);
        // Same label, different desktop identity remains allowed.
        const secondId = notify("Same Name", 0, "other app", "allowed", "org.test.two");
        await waitFor(() => stats().rows.length === 3 && stats().banners === 1);
        ipc("block", "desktop:org.test.two", true);
        await waitFor(() => stats().banners === 0);
        const beforeReplace = stats();
        notify("Same Name", secondId, "blocked replacement", "hidden replacement", "org.test.two");
        await sleep(150);
        assert.equal(stats().rows.length, beforeReplace.rows.length);
        assert.deepEqual(stats().unread, beforeReplace.unread);
        ipc("block", blockedKey, false);
        notify("Same Name", 0, "allowed again", "visible", "org.test.one");
        await waitFor(() => stats().rows.length === 4 && stats().banners === 1);
        // DND objects are untracked; another replaces_id must still honor policy.
        ipc("block", "desktop:org.test.dnd", true);
        const beforeDndReplace = stats();
        notify("DND", silentId, "suppressed", "hidden", "org.test.dnd");
        await sleep(150);
        assert.equal(stats().rows.length, beforeDndReplace.rows.length);
        assert.deepEqual(stats().unread, beforeDndReplace.unread);
        ipc("preference", "bannersEnabled", false);
        const quietCount = stats().rows.length;
        notify("Quiet", 0, "no banner", "history preserved", "org.test.quiet");
        await waitFor(() => stats().rows.length === quietCount + 1 && stats().banners === 0);
        ipc("preference", "historyEnabled", false);
        const historyCount = stats().rows.length;
        notify("Quiet", 0, "no history", "not stored", "org.test.quiet");
        await sleep(150);
        assert.equal(stats().rows.length, historyCount);
        ipc("preference", "showPreview", false);
        ipc("preference", "doNotDisturbEnabled", true);
        // Explicit opt-in is retained for the restart below; startup replay stays silent.
        ipc("preference", "soundEnabled", true);
        ipc("preference", "unknown", false);
        await sleep(350);
        await stop();
        await start();
        assert.equal(stats().soundEnabled, true, "explicit sound opt-in persists across restart");
        ipc("preference", "soundEnabled", false);
        assert.equal(stats().prefs.bannersEnabled, false);
        assert.equal(stats().prefs.historyEnabled, false);
        assert.equal(stats().prefs.showPreview, false);
        assert.equal(stats().prefs.doNotDisturbEnabled, true);
        ipc("preference", "bannersEnabled", true);
        ipc("preference", "historyEnabled", true);
        ipc("preference", "doNotDisturbEnabled", false);
        assert(stats().blocked.includes("desktop:org.test.two"));
        assert(stats().sources.some(source => source.key === "desktop:org.test.two"));
        notify("Same Name", 0, "persisted blocked", "hidden", "org.test.two");
        await sleep(150);
        assert.equal(stats().rows.length, 0);
        assert.equal(stats().unread.length, 0);
        ipc("block", "desktop:org.test.two", false);
        notify("Same Name", 0, "unblocked after restart", "visible", "org.test.two");
        await waitFor(() => stats().rows.length === 1 && stats().banners === 1);
        notify("Fallback", 0, "name source", "allowed");
        await waitFor(() => stats().sources.some(source => source.key === "name:Fallback"));
        ipc("block", "name:Fallback", true);
        const beforeFallback = stats();
        notify("Fallback", 0, "name blocked", "hidden");
        await sleep(150);
        assert.equal(stats().rows.length, beforeFallback.rows.length);
        assert.deepEqual(stats().unread, beforeFallback.unread);
        notify("Fallback", 0, "desktop source", "allowed", "org.test.fallback");
        await waitFor(() => stats().rows.length === beforeFallback.rows.length + 1);
        // Exercise sound on real D-Bus arrivals with a counted backend, without
        // requiring an audio device or QtMultimedia on the CI worker.
        await sleep(2200);
        ipc("preference", "soundEnabled", true);
        await waitFor(() => stats().soundBackendLoaded);
        notify("Silent", 0, "client plays sound", "", "org.test.silent", "'suppress-sound': <true>");
        await sleep(100);
        assert.equal(stats().soundPlays, 0, "respect the client's suppress-sound hint");
        const soundId = notify("Tone", 0, "arrival", "", "org.test.tone");
        await waitFor(() => stats().soundPlays === 1);
        assert(stats().soundPlaying);
        ipc("preference", "doNotDisturbEnabled", true);
        await waitFor(() => !stats().soundPlaying);
        notify("Tone", 0, "muted", "", "org.test.tone");
        await sleep(650);
        assert.equal(stats().soundPlays, 1);
        ipc("preference", "doNotDisturbEnabled", false);
        notify("Tone", soundId, "replacement", "changed", "org.test.tone");
        await sleep(100);
        assert.equal(stats().soundPlays, 1, "replacement updates do not replay a tone");
        notify("Tone", 0, "arrival", "", "org.test.tone");
        await waitFor(() => stats().soundPlays === 2);
        notify("Tone", 0, "burst", "", "org.test.tone");
        await sleep(100);
        assert.equal(stats().soundPlays, 2, "coalesce bursts without queuing stale sounds");
        ipc("preference", "soundEnabled", false);
        await waitFor(() => !stats().soundBackendLoaded);
        assert.doesNotMatch(output, /TypeError|ReferenceError|Failed to load/);
        await sleep(350);
        await stop();
        const stateRoot = join(directory, "state");
        const relative = readdirSync(stateRoot, {recursive: true}).find(path => path.endsWith("notifications/config.json"));
        assert(relative, "notification policy was persisted");
        const policyFile = join(stateRoot, relative);
        const legacyPolicy = JSON.parse(readFileSync(policyFile, "utf8"));
        delete legacyPolicy.soundEnabled;
        writeFileSync(policyFile, JSON.stringify(legacyPolicy));
        await start();
        assert.equal(stats().soundEnabled, false, "upgrading a profile without the new key stays silent");
        assert.equal(stats().soundBackendLoaded, false);
        await stop();
        legacyPolicy.soundEnabled = "true";
        writeFileSync(policyFile, JSON.stringify(legacyPolicy));
        // A missing optional multimedia module must not break the notification
        // server, either while sound is off or after an explicit opt-in.
        writeFileSync(join(notificationDir, "NotificationAudioPlayer.qml"), "import QtQuick\nimport MissingOptionalAudioBackend 1.0\nQtObject {}\n");
        await start();
        assert.equal(stats().soundEnabled, false, "invalid stored values cannot enable sound");
        assert.equal(stats().soundBackendLoaded, false);
        ipc("preference", "soundEnabled", true);
        await waitFor(() => stats().soundBackendStatus === 3);
        notify("Missing audio", 0, "still delivered", "", "org.test.missing");
        await waitFor(() => stats().rows.some(row => row.summary === "still delivered"));
        assert(stats().ready, "multimedia failure does not break notifications");
        console.log("Production NotificationCenter: normal, DND, identity isolation, block/replacement, unblock, persisted policy and global notification sound controls passed");
    } finally {
        shell?.kill("SIGTERM");
        rmSync(directory, {recursive: true, force: true});
    }
}
