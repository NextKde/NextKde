import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Run the real presentation, identity and action services against a stub
// platform socket. The launch requests can then be inspected without starting
// any application and without touching user settings.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const directory = mkdtempSync(join(tmpdir(), "kos-app-launch-"));
const socket = join(directory, "platform.sock");
const launches = [];

const server = createServer((connection) => {
    let pending = "";
    connection.on("data", (chunk) => {
        pending += chunk;
        let newline;
        while ((newline = pending.indexOf("\n")) >= 0) {
            const request = JSON.parse(pending.slice(0, newline));
            pending = pending.slice(newline + 1);
            if (request.operation === "application.launch")
                launches.push(request.payload?.desktopId ?? "");
            connection.write(JSON.stringify({
                version: 1, requestId: request.requestId, ok: true, result: {},
            }) + "\n");
        }
    });
});

async function run() {
    const child = spawn(process.argv[2] || "quickshell", ["-p", directory], {
        env: {
            ...process.env,
            QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            XDG_CONFIG_HOME: join(directory, "config"),
            XDG_STATE_HOME: join(directory, "state"),
            KOS_PLATFORM_SOCKET: socket,
            KOS_DATA_SOCKET: join(directory, "absent-data.sock"),
        },
    });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    const timeout = setTimeout(() => child.kill("SIGKILL"), 25000);
    try {
        const status = await new Promise((resolve, reject) => {
            child.on("error", reject);
            child.on("exit", resolve);
        });
        assert.equal(status, 0, output);
        assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop/);
        assert.ok(output.includes("APP_LAUNCH_RESOLUTION_PASS"), output);
        const match = output.match(/APP_LAUNCH_TARGET (\S+)/);
        assert.ok(match, output);
        const second = output.match(/APP_LAUNCH_SECOND (\S+)/);
        return { target: match[1], second: second ? second[1] : "" };
    } finally {
        clearTimeout(timeout);
        child.kill();
    }
}

try {
    copyFileSync(new URL("shell.qml", import.meta.url), join(directory, "shell.qml"));
    symlinkSync(join(repository, "shell/desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(repository, "shell/Kos"), join(directory, "Kos"), "dir");
    mkdirSync(join(directory, "config"));
    await new Promise((resolve) => server.listen(socket, resolve));
    const { target, second } = await run();
    assert.ok(launches.includes(target),
        `the daemon must receive application.launch for ${target}`
        + ` (got ${JSON.stringify(launches)})`);
    assert.ok(launches.includes("kos-missing-entry.desktop"),
        "an uninstalled desktop id must still reach the daemon");
    if (second) {
        assert.ok(launches.includes(second),
            `the Dock new-window action must reach the daemon for ${second}`
            + ` (got ${JSON.stringify(launches)})`);
    }
    console.log("App launch resolution: descriptors and identity results carry"
        + " no entry, entryFor resolves by id, launch forwards the desktop id");
} finally {
    server.close();
    rmSync(directory, { recursive: true, force: true });
}
