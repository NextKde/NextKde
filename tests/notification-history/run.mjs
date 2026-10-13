import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const directory = mkdtempSync(join(tmpdir(), "nextkde-notification-history-"));
try {
    copyFileSync(new URL("shell.qml", import.meta.url), join(directory, "shell.qml"));
    copyFileSync(new URL("../../shell/desktop/modules/notifications/NotificationHistoryService.qml", import.meta.url),
        join(directory, "NotificationHistoryService.qml"));
    copyFileSync(new URL("../../shell/desktop/modules/notifications/NotificationIdentity.mjs", import.meta.url),
        join(directory, "NotificationIdentity.mjs"));
    writeFileSync(join(directory, "qmldir"), "singleton NotificationHistoryService 1.0 NotificationHistoryService.qml\n");
    const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {
        encoding: "utf8", timeout: 10000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error));
    assert.equal(result.status, 0, output);
    assert.match(output, /HISTORY_MODEL_TEST_PASS/);
    console.log("Notification history: grouping, removal, replacement updates, capacity and clear passed");
} finally {
    rmSync(directory, { recursive: true, force: true });
}
