import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads the glass ink fixture under a real Quickshell, offscreen.
//
// The fixture is the only check that reads the *resolved* ink rather than the
// source: the option, the appearance token and the surfaces that consume them
// are four files apart, and a broken binding between them still renders
// something plausible while the glass is dark. It needs the shipping module tree
// for the same reason as the LiquidGlassPanel fixture -- the singletons reach
// across qs.desktop.modules.* and Kos.Ui -- so it symlinks the real tree instead
// of copying it.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-glass-ink-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 20000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    // Both markers go to stderr: the marker only has to survive the shell's
    // logging setup, and a build that filters qDebug drops console.log.
    assert.doesNotMatch(output, /GLASS_INK_FAIL/, output);
    assert.match(output, /GLASS_INK_PASS/);
    // A binding that reads a property the module no longer registers shows up
    // as a load-time warning rather than a wrong colour, so it is checked too.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError/,
        output);
    console.log("glass ink: the white ink of an opted-out glass, the dark ink "
        + "of a light glass, the white ink a dark desktop restores and material's "
        + "own light ink all resolve");
} finally {
    // The scratch tree is nothing but symlinks, and some sandboxes route rm
    // through a trash directory the process cannot write. Cleanup failing says
    // nothing about the ink, so it must not be able to fail the test.
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
