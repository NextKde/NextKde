import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads the Bar mac-style fixture under a real Quickshell, offscreen.
//
// The fixture is the only check that reads the *resolved* plate and ink rather
// than the source: the style choice, the tint, the plate colour, the blend and
// the ink are five bindings apart, and a broken link still renders something
// plausible -- an ink read off the plate instead of the blend only fails on a
// bright wallpaper at a low tint. It needs the shipping module tree for the same reason as the
// LiquidGlassPanel fixture -- the singletons reach across qs.desktop.modules.*
// and Kos.Ui -- so it symlinks the real tree instead of copying it.
//
// State and config directories are redirected into the scratch tree so the
// appearance service reads a fresh state instead of the developer's own.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-bar-mac-style-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");
    mkdirSync(join(directory, "state"));
    mkdirSync(join(directory, "config"));

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 20000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
                XDG_STATE_HOME: join(directory, "state"),
                XDG_CONFIG_HOME: join(directory, "config"),
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    // Both markers go to stderr: the marker only has to survive the shell's
    // logging setup, and a build that filters qDebug drops console.log.
    assert.doesNotMatch(output, /BAR_MAC_STYLE_FAIL/, output);
    assert.match(output, /BAR_MAC_STYLE_PASS/);
    // A binding that reads a property the module no longer registers shows up
    // as a load-time warning rather than a wrong colour, so it is checked too.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError/,
        output);
    console.log("bar mac style: the default style keeps the Bar untouched, the "
        + "selector restores the remembered tint, the plate opposes the "
        + "wallpaper, and the ink follows the wallpaper/plate blend at both "
        + "ends of the tint");
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
