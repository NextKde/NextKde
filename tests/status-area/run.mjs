import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads the real status area with isolated state and config.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-status-area-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");
    symlinkSync(join(shell, "shared"), join(directory, "shared"), "dir");
    mkdirSync(join(directory, "state"));
    mkdirSync(join(directory, "config"));

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 20000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: process.env.QT_QPA_PLATFORM || "wayland",
                QT_QUICK_BACKEND: "software",
                XDG_STATE_HOME: join(directory, "state"),
                XDG_CONFIG_HOME: join(directory, "config"),
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
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError/,
        output);
    console.log("status area: independent readouts, ordering, visibility, Dock exclusion and editor toggle passed");
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
