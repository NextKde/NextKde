import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const directory = mkdtempSync(join(tmpdir(), "nextkde-static-work-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url), join(directory, "shell.qml"));
    copyFileSync(new URL("../../shell/desktop/modules/dock/WindowRecordIndex.mjs", import.meta.url),
        join(directory, "WindowRecordIndex.mjs"));
    const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {
        encoding: "utf8", timeout: 10000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /STATIC_WORK_FAIL/);
    assert.match(output, /STATIC_WORK_PASS/);
    console.log("Quickshell offscreen: identity, reload and recovery passed");
} finally {
    rmSync(directory, { recursive: true, force: true });
}
