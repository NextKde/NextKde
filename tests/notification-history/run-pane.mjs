import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
const directory = mkdtempSync(join(tmpdir(), "kos-notification-pane-"));
try {
    for (const entry of ["desktop", "Kos", "shared"])
        symlinkSync(fileURLToPath(new URL(`../../shell/${entry}`, import.meta.url)), join(directory, entry));
    for (const [file, marker] of [["pane.qml", "HISTORY_PANE_PASS"], ["empty-state.qml", "HISTORY_EMPTY_STATE_PASS"]]) {
        copyFileSync(new URL(file, import.meta.url), join(directory, "shell.qml"));
        const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory, "--no-color"], {
            encoding:"utf8", timeout:8000,
            env:{...process.env, QT_QPA_PLATFORM:"offscreen", QT_QUICK_BACKEND:"software"}
        });
        const output = (result.stdout || "") + (result.stderr || "");
        assert.equal(result.status, 0, output);
        assert(output.includes(marker), output);
        assert.doesNotMatch(output, /ReferenceError|TypeError|Binding loop|Error:|Failed to load configuration/);
    }
    console.log("Notification pane: preview, dismiss, expansion, scrolling, clear/arrival and smooth empty-state handoff passed");
} finally { rmSync(directory, {recursive:true, force:true}); }
