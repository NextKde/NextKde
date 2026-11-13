import assert from "node:assert/strict";
import {mkdirSync, mkdtempSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {spawn, spawnSync} from "node:child_process";
import {createConnection} from "node:net";

// Even direct invocation creates a private bus before starting the real daemon.
if (process.argv[2] !== "--isolated") {
    const result = spawnSync("dbus-run-session", [process.execPath, fileURLToPath(import.meta.url),
        "--isolated", process.argv[2]], {encoding: "utf8", timeout: 20000});
    assert.equal(result.status, 0, (result.stdout || "") + (result.stderr || ""));
    console.log(result.stdout.trim());
} else {
    const directory = mkdtempSync(join(tmpdir(), "kos-lockscreen-platform-"));
    const socketPath = join(directory, "platform.sock");
    const noTools = join(directory, "no-tools");
    mkdirSync(noTools);
    const daemon = spawn(process.argv[3], [], {
        env: {...process.env, HOME: directory, XDG_RUNTIME_DIR: directory,
            XDG_CONFIG_HOME: join(directory, "config"), XDG_DATA_HOME: join(directory, "data"),
            XDG_STATE_HOME: join(directory, "state"), XDG_CACHE_HOME: join(directory, "cache"),
            KOS_PLATFORM_SOCKET: socketPath, QT_QPA_PLATFORM: "offscreen", PATH: noTools},
        stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    let socket;
    let other;
    daemon.stdout.on("data", data => { output += data; });
    daemon.stderr.on("data", data => { output += data; });
    const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
    async function waitFor(test) {
        const deadline = Date.now() + 5000;
        while (!test() && Date.now() < deadline) {
            assert.equal(daemon.exitCode, null, output);
            await sleep(20);
        }
        assert(test(), output);
    }
    function bus(interfaceName, method, args = []) {
        const result = spawnSync("gdbus", ["call", "--session", "--dest", "org.kos.LockScreen",
            "--object-path", "/org/kos/LockScreen", "--method", `${interfaceName}.${method}`, ...args],
            {encoding: "utf8", timeout: 2000});
        assert.equal(result.status, 0, result.stderr + output);
        return result.stdout;
    }
    function open() {
        const client = createConnection(socketPath);
        let nextId = 0;
        let buffer = "";
        const pending = new Map();
        client.on("data", bytes => {
            buffer += bytes;
            let end;
            while ((end = buffer.indexOf("\n")) >= 0) {
                const response = JSON.parse(buffer.slice(0, end));
                buffer = buffer.slice(end + 1);
                const callback = pending.get(response.requestId);
                pending.delete(response.requestId);
                callback?.(response);
            }
        });
        client.request = (operation, payload = {}) => new Promise((resolve, reject) => {
            const requestId = String(++nextId);
            const timeout = setTimeout(() => reject(Error("request timed out: " + output)), 2000);
            pending.set(requestId, response => { clearTimeout(timeout); resolve(response); });
            client.write(JSON.stringify({version: 1, requestId, operation, payload}) + "\n");
        });
        return client;
    }
    try {
        await waitFor(() => output.includes("READY"));
        socket = open();
        const ping = await socket.request("platform.ping");
        assert(ping.ok && ping.result.capabilities.includes("lockscreen.notifications-publish"));
        const notification = {id: "1", appName: "Platform integration", appIcon: "mail-unread",
            createdAt: Date.now(), summary: "", body: ""};
        assert((await socket.request("lockscreen.notifications-publish", {notifications: [notification]})).ok);
        assert.match(bus("org.kos.LockScreen1", "GetNotifications"), /Platform integration/);
        const privateData = await socket.request("lockscreen.notifications-publish",
            {notifications: [{...notification, body: "NEVER EXPORT"}]});
        assert.equal(privateData.error.code, "invalid-lockscreen-notifications");
        assert.doesNotMatch(bus("org.kos.LockScreen1", "GetNotifications"), /NEVER EXPORT/);
        other = open();
        const conflict = await other.request("lockscreen.notifications-publish", {notifications: []});
        assert.equal(conflict.error.code, "lockscreen-publisher-busy");
        socket.destroy();
        await waitFor(() => bus("org.kos.LockScreen1", "GetNotifications").includes("'[]'"));
        assert((await other.request("lockscreen.notifications-publish", {notifications: []})).ok);
        const owner = spawnSync("gdbus", ["call", "--session", "--dest", "org.freedesktop.DBus",
            "--object-path", "/org/freedesktop/DBus", "--method", "org.freedesktop.DBus.NameHasOwner",
            "org.freedesktop.Notifications"], {encoding: "utf8", timeout: 2000});
        assert.equal(owner.status, 0, owner.stderr);
        assert.match(owner.stdout, /false/);
        console.log("Full platform: capability, JSONL publication, privacy rejection, socket lease and notification ownership passed");
    } finally {
        socket?.destroy();
        other?.destroy();
        daemon.kill("SIGTERM");
        await new Promise(resolve => {
            if (daemon.exitCode !== null || daemon.signalCode !== null) return resolve();
            const timeout = setTimeout(() => daemon.kill("SIGKILL"), 2000);
            daemon.once("exit", () => { clearTimeout(timeout); resolve(); });
        });
        rmSync(directory, {recursive: true, force: true});
    }
}
