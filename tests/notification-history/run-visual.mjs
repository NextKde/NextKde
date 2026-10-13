import { stageIcons } from "./stage-icons.mjs";
import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
const directory = mkdtempSync(join(tmpdir(), "nextkde-notification-visual-"));
try {
    stageIcons(directory);
    copyFileSync(new URL("visual.qml", import.meta.url), join(directory, "shell.qml"));
    for (const file of ["NotificationHistoryGroup.qml", "NotificationHistoryEntry.qml"])
        copyFileSync(new URL(`../../shell/desktop/modules/bar/${file}`, import.meta.url), join(directory, file));
    for (const file of ["NotificationHistoryService.qml", "NotificationIdentity.mjs"])
        copyFileSync(new URL(`../../shell/desktop/modules/notifications/${file}`, import.meta.url), join(directory, file));
    writeFileSync(join(directory, "qmldir"), "singleton NotificationHistoryService 1.0 NotificationHistoryService.qml\nNotificationHistoryGroup 1.0 NotificationHistoryGroup.qml\nNotificationHistoryEntry 1.0 NotificationHistoryEntry.qml\nNotificationSourceIcon 1.0 NotificationSourceIcon.qml\n");
    const result = spawnSync(process.argv[2] || "quickshell", ["-p", directory], {encoding: "utf8", timeout: 8000, env: {...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software"}});
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.status, 0, output);
    assert.match(output, /HISTORY_VISUAL_TEST_PASS/);
    assert.doesNotMatch(output, /TypeError|ReferenceError|Unable to assign|Required property|Error:|Failed to load/);
    console.log("Real history delegates: collapse/expand, single and group exits, new arrivals and clear passed");
} finally { rmSync(directory, {recursive: true, force: true}); }
