import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const directory = mkdtempSync(join(tmpdir(), "nextkde-date-projection-"));
try {
    copyFileSync(new URL("tst_projection.qml", import.meta.url), join(directory, "tst_projection.qml"));
    for (const name of ["DateProjection.qml", "DateBuckets.mjs"])
        copyFileSync(new URL(`../../shell/desktop/modules/common/${name}`, import.meta.url), join(directory, name));
    const result = spawnSync(process.argv[2] || "qmltestrunner", ["-input", directory], {
        encoding: "utf8", timeout: 10000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /0 failed/);
    console.log(output.trim());
} finally {
    rmSync(directory, { recursive: true, force: true });
}
