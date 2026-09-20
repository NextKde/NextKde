import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Loads ColorScheme through the Kos.Ui alias under a real Quickshell, offscreen.
//
// The node suite (test_traditional_color.mjs) is authoritative for the colour
// maths. This fixture exists for the one thing Node cannot check: whether the
// QML engine can resolve the module graph ColorScheme.qml now pulls in —
// TraditionalColorScheme.mjs plus its Chinese/Japanese/Cam16Hct/Material
// dependencies. Those are relative imports resolved by QML's module system, so
// a file that is not where the QML side expects it is a load-time failure with
// no Node-visible symptom.
//
// Quickshell resolves "qs.desktop.modules.*" against the config directory, and
// the Kos/Ui alias inside shell/ points back into shared/qml by relative
// symlinks. Copying the tree would mean a second, drifting copy of the module
// layout, so the fixture symlinks shell/Kos into a scratch config instead and
// exercises the shipping files.
const repository = fileURLToPath(new URL("../..", import.meta.url));
const shell = join(repository, "shell");

const directory = mkdtempSync(join(tmpdir(), "kos-traditional-color-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url),
        join(directory, "shell.qml"));
    // "Kos/Ui" has to sit inside the config root for the import to resolve, and
    // shell/Kos/Ui/colorize is itself a symlink into shared/qml — the real files
    // are the ones under test.
    symlinkSync(join(shell, "Kos"), join(directory, "Kos"), "dir");
    // "qs.desktop.modules.common" resolves against the config directory too.
    // AppearanceTokens lives there, and the layer assertions below need it
    // instantiated rather than merely imported.
    symlinkSync(join(shell, "desktop"), join(directory, "desktop"), "dir");

    const result = spawnSync(process.argv[2] || "quickshell",
        ["-p", directory], {
            encoding: "utf8",
            timeout: 12000,
            env: {
                ...process.env,
                QT_QPA_PLATFORM: "offscreen",
                QT_QUICK_BACKEND: "software",
            },
        });

    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /TRADITIONAL_COLOR_PASS/);
    assert.doesNotMatch(output, /TRADITIONAL_COLOR_FAIL/, output);
    // A module graph that resolves but is missing data would surface here
    // rather than as a wrong colour.
    assert.doesNotMatch(output,
        /is not a type|is not a function|Cannot assign|Unable to assign|ReferenceError|TypeError|module .* is not installed|SyntaxError/,
        output);
    console.log("ColorScheme offscreen: all three colour sources load and "
        + "rebuild through the Kos.Ui alias");
} finally {
    // The scratch tree is only symlinks, and some sandboxes route rm through a
    // trash directory the process cannot write. Cleanup failing says nothing
    // about the scheme, so it must not be able to fail the test.
    try {
        rmSync(directory, { recursive: true, force: true });
    } catch {
        console.error(`left ${directory} for the system temp reaper`);
    }
}
