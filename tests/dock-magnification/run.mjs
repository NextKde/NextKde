import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Runs the shipping DockIcon through boundary, entry, tracking and exit probes.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-dock-magnification-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    // Quickshell resolves "qs.desktop.modules.*" against the config directory,
    // and AppearanceTokens reaches the shared library through the Kos/Ui alias
    // with a path relative to its own file.
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

    // The magnification tokens (and therefore the hover lift this test is about)
    // only switch on for the macOS shell style, which is also the default. An
    // empty config home guarantees that default instead of inheriting whatever
    // the machine running the test has selected.
    const configHome = join(directory, "config");
    mkdirSync(configHome, { recursive: true });

    const runtimeDir = join(directory, "runtime");
    mkdirSync(runtimeDir, { mode: 0o700 });
    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 20000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
                QT_LOGGING_RULES: "qml.debug=true",
                XDG_CONFIG_HOME: configHome,
                XDG_STATE_HOME: join(directory, "state"),
                XDG_RUNTIME_DIR: runtimeDir,
                WAYLAND_DISPLAY: "", DISPLAY: "",
                DBUS_SESSION_BUS_ADDRESS: "unix:path=" + join(runtimeDir, "no-bus"),
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /DOCK_MAGNIFICATION_PASS/);
    // QML resolves types and property names at load time, so this catches
    // DockIcon drifting away from its own module registration.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|Binding loop/,
        output);
    // The fixture reports visual and temporal regressions as explicit failures.
    assert.doesNotMatch(output, /FAIL /, output);

    for (const line of output.split("\n"))
        if (line.includes("REPORT ")) console.log(line.slice(line.indexOf("REPORT ")));
    console.log("Dock magnification: continuous boundaries, synchronized motion and idle settlement on all edges");
} finally {
    // The scratch tree is nothing but symlinks, and some sandboxes route rm
    // through a trash directory the process cannot write. Cleanup failing says
    // nothing about the Dock, so it must not be able to fail the test.
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
