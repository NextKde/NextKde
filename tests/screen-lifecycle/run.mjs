import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const directory = mkdtempSync(join(tmpdir(), "kos-screen-lifecycle-"));
try {
    const commonDir = new URL("../../shell/desktop/modules/common/", import.meta.url);
    copyFileSync(new URL("ScreenSelection.mjs", commonDir), join(directory, "ScreenSelection.mjs"));
    writeFileSync(join(directory, "ScreenLifecycle.qml"),
        readFileSync(new URL("ScreenLifecycle.qml", commonDir), "utf8")
            .replace("import Quickshell", 'import "."')
            .replace('import "../platform"', 'import "."'));
    writeFileSync(join(directory, "Quickshell.qml"), `pragma Singleton
import QtQuick
QtObject {
    property var screens: []
}
`);
    writeFileSync(join(directory, "PlatformClient.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool connected: true
    property var calls: []
    property var visibilityHandler: null
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)
    function request(op, payload, callback) {
        calls = calls.concat([{ op: op, payload: payload }]);
        if (op === "session.visibility" && visibilityHandler) {
            visibilityHandler(callback);
            return;
        }
        if (callback)
            callback({ ok: true, result: { available: true, outputs: [] } });
    }
}
`);
    writeFileSync(join(directory, "qmldir"),
        "singleton Quickshell 1.0 Quickshell.qml\n"
        + "singleton PlatformClient 1.0 PlatformClient.qml\n"
        + "singleton ScreenLifecycle 1.0 ScreenLifecycle.qml\n");
    copyFileSync(new URL("tst_lock_gate.qml", import.meta.url), join(directory, "tst_lock_gate.qml"));

    const runner = process.argv[2] || "qmltestrunner";
    const result = spawnSync(runner, ["-input", join(directory, "tst_lock_gate.qml")], {
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software" },
        encoding: "utf8",
    });
    process.stdout.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    assert.equal(result.status, 0);
} finally {
    rmSync(directory, { recursive: true, force: true });
}
