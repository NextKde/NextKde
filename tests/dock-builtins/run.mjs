import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

// Run the real configuration service and JSON transport across three starts. Only the
// platform's state storage is replaced, so this never writes user settings.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const directory = mkdtempSync(join(tmpdir(), "kos-dock-builtins-"));
const socket = join(directory, "platform.sock");
const saved = new Map();
const server = createServer((connection) => {
    let pending = "";
    connection.on("data", (chunk) => {
        pending += chunk;
        let newline;
        while ((newline = pending.indexOf("\n")) >= 0) {
            const request = JSON.parse(pending.slice(0, newline));
            pending = pending.slice(newline + 1);
            const payload = request.payload ?? {};
            const key = `${payload.dir}/${payload.file}`;
            let result = {};
            if (request.operation === "state.write")
                saved.set(key, payload.data);
            if (request.operation === "state.read")
                result = { exists: saved.has(key), data: saved.get(key) ?? "" };
            connection.write(JSON.stringify({ version: 1, requestId: request.requestId, ok: true, result }) + "\n");
        }
    });
});

async function run(reload) {
    const child = spawn(process.argv[2] || "quickshell", ["-p", directory], {
        env: {
            ...process.env,
            QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            XDG_CONFIG_HOME: join(directory, "config"),
            XDG_STATE_HOME: join(directory, "state"),
            KOS_PLATFORM_SOCKET: socket,
            KOS_DATA_SOCKET: join(directory, "absent-data.sock"),
            KOS_TEST_RELOAD: String(reload),
            WAYLAND_DISPLAY: "", DISPLAY: "",
        },
    });
    let output = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    const timeout = setTimeout(() => child.kill("SIGKILL"), 10000);
    try {
        const status = await new Promise((resolve, reject) => {
            child.on("error", reject);
            child.on("exit", resolve);
        });
        assert.equal(status, 0, output);
        assert.doesNotMatch(output, /FAIL |ReferenceError|TypeError|Binding loop/);
        assert.ok(output.includes(reload === 2 ? "DOCK_BUILTINS_DEFAULT_RELOAD_PASS"
            : reload === 1 ? "DOCK_BUILTINS_RELOAD_PASS"
            : "DOCK_BUILTINS_SAVE_PASS"), output);
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
    await run(0);
    assert.ok([...saved.values()].some((data) => {
        const value = JSON.parse(data);
        return value.showLauncher === false && value.showTrash === false;
    }), "visibility booleans must be serialized");
    await run(1);
    assert.ok([...saved.values()].some((data) => {
        const value = JSON.parse(data);
        return value.showLauncher === true && value.showTrash === true;
    }), "restoring defaults must also persist");
    await run(2);
    console.log("Dock built-ins: defaults, validation, independent toggles, persistence and restart passed");
} finally {
    server.close();
    rmSync(directory, { recursive: true, force: true });
}
