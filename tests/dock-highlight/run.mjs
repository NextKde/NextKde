import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

// Test the shipping paint-only component without importing the Dock's
// Quickshell-only service registry into a plain Qt Quick Test process.
const directory = mkdtempSync(join(tmpdir(), "kos-dock-highlight-"));
try {
    copyFileSync(new URL("../../shared/qml/controls/SelectionHighlight.qml", import.meta.url),
        join(directory, "SelectionHighlight.qml"));
    const dockWrapper = readFileSync(new URL("../../shell/desktop/modules/dock/DockIconHighlight.qml", import.meta.url), "utf8")
        .replace('import "../../../Kos/Ui"', 'import "."');
    writeFileSync(join(directory, "DockIconHighlight.qml"), dockWrapper);
    const fixture = readFileSync(new URL("tst_highlight.qml", import.meta.url), "utf8")
        .replace('import "../../shell/desktop/modules/dock" as Dock', 'import "." as Dock');
    writeFileSync(join(directory, "tst_highlight.qml"), fixture);
    const result = spawnSync(process.argv[2] || "qmltestrunner", ["-input", directory], {
        encoding: "utf8",
        timeout: 15000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error) + "\n" + output);
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL!|ReferenceError|TypeError|Binding loop/);
    console.log(output.trim());
} finally {
    rmSync(directory, { recursive: true, force: true });
}
