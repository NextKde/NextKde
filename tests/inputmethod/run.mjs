import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// Exercise the shipping presentation and animation in Qt Quick without a
// desktop session. Only the common-module import/token singleton is replaced.
const directory = mkdtempSync(join(tmpdir(), "kos-inputmethod-motion-"));
try {
    const source = new URL("../../shell/desktop/modules/", import.meta.url);
    writeFileSync(join(directory, "InputMethodPresentation.qml"),
        readFileSync(new URL("inputmethod/InputMethodPresentation.qml", source), "utf8")
            .replace("import qs.desktop.modules.common", 'import "."'));
    copyFileSync(new URL("common/PopupMotion.qml", source), join(directory, "PopupMotion.qml"));
    copyFileSync(new URL("inputmethod/InputMethodPlacement.mjs", source), join(directory, "InputMethodPlacement.mjs"));
    writeFileSync(join(directory, "InputMethodService.qml"),
        readFileSync(new URL("inputmethod/InputMethodService.qml", source), "utf8")
            .replace("import Quickshell", "")
            .replace("import qs.desktop.modules.platform", 'import "."')
            .replace("import qs.desktop.modules.dock", "")
            .replace("Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null", "null"));
    copyFileSync(new URL("motion.qml", import.meta.url), join(directory, "tst_motion.qml"));
    writeFileSync(join(directory, "qmldir"),
        "singleton AppearanceTokens 1.0 AppearanceTokens.qml\n"
        + "singleton InputMethodService 1.0 InputMethodService.qml\n"
        + "singleton PlatformClient 1.0 PlatformClient.qml\n"
        + "singleton WindowService 1.0 WindowService.qml\n");
    writeFileSync(join(directory, "PlatformClient.qml"), `pragma Singleton
import QtQuick
QtObject {
    property bool connected: false
    property var calls: []
    signal eventReceived(string eventName, var payload)
    signal transportChanged(bool connected)
    function supports(op) { return true }
    function request(op, payload, callback) { calls = calls.concat([{ op, payload, callback }]) }
}
`);
    writeFileSync(join(directory, "WindowService.qml"), `pragma Singleton
import QtQuick
QtObject {
    property string kwinActiveId: "window-a"
    property var records: []
}
`);
    writeFileSync(join(directory, "AppearanceTokens.qml"), `pragma Singleton
import QtQuick
QtObject {
    property QtObject motion: QtObject {
        property int popupOpenDuration: 150
        property int popupCloseDuration: 140
    }
}
`);
    const result = spawnSync(process.argv[2] || "qmltestrunner", ["-input", directory], {
        encoding: "utf8", timeout: 20000,
        env: { ...process.env, QT_QPA_PLATFORM: "offscreen", QT_QUICK_BACKEND: "software",
            WAYLAND_DISPLAY: "", DISPLAY: "" },
    });
    const output = (result.stdout || "") + (result.stderr || "");
    assert.equal(result.error, undefined, String(result.error) + "\n" + output);
    assert.equal(result.status, 0, output);
    assert.doesNotMatch(output, /FAIL!|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign/);
    console.log(output.trim());
} finally {
    rmSync(directory, { recursive: true, force: true });
}
