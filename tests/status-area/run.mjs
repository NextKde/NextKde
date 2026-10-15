import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { basename, isAbsolute, join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads the real status area with isolated state and config.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-status-area-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    // Retain production modules, replacing only transport with read-only data.
    // No requests or state writes can reach the user's installed daemon.
    mkdirSync(join(directory, "desktop/modules"), { recursive: true });
    for (const name of readdirSync(join(shell, "desktop"))) {
        if (name !== "modules") symlinkSync(join(shell, "desktop", name), join(directory, "desktop", name));
    }
    for (const name of readdirSync(join(shell, "desktop/modules"))) {
        if (name !== "platform") symlinkSync(join(shell, "desktop/modules", name), join(directory, "desktop/modules", name));
    }
    mkdirSync(join(directory, "desktop/modules/platform"));
    for (const name of readdirSync(join(shell, "desktop/modules/platform"))) {
        if (name !== "PlatformClient.qml") symlinkSync(join(shell, "desktop/modules/platform", name), join(directory, "desktop/modules/platform", name));
    }
    copyFileSync(new URL("../notification-history/NativePlatformFixture.qml", import.meta.url),
        join(directory, "desktop/modules/platform/PlatformClient.qml"));
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");
    symlinkSync(join(shell, "shared"), join(directory, "shared"), "dir");
    mkdirSync(join(directory, "state"));
    mkdirSync(join(directory, "config"));
    mkdirSync(join(directory, "runtime"), { mode: 0o700 });
    const display = process.env.WAYLAND_DISPLAY || "wayland-0";
    const socket = isAbsolute(display) ? display : join(process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`, display);
    symlinkSync(socket, join(directory, "runtime", basename(display)));

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory, "--no-color"], {
            encoding: "utf8",
            timeout: 20000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: process.env.QT_QPA_PLATFORM || "wayland",
                QT_QUICK_BACKEND: "software",
                XDG_STATE_HOME: join(directory, "state"),
                XDG_CONFIG_HOME: join(directory, "config"),
                XDG_RUNTIME_DIR: join(directory, "runtime"),
                WAYLAND_DISPLAY: basename(display),
                KOS_DATA_SOCKET: join(directory, "absent-data.sock"),
                DBUS_SESSION_BUS_ADDRESS: "unix:path=" + join(directory, "absent-bus"),
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    // Check failures even if the fixture reaches its completion marker.
    assert.doesNotMatch(output, /STATUS_AREA_FAIL/, output);
    assert.match(output, /STATUS_AREA_PASS/);
    // Ignore singleton teardown warnings after Qt.quit().
    assert.doesNotMatch(output.split("STATUS_AREA_PASS")[0],
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|Binding loop|no parent window/i,
        output);
    console.log("status area: ordering, visibility, mapped editor, sample events, Escape and outside dismissal passed");
} finally {
    // The scratch tree is nothing but symlinks, and some sandboxes route rm
    // through a trash directory the process cannot write. Cleanup failing says
    // nothing about the style, so it must not be able to fail the test.
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
