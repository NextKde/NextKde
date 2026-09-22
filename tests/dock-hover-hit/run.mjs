import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads the shipping DockIcon under a real Quickshell, offscreen, and drives its
// `magnificationPointer` by hand (a pointer never enters an offscreen window).
//
// What this pins: `_hovering` must be a pure function of the pointer against the
// icon's *untransformed* slot. It used to be `_mouseArea.containsMouse`, and
// that MouseArea is anchored to the icon, so it moved with the hover lift/scale
// it drove -- with the cursor parked on the slot's bottom edge the icon lifted
// out from under it, the hover cleared, the icon dropped back and the cycle
// repeated. That is an endless jitter, and no other test in the suite looks at
// where the Dock decides an icon is hovered.
//
// The fixture also reports the width of the band where the old
// transformed-rect test disagrees with the slot test, so the size of the
// removed defect is visible in the log rather than asserted.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-dock-hover-hit-"));
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

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 20000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
                XDG_CONFIG_HOME: configHome,
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /DOCK_HOVER_HIT_PASS/);
    // QML resolves types and property names at load time, so this catches
    // DockIcon drifting away from its own module registration.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|Binding loop/,
        output);
    // A binding loop between the hover test and the lift it drives is the whole
    // defect; QML reports it, and the fixture must never accept it.
    assert.doesNotMatch(output, /FAIL /, output);

    for (const line of output.split("\n"))
        if (line.includes("REPORT ")) console.log(line.slice(line.indexOf("REPORT ")));
    console.log("DockIcon hover: resolved against the untransformed slot on both axes");
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
